//Camera_Page.dart

import 'dart:io';
import 'dart:ui' as ui;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:hive_flutter/hive_flutter.dart';
import './models/session.dart';
import './models/session_model.dart';
import './services/session_service.dart';
import './services/tflite_service.dart';

class DetectionResult {
  final String label;
  final double confidence;
  final Rect boundingBox;

  DetectionResult({
    required this.label,
    required this.confidence,
    required this.boundingBox,
  });

  // Factory constructor to create DetectionResult from TFLite detection
  factory DetectionResult.fromTFLiteDetection(Map<String, double> detection) {
    return DetectionResult(
      label: 'Fish',
      confidence: detection['confidence']!,
      boundingBox: Rect.fromLTRB(
        detection['x1']!,
        detection['y1']!,
        detection['x2']!,
        detection['y2']!,
      ),
    );
  }
}

class CameraPage extends StatefulWidget {
  final String batchId;
  final String species;
  final String location;
  final String notes;

  const CameraPage({
    Key? key,
    required this.batchId,
    required this.species,
    required this.location,
    this.notes = '',
  }) : super(key: key);

  @override
  _CameraPageState createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription>? cameras;
  bool isProcessingImage = false;
  List<DetectionResult> _detections = [];
  Map<String, int> _counts = {};
  String timestamp = '';
  Timer? _timer;
  final SessionService _sessionService = SessionService();
  final TFLiteService _tfliteService = TFLiteService(); // Initialize TFLite service
  String? _lastCapturedImagePath;
  StreamSubscription? _batchResultSubscription;

