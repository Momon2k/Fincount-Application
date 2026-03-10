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
import './services/hybrid_session_service.dart';
import './services/user_session_manager.dart';
import './services/api_service.dart';
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
    super.key,
    required this.batchId,
    required this.species,
    required this.location,
    this.notes = '',
  });

  @override
  _CameraPageState createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription>? cameras;
  bool isProcessingImage = false;
  List<DetectionResult> _detections = [];
  Map<String, int> _counts = {};
  Map<String, int>? _lastValidCounts;
  List<DetectionResult>? _lastValidDetections;
  String timestamp = '';
  Timer? _timer;
  final HybridSessionService _hybridSessionService = HybridSessionService();
  final TFLiteService _tfliteService = TFLiteService();
  String? _lastCapturedImagePath;
  StreamSubscription? _batchResultSubscription;

  // Performance tracking
  final List<Duration> _processingTimes = [];
  bool _isModelInitialized = false;
  String _modelStatus = 'Initializing...';

  // Species enum mapping
  FishSpecies? _selectedSpecies;
  int _lastCaptureCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _mapSpeciesToEnum();
    _initializeCamera();
    _initializeTFLiteService();
    _startTimestamp();
    _setupBatchResultListener();
  }

  // Map the string species to FishSpecies enum
  void _mapSpeciesToEnum() {
    final speciesLower = widget.species.toLowerCase();
    if (speciesLower.contains('tilapia')) {
      _selectedSpecies = FishSpecies.tilapia;
    } else if (speciesLower.contains('bangus') ||
        speciesLower.contains('milkfish')) {
      _selectedSpecies = FishSpecies.bangus;
    } else {
      // Default to tilapia if unknown species
      _selectedSpecies = FishSpecies.tilapia;
      print(
          'Warning: Unknown species "${widget.species}", defaulting to Tilapia');
    }

    print('Selected species enum: ${_selectedSpecies?.name}');
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
        _modelStatus = 'Loading AI model for ${widget.species}...';
      });

      await _tfliteService.initialize();

      setState(() {
        _isModelInitialized = true;
        _modelStatus = 'Model ready (${_selectedSpecies?.name ?? 'unknown'})';
      });

      print(
          'TFLite service initialized successfully for ${_selectedSpecies?.name}');
    } catch (e) {
      print('Error initializing TFLite service: $e');
      setState(() {
        _modelStatus = 'Model initialization failed: ${e.toString()}';
      });
    }
  }

  void _setupBatchResultListener() {
    _batchResultSubscription =
        _tfliteService.batchResults.listen((batchResult) {
      // Handle batch results if needed for bulk processing
      print(
          'Batch result received: ${batchResult.successCount} successes, ${batchResult.failureCount} failures');
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
    if (isProcessingImage ||
        _controller == null ||
        !_controller!.value.isInitialized) {
      return;
    }

    if (!_isModelInitialized) {
      _showErrorSnackBar('AI model is not ready yet. Please wait...');
      return;
    }

    if (_selectedSpecies == null) {
      _showErrorSnackBar('Species not properly configured');
      return;
    }

    setState(() {
      isProcessingImage = true;
      _detections = [];
    });

    final processingStopwatch = Stopwatch()..start();

    try {
      print(
          '\n=== Starting capture and detection for ${_selectedSpecies?.name} ===');

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

      // Perform TFLite detection with the selected species model
      final detectionCount = await _tfliteService.detectFingerlings(
        savedImage,
        species: _selectedSpecies!,
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
      final mockDetections =
          _createMockDetectionsForVisualization(detectionCount);

      setState(() {
        _detections = mockDetections;
        _lastCaptureCount = detectionCount;
        // Accumulate the fish count
        _counts['Fish'] = (_counts['Fish'] ?? 0) + detectionCount;
        final total = _counts.values.fold(0, (sum, count) => sum + count);
        if (total > 0) {
          _lastValidCounts = Map<String, int>.from(_counts);
          _lastValidDetections = List<DetectionResult>.from(_detections);
        }
      });

      if (mounted) {
        final processingTime = processingStopwatch.elapsedMilliseconds;
        final avgProcessingTime = _processingTimes
                .map((d) => d.inMilliseconds)
                .reduce((a, b) => a + b) /
            _processingTimes.length;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Detected: $detectionCount ${widget.species} (${processingTime}ms, avg: ${avgProcessingTime.toStringAsFixed(0)}ms)',
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
  List<DetectionResult> _createMockDetectionsForVisualization(int count) {
    final List<DetectionResult> detections = [];

    // Create mock bounding boxes for visualization
    for (int i = 0; i < count && i < 20; i++) {
      // Limit to 20 for performance
      detections.add(DetectionResult(
        label: widget.species,
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

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const Center(
          child: CircularProgressIndicator(),
        );
      },
    );

    bool sessionSavedToServer = false;
    String errorMessage = '';

    try {
      String imageUrl = _lastCapturedImagePath!;

      print('=== Camera Page: Starting save session ===');

      // Check if online and try to upload image
      final isOnline = await _hybridSessionService.isOnline();
      print('Camera Page: Connection check result: $isOnline');

      if (isOnline) {
        try {
          // Upload image to server
          imageUrl = await ApiService.uploadImage(
            File(_lastCapturedImagePath!),
            widget.batchId,
          );
          print('Camera Page: Image uploaded successfully: $imageUrl');
        } catch (e) {
          print('Camera Page: Image upload failed, using local path: $e');
          // Continue with local path if upload fails
        }
      }

      // Create Session object
      final session = Session(
        id: const Uuid().v4(),
        batchId: widget.batchId,
        species: widget.species,
        location: widget.location,
        notes: widget.notes,
        counts: Map<String, int>.from(_counts),
        timestamp: timestamp,
        imageUrl: imageUrl,
      );

      print('Camera Page: Calling HybridSessionService.saveSession()');

      // Save using HybridSessionService (handles both local and API)
      try {
        await _hybridSessionService.saveSession(session);
        // If we reach here without exception, check if it was synced
        final isOnlineAfterSave = await _hybridSessionService.isOnline();
        sessionSavedToServer = isOnlineAfterSave;
        print(
            'Camera Page: Session save completed. Synced to server: $sessionSavedToServer');
      } catch (e) {
        print('Camera Page: Session save threw exception: $e');
        errorMessage = e.toString();
        // Session was saved locally but not to server
        sessionSavedToServer = false;
      }

      // Also save SessionModel for Hive (for local UI)
      final sessionModel = SessionModel(
        batchId: widget.batchId,
        species: widget.species,
        location: widget.location,
        notes: widget.notes,
        date: DateTime.now(),
        count: _counts.values.fold(0, (sum, count) => sum + count),
      );
      final sessionsBox = UserSessionManager.getCurrentUserBox();
      await sessionsBox.add(sessionModel);

      if (mounted) {
        _lastValidCounts = Map<String, int>.from(_counts);
        _lastValidDetections = List<DetectionResult>.from(_detections);
        Navigator.of(context).pop(); // Close loading dialog
        Navigator.of(context).pop(); // Close the review modal

        // Show success message based on actual result
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    sessionSavedToServer
                        ? 'Session saved to server successfully!'
                        : 'Session saved locally. Will sync when online.${errorMessage.isNotEmpty ? '\nError: $errorMessage' : ''}',
                  ),
                ),
              ],
            ),
            backgroundColor:
                sessionSavedToServer ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 4),
          ),
        );

        Navigator.pushNamedAndRemoveUntil(
          context,
          '/dashboard',
          (route) => false, // Remove all previous routes
        );
      }
    } catch (e) {
      print('Camera Page: Fatal error saving session: $e');
      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog
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
                Text('Species: ${widget.species} (${_selectedSpecies?.name})'),
                const SizedBox(height: 8),
                Text('Location: ${widget.location}'),
                const SizedBox(height: 8),
                Text('Notes: ${widget.notes}'),
                const SizedBox(height: 16),
                const Text('Detected Counts:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                ..._counts.entries.where((e) => e.value > 0).map((e) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('${e.key}: ${e.value}'),
                    )),
                const SizedBox(height: 8),
                Text('Time: $timestamp'),
                if (_processingTimes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                      'Avg Processing Time: ${(_processingTimes.map((d) => d.inMilliseconds).reduce((a, b) => a + b) / _processingTimes.length).toStringAsFixed(0)}ms'),
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

  void _showEditLastCaptureModal() {
    final controller = TextEditingController(text: '$_lastCaptureCount');
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Last Capture Count'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Detected Count: $_lastCaptureCount'),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Correct Count',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final text = controller.text.trim();
                final corrected = int.tryParse(text);
                if (corrected == null || corrected < 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter a valid non-negative number'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                  return;
                }
                final previous = _lastCaptureCount;
                final delta = corrected - previous;
                setState(() {
                  _lastCaptureCount = corrected;
                  _counts['Fish'] =
                      ((_counts['Fish'] ?? 0) + delta).clamp(0, 1 << 31);
                  _lastValidCounts = Map<String, int>.from(_counts);
                });
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content:
                        Text('Updated last capture: $previous → $corrected'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              child: const Text('Apply'),
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
                Text('Active Species: ${_selectedSpecies?.name ?? 'N/A'}'),
                const Divider(),
                Text('Total Processed: ${metrics['totalProcessed']}'),
                Text(
                    'Average Processing Time: ${metrics['averageProcessingTime']?.toStringAsFixed(2) ?? 'N/A'}ms'),
                Text('Cache Size: ${metrics['cacheSize']}'),
                Text('Isolate Pool Size: ${metrics['isolatePoolSize']}'),
                Text('Batch Queue Size: ${metrics['batchQueueSize'] ?? 'N/A'}'),
                const Divider(),
                const Text('Loaded Models:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                ...((metrics['loadedModels'] as List<dynamic>?) ?? [])
                    .map((model) => Padding(
                          padding: const EdgeInsets.only(left: 8, top: 4),
                          child: Row(
                            children: [
                              Icon(
                                model == _selectedSpecies?.name
                                    ? Icons.check_circle
                                    : Icons.circle_outlined,
                                size: 16,
                                color: model == _selectedSpecies?.name
                                    ? Colors.green
                                    : Colors.grey,
                              ),
                              const SizedBox(width: 4),
                              Text(model.toString()),
                            ],
                          ),
                        )),
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

  void _undoToLastValidCount() {
    final total =
        _lastValidCounts?.values.fold(0, (sum, count) => sum + count) ?? 0;
    if (total <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No valid count to restore'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    setState(() {
      _counts = Map<String, int>.from(_lastValidCounts!);
      _detections = List<DetectionResult>.from(_lastValidDetections ?? []);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Restored valid count: Total $total'),
        duration: const Duration(seconds: 2),
      ),
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
        automaticallyImplyLeading: false,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Material(
                color: Colors.blue.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _showEditLastCaptureModal,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Last',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$_lastCaptureCount',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.edit, size: 16),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: Colors.blue.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Total',
                      style:
                          TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${_counts['Fish'] ?? 0}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        titleSpacing: 12,
        actions: [
          const SizedBox(width: 12),
          // Performance metrics button
          IconButton(
            icon: const Icon(Icons.analytics, size: 20),
            onPressed: _showPerformanceMetrics,
            tooltip: 'Performance Metrics',
            visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
          ),
          const SizedBox(width: 8),
          // Undo to last valid count button
          IconButton(
            icon: const Icon(Icons.undo, size: 20),
            onPressed: _undoToLastValidCount,
            tooltip: 'Undo to last valid count',
            visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
          ),
          const SizedBox(width: 8),
          // Save session button
          IconButton(
            icon: const Icon(Icons.save, size: 20),
            onPressed: _showReviewModal,
            tooltip: 'Save Session',
            visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
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
                onPressed: (isProcessingImage || !_isModelInitialized)
                    ? null
                    : _captureAndDetect,
                backgroundColor: _isModelInitialized ? null : Colors.grey,
                child: Icon(isProcessingImage
                    ? Icons.hourglass_empty
                    : _isModelInitialized
                        ? Icons.camera
                        : Icons.warning),
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
                      'Avg: ${(_processingTimes.map((d) => d.inMilliseconds).reduce((a, b) => a + b) / _processingTimes.length).toStringAsFixed(0)}ms',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  Text(
                    'Model: ${_selectedSpecies?.name ?? 'N/A'}',
                    style: const TextStyle(
                        color: Colors.greenAccent, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
          if (isProcessingImage)
            Container(
              color: Colors.black26,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      'Detecting ${widget.species}...',
                      style: const TextStyle(color: Colors.white, fontSize: 16),
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
      print('Camera disposed successfully');
    } catch (e) {
      print('Error during camera disposal: $e');
    } finally {
      super.dispose();
    }
  }
}
