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
import 'package:shared_preferences/shared_preferences.dart';
import './models/session.dart';
import './models/session_model.dart';
import './services/hybrid_session_service.dart';
import './services/api_service.dart';
import './services/tflite_service.dart';
import './services/user_session_manager.dart';

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
  String timestamp = '';
  Timer? _timer;
  final HybridSessionService _hybridSessionService = HybridSessionService();
  final TFLiteService _tfliteService = TFLiteService();
  String? _lastCapturedImagePath;
  StreamSubscription? _batchResultSubscription;
  String? _currentUserId; // ✅ Store current user ID

  // Performance tracking
  final List<Duration> _processingTimes = [];
  bool _isModelInitialized = false;
  String _modelStatus = 'Initializing...';

  // Species enum mapping
  FishSpecies? _selectedSpecies;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _mapSpeciesToEnum();
    _loadCurrentUserId(); // ✅ Load user ID on init
    _initializeCamera();
    _initializeTFLiteService();
    _startTimestamp();
    _setupBatchResultListener();
  }

  // ✅ Load current user ID from SharedPreferences
  Future<void> _loadCurrentUserId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _currentUserId = prefs.getString('user_id');

      if (_currentUserId == null) {
        print('Warning: No user_id found in SharedPreferences');
      } else {
        print('Loaded user_id: $_currentUserId');
      }
    } catch (e) {
      print('Error loading user_id: $e');
    }
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
        // Accumulate the fish count
        _counts['Fish'] = (_counts['Fish'] ?? 0) + detectionCount;
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

  // Parse error messages to identify specific error types
  Map<String, dynamic> _parseError(dynamic error) {
    final errorString = error.toString().toLowerCase();

    if (errorString.contains('foreign key') ||
        errorString.contains('foreignkeyviolation')) {
      return {
        'type': 'foreign_key_violation',
        'title': 'Account Data Out of Sync',
        'message':
            'Your account information is not properly synchronized with the server. This usually happens after database updates.',
        'action': 're_login',
        'actionText': 'Log Out & Re-login',
      };
    } else if (errorString.contains('user not found') ||
        errorString.contains('user_id') &&
            errorString.contains('not present')) {
      return {
        'type': 'user_not_found',
        'title': 'User Authentication Issue',
        'message':
            'Your user account cannot be found in the database. Please log out and log back in.',
        'action': 're_login',
        'actionText': 'Log Out & Re-login',
      };
    } else if (errorString.contains('no internet') ||
        errorString.contains('network') ||
        errorString.contains('connection')) {
      return {
        'type': 'network_error',
        'title': 'No Internet Connection',
        'message':
            'Your session has been saved locally and will sync automatically when you\'re back online.',
        'action': 'retry',
        'actionText': 'Retry Now',
      };
    } else if (errorString.contains('timeout')) {
      return {
        'type': 'timeout',
        'title': 'Request Timeout',
        'message':
            'The server took too long to respond. Your session is saved locally.',
        'action': 'retry',
        'actionText': 'Retry Sync',
      };
    } else if (errorString.contains('unauthorized') ||
        errorString.contains('401')) {
      return {
        'type': 'unauthorized',
        'title': 'Authentication Expired',
        'message': 'Your login session has expired. Please log in again.',
        'action': 're_login',
        'actionText': 'Go to Login',
      };
    } else {
      return {
        'type': 'unknown',
        'title': 'Session Save Error',
        'message':
            'An error occurred while saving the session. Data is saved locally.',
        'action': 'dismiss',
        'actionText': 'OK',
        'details': error.toString(),
      };
    }
  }

  // Show detailed error dialog with actionable options
  void _showErrorDialog(Map<String, dynamic> errorInfo) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                errorInfo['type'] == 'network_error'
                    ? Icons.wifi_off
                    : Icons.error_outline,
                color: errorInfo['type'] == 'network_error'
                    ? Colors.orange
                    : Colors.red,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  errorInfo['title'],
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(errorInfo['message']),
                if (errorInfo['details'] != null) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Technical Details:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      errorInfo['details'],
                      style: const TextStyle(
                          fontSize: 11, fontFamily: 'monospace'),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 20, color: Colors.blue[700]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Your session data is safe and saved locally.',
                          style:
                              TextStyle(fontSize: 12, color: Colors.blue[900]),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            if (errorInfo['action'] != 're_login')
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).pop(); // Close review modal
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/dashboard',
                    (route) => false,
                  );
                },
                child: const Text('Go to Dashboard'),
              ),
            if (errorInfo['action'] == 'retry')
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _retrySaveSession();
                },
                child: Text(errorInfo['actionText']),
              ),
            if (errorInfo['action'] == 're_login')
              ElevatedButton(
                onPressed: () => _promptReLogin(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                ),
                child: Text(errorInfo['actionText']),
              ),
            if (errorInfo['action'] == 'dismiss')
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).pop(); // Close review modal
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    '/dashboard',
                    (route) => false,
                  );
                },
                child: Text(errorInfo['actionText']),
              ),
          ],
        );
      },
    );
  }

  // Prompt user to re-login
  void _promptReLogin() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.logout, color: Colors.orange),
              SizedBox(width: 8),
              Text('Re-login Required'),
            ],
          ),
          content: const Text(
            'To fix this issue, you need to log out and log back in. This will refresh your account credentials and resolve the synchronization problem.\n\nYour unsaved session will remain in local storage.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pop(); // Close error dialog
                Navigator.of(context).pop(); // Close review modal
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/dashboard',
                  (route) => false,
                );
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  // Clear any persistent SnackBars
                  if (mounted) {
                    ScaffoldMessenger.of(context).clearSnackBars();
                  }

                  // Clear authentication tokens
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove('auth_token');
                  await prefs.remove('user_data');

                  if (mounted) {
                    // Navigate to login page
                    Navigator.of(context).pushNamedAndRemoveUntil(
                      '/login',
                      (route) => false,
                    );
                  }
                } catch (e) {
                  print('Error during logout: $e');
                  if (mounted) {
                    _showErrorSnackBar('Failed to log out: ${e.toString()}');
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
              ),
              child: const Text('Log Out Now'),
            ),
          ],
        );
      },
    );
  }

  // Retry saving session after error
  Future<void> _retrySaveSession() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'Retrying sync...',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
        );
      },
    );

    try {
      // Check connection first
      final isOnline = await _hybridSessionService.isOnline();

      if (!isOnline) {
        if (mounted) {
          Navigator.of(context).pop(); // Close loading dialog
          _showErrorSnackBar('Still offline. Session remains saved locally.');
        }
        return;
      }

      // Retry the session save
      if (_lastCapturedImagePath != null) {
        String imageUrl = _lastCapturedImagePath!;

        // Try to upload image
        try {
          imageUrl = await ApiService.uploadImage(
            File(_lastCapturedImagePath!),
            widget.batchId,
          );
        } catch (e) {
          print('Image upload failed during retry: $e');
        }

        // Create and save session
        final session = Session(
          id: const Uuid().v4(),
          batchId: widget.batchId,
          species: widget.species,
          location: widget.location,
          notes: widget.notes,
          counts: Map<String, int>.from(_counts),
          timestamp: timestamp,
          imageUrl: imageUrl,
          userId: _currentUserId, // ✅ Pass current user ID
        );

        await _hybridSessionService.saveSession(session);

        if (mounted) {
          Navigator.of(context).pop(); // Close loading dialog
          Navigator.of(context).pop(); // Close review modal

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 8),
                  Expanded(child: Text('Session synced successfully!')),
                ],
              ),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );

          Navigator.pushNamedAndRemoveUntil(
            context,
            '/dashboard',
            (route) => false,
          );
        }
      }
    } catch (e) {
      print('Retry failed: $e');
      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        final errorInfo = _parseError(e);
        _showErrorDialog(errorInfo);
      }
    }
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
        userId: _currentUserId, // ✅ Pass current user ID
      );

      print('Camera Page: Calling HybridSessionService.saveSession()');

      // Save using HybridSessionService (handles both local and API)
      final saveResult = await _hybridSessionService.saveSession(session);

      print('Save result: $saveResult');

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
        Navigator.of(context).pop(); // Close loading dialog
        Navigator.of(context).pop(); // Close the review modal

        // Show appropriate success message based on sync status
        final savedLocally = saveResult['savedLocally'] ?? false;
        final syncedToApi = saveResult['syncedToApi'] ?? false;
        final syncError = saveResult['syncError'];

        if (savedLocally && syncedToApi) {
          // Perfect - saved locally and synced to API
          ScaffoldMessenger.of(context)
            ..clearSnackBars() // Clear any existing snackbars
            ..showSnackBar(
              const SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.cloud_done, color: Colors.white),
                    SizedBox(width: 8),
                    Expanded(child: Text('Session saved and synced to cloud!')),
                  ],
                ),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
        } else if (savedLocally && !syncedToApi) {
          // Saved locally but not synced - this is still success!
          ScaffoldMessenger.of(context)
            ..clearSnackBars() // Clear any existing snackbars
            ..showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.save, color: Colors.white),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        syncError?.contains('internet') ?? false
                            ? 'Session saved locally. Will sync when online.'
                            : 'Session saved locally. Sync pending.',
                      ),
                    ),
                  ],
                ),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 3),
                action: SnackBarAction(
                  label: 'Details',
                  textColor: Colors.white,
                  onPressed: () {
                    // Show more info about the sync error
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.blue),
                            SizedBox(width: 8),
                            Text('Sync Status'),
                          ],
                        ),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '✓ Session saved locally',
                              style: TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              '⚠ Cloud sync pending',
                              style: TextStyle(
                                  color: Colors.orange,
                                  fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 16),
                            if (syncError != null) Text('Reason: $syncError'),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.blue[50],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Your data is safe! The app will automatically sync to the cloud when you\'re back online.',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('OK'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            );
        } else {
          // This shouldn't happen, but handle it
          ScaffoldMessenger.of(context)
            ..clearSnackBars() // Clear any existing snackbars
            ..showSnackBar(
              const SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.save, color: Colors.white),
                    SizedBox(width: 8),
                    Expanded(child: Text('Session processed')),
                  ],
                ),
                backgroundColor: Colors.blue,
                duration: Duration(seconds: 2),
              ),
            );
        }

        Navigator.pushNamedAndRemoveUntil(
          context,
          '/dashboard',
          (route) => false,
        );
      }
    } catch (e) {
      print('Camera Page: Error saving session: $e');

      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        Navigator.of(context).pop(); // Close the review modal

        // Show error message but still navigate to dashboard
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Session saved locally. Error: ${e.toString()}'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );

        Navigator.pushNamedAndRemoveUntil(
          context,
          '/dashboard',
          (route) => false,
        );
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
        title: Text('${widget.species} Detection'),
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