  // Performance tracking
  List<Duration> _processingTimes = [];
  bool _isModelInitialized = false;
  String _modelStatus = 'Initializing...';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
    _initializeTFLiteService();
    _startTimestamp();
    _setupBatchResultListener();
  }

  Future<void> _initializeCamera() async {
    try {
      cameras = await availableCameras();
      if (cameras != null && cameras!.isNotEmpty) {
        _controller = CameraController(
          cameras![0],
          ResolutionPreset.high,
          enableAudio: false,
        );

        await _controller?.initialize();
        if (mounted) {
          setState(() {});
        }
      }
    } catch (e) {
      print('Error initializing camera: $e');
      if (mounted) {
        setState(() {
          _modelStatus = 'Camera initialization failed';
        });
      }
    }
  }

  Future<void> _initializeTFLiteService() async {
    try {
      setState(() {
        _modelStatus = 'Loading AI model...';
      });
      
      await _tfliteService.initialize();
      
      setState(() {
        _isModelInitialized = true;
        _modelStatus = 'Model ready';
      });
      
      print('TFLite service initialized successfully');
    } catch (e) {
      print('Error initializing TFLite service: $e');
      setState(() {
        _modelStatus = 'Model initialization failed: ${e.toString()}';
      });
    }
  }

  void _setupBatchResultListener() {
    _batchResultSubscription = _tfliteService.batchResults.listen((batchResult) {
      // Handle batch results if needed for bulk processing
      print('Batch result received: ${batchResult.successCount} successes, ${batchResult.failureCount} failures');
    });
  }

  void _startTimestamp() {
    _updateTimestamp();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        _updateTimestamp();
      }
    });
  }

  void _updateTimestamp() {
    if (mounted) {
      setState(() {
        timestamp = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
      });
    }
  }

  Future<void> _captureAndDetect() async {
    if (isProcessingImage || _controller == null || !_controller!.value.isInitialized) {
      return;
    }

    if (!_isModelInitialized) {
      _showErrorSnackBar('AI model is not ready yet. Please wait...');
      return;
    }

    setState(() {
      isProcessingImage = true;
      _detections = [];
    });

    final processingStopwatch = Stopwatch()..start();

    try {
      print('\n=== Starting capture and detection ===');
      
      // Capture image
      final XFile? imageFile = await _controller?.takePicture();
      if (imageFile == null) throw Exception('Failed to capture image');

      // Save image to permanent location
      final appDir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory('${appDir.path}/fish_images');
      if (!await imagesDir.exists()) {
        await imagesDir.create(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final newPath = '${imagesDir.path}/${widget.batchId}_$timestamp.jpg';
      final savedImage = await File(imageFile.path).copy(newPath);
      _lastCapturedImagePath = newPath;
      print('Image saved to: $newPath');

      // Perform TFLite detection
      final detectionCount = await _tfliteService.detectFingerlings(
        savedImage,
        confidenceThreshold: 0.5,
        nmsThreshold: 0.4,
      );

      processingStopwatch.stop();
      _processingTimes.add(processingStopwatch.elapsed);

      // Keep only last 10 processing times for average calculation
      if (_processingTimes.length > 10) {
        _processingTimes.removeAt(0);
      }

      // Create detection results for visualization
      // Note: The TFLiteService currently returns only count, but we can extend it to return full detection data
      final mockDetections = _createMockDetectionsForVisualization(detectionCount);

      setState(() {
        _detections = mockDetections;
        // Accumulate the fish count
        _counts['Fish'] = (_counts['Fish'] ?? 0) + detectionCount;
      });

      if (mounted) {
        final processingTime = processingStopwatch.elapsedMilliseconds;
        final avgProcessingTime = _processingTimes
            .map((d) => d.inMilliseconds)
            .reduce((a, b) => a + b) / _processingTimes.length;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Detected: $detectionCount fish (${processingTime}ms, avg: ${avgProcessingTime.toStringAsFixed(0)}ms)',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      processingStopwatch.stop();
      print('Error during capture and detection: $e');
      if (mounted) {
        _showErrorSnackBar('Detection failed: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() {
          isProcessingImage = false;
        });
      }
    }
  }

  // Helper method to create mock detections for visualization
  // This should be replaced with actual detection data from TFLiteService
  List<DetectionResult> _createMockDetectionsForVisualization(int count) {
    final List<DetectionResult> detections = [];
    
    // Create mock bounding boxes for visualization
    // In a real implementation, you'd modify TFLiteService to return detection coordinates
    for (int i = 0; i < count && i < 20; i++) { // Limit to 20 for performance
      detections.add(DetectionResult(
        label: 'Fish',
        confidence: 0.7 + (i * 0.05), // Mock confidence values
        boundingBox: Rect.fromLTWH(
          50.0 + (i * 30.0) % 300, // Mock x position
          50.0 + (i * 25.0) % 200, // Mock y position
          60.0, // Mock width
          40.0, // Mock height
        ),
      ));
    }
    
    return detections;
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _saveSession() async {
    if (_lastCapturedImagePath == null) {
      _showErrorSnackBar('No image captured yet!');
      return;
    }

    try {
      // Create and save Session for SharedPreferences
      final session = Session(
        id: const Uuid().v4(),
        batchId: widget.batchId,
        species: widget.species,
        location: widget.location,
        notes: widget.notes,
        counts: Map<String, int>.from(_counts),
        timestamp: timestamp,
        imageUrl: _lastCapturedImagePath!,
      );
      await _sessionService.saveSession(session);

      // Create and save SessionModel for Hive
      final sessionModel = SessionModel(
        batchId: widget.batchId,
        species: widget.species,
        location: widget.location,
        notes: widget.notes,
        date: DateTime.now(),
        count: _counts.values.fold(0, (sum, count) => sum + count),
      );
      final sessionsBox = Hive.box<SessionModel>('sessions');
      await sessionsBox.add(sessionModel);
      
      if (mounted) {
        Navigator.of(context).pop(); // Close the modal
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/dashboard',
          (route) => false, // Remove all previous routes
        );
      }
    } catch (e) {
      print('Error saving session: $e');
      if (mounted) {
        _showErrorSnackBar('Error saving session: ${e.toString()}');
      }
    }
  }

  void _showReviewModal() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Review Session'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Batch ID: ${widget.batchId}'),
                const SizedBox(height: 8),
                Text('Species: ${widget.species}'),
                const SizedBox(height: 8),
                Text('Location: ${widget.location}'),
                const SizedBox(height: 8),
                Text('Notes: ${widget.notes}'),
                const SizedBox(height: 16),
                const Text('Detected Counts:', style: TextStyle(fontWeight: FontWeight.bold)),
                ..._counts.entries
                    .where((e) => e.value > 0)
                    .map((e) => Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('${e.key}: ${e.value}'),
                        )),
                const SizedBox(height: 8),
                Text('Time: $timestamp'),
                if (_processingTimes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Avg Processing Time: ${_processingTimes.map((d) => d.inMilliseconds).reduce((a, b) => a + b) / _processingTimes.length}ms'),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: _saveSession,
              child: const Text('Save Session'),
            ),
          ],
        );
      },
    );
  }

  void _showPerformanceMetrics() {
    final metrics = _tfliteService.getPerformanceMetrics();
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Performance Metrics'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total Processed: ${metrics['totalProcessed']}'),
                Text('Average Processing Time: ${metrics['averageProcessingTime']?.toStringAsFixed(2) ?? 'N/A'}ms'),
                Text('Cache Size: ${metrics['cacheSize']}'),
                Text('Isolate Pool Size: ${metrics['isolatePoolSize']}'),
                Text('Batch Queue Size: ${metrics['batchQueueSize'] ?? 'N/A'}'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(_modelStatus),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fingerlings Detection'),
        actions: [
          // Model status indicator
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _isModelInitialized ? Colors.green : Colors.orange,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _isModelInitialized ? 'AI Ready' : 'Loading...',
                style: const TextStyle(fontSize: 12, color: Colors.white),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Count display
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.set_meal, size: 18),
                  const SizedBox(width: 4),
                  Text(
                    'Total: ${_counts['Fish'] ?? 0}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Performance metrics button
          IconButton(
            icon: const Icon(Icons.analytics),
            onPressed: _showPerformanceMetrics,
            tooltip: 'Performance Metrics',
          ),
          // Reset count button
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _counts = {};
                _detections = [];
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Count reset to 0'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            tooltip: 'Reset Count',
          ),
          // Save session button
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _showReviewModal,
            tooltip: 'Save Session',
          ),
        ],
      ),
      body: Stack(
        children: [
          CameraPreview(_controller!),
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Center(
              child: FloatingActionButton(
                onPressed: (isProcessingImage || !_isModelInitialized) ? null : _captureAndDetect,
                backgroundColor: _isModelInitialized ? null : Colors.grey,
                child: Icon(
                  isProcessingImage 
                    ? Icons.hourglass_empty 
                    : _isModelInitialized 
                      ? Icons.camera 
                      : Icons.warning
                ),
              ),
            ),
          ),
          Positioned(
            top: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    timestamp,
                    style: const TextStyle(color: Colors.white),
                  ),
                  if (_processingTimes.isNotEmpty)
                    Text(
                      'Avg: ${_processingTimes.map((d) => d.inMilliseconds).reduce((a, b) => a + b) / _processingTimes.length}ms',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                ],
              ),
            ),
          ),
          if (isProcessingImage)
            Container(
              color: Colors.black26,
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      'Processing image...',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    try {
      _timer?.cancel();
      _batchResultSubscription?.cancel();
      _controller?.dispose();
      WidgetsBinding.instance.removeObserver(this);
      // Note: Don't dispose TFLiteService here as it might be used by other parts of the app
      print('Camera disposed successfully');
    } catch (e) {
      print('Error during camera disposal: $e');
    } finally {
      super.dispose();
    }
  }
}