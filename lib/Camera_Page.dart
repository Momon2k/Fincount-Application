import 'package:image/image.dart' as img;
import 'dart:typed_data';
import 'dart:math';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:uuid/uuid.dart';
import './models/session.dart';
import './services/session_service.dart';
import 'Dashboard_Page.dart';
import 'package:crypto/crypto.dart';


class DetectionResult {
  final String label;
  final double confidence;
  final Rect boundingBox;

  DetectionResult({
    required this.label,
    required this.confidence,
    required this.boundingBox,
  });
}

class MLKitDetector {
  ObjectDetector? _detector;
  List<String> _labels = [];
  static const double confidenceThreshold = 0.3;
  static const int inputSize = 640;
  Map<String, int> objectCounts = {};

  // ImageNet normalization parameters
  static const double meanR = 0.485;
  static const double meanG = 0.456;
  static const double meanB = 0.406;
  static const double stdR = 0.229;
  static const double stdG = 0.224;
  static const double stdB = 0.225;

  // Function to preprocess and normalize image
  img.Image preprocessImage(img.Image image) {
    try {
      // Resize the image to match the model's expected input size
      image = img.copyResize(
        image,
        width: inputSize,
        height: inputSize,
        interpolation: img.Interpolation.linear
      );

      // Validate image dimensions
      if (image.width != inputSize || image.height != inputSize) {
        throw Exception('Invalid image dimensions after resizing: ${image.width}x${image.height}');
      }

      // Create a new image for normalized values
      final normalizedImage = img.Image(width: inputSize, height: inputSize);

      // Normalize pixel values to [0, 1] range
      for (int y = 0; y < image.height; y++) {
        for (int x = 0; x < image.width; x++) {
          final pixel = image.getPixel(x, y);
          
          // Extract RGB values using pixel properties
          final r = pixel.rNormalized;  // Already in range 0.0-1.0
          final g = pixel.gNormalized;
          final b = pixel.bNormalized;
          
          // Apply ImageNet normalization
          final normalizedR = ((r - meanR) / stdR).clamp(0.0, 1.0);
          final normalizedG = ((g - meanG) / stdG).clamp(0.0, 1.0);
          final normalizedB = ((b - meanB) / stdB).clamp(0.0, 1.0);
          
          // Convert back to [0, 255] range for image storage
          final int finalR = (normalizedR * 255).round();
          final int finalG = (normalizedG * 255).round();
          final int finalB = (normalizedB * 255).round();
          
          // Set normalized pixel values
          normalizedImage.setPixelRgba(x, y, finalR, finalG, finalB, 255);
        }
      }

      return normalizedImage;
    } catch (e) {
      print('Error in preprocessImage: $e');
      rethrow;
    }
  }

  // Function to compute SHA-256 hash of a file
  Future<String> _computeFileHash(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final hash = sha256.convert(bytes);
      return hash.toString();
    } catch (e) {
      print('Error computing file hash: $e');
      rethrow;
    }
  }

  Future<String> _getLocalPath(String assetPath) async {
    try {
      // Get the model file from assets
      final modelData = await rootBundle.load('assets/$assetPath');
      final bytes = modelData.buffer.asUint8List();

      // Get the app's local directory
      final appDir = await getApplicationDocumentsDirectory();
      final modelFile = File('${appDir.path}/$assetPath');

      // Create the directory if it doesn't exist
      if (!await modelFile.parent.exists()) {
        await modelFile.parent.create(recursive: true);
      }

      // Check if model file exists and verify its integrity
      if (await modelFile.exists()) {
        // Compute hash of existing file
        final existingHash = await _computeFileHash(modelFile);
        // Compute hash of new file
        final newHash = sha256.convert(bytes).toString();
        
        if (existingHash == newHash) {
          print('Model file exists and is valid at: ${modelFile.path}');
          return modelFile.path;
        } else {
          print('Model file exists but is invalid. Replacing...');
          await modelFile.delete();
        }
      }

      // Write the model to local storage
      await modelFile.writeAsBytes(bytes);
      print('Model copied to: ${modelFile.path}');
      
      // Verify the written file
      final writtenHash = await _computeFileHash(modelFile);
      final expectedHash = sha256.convert(bytes).toString();
      
      if (writtenHash != expectedHash) {
        throw Exception('Model file integrity check failed');
      }

      return modelFile.path;
    } catch (e) {
      print('Error copying model file: $e');
      rethrow;
    }
  }

  Future<InputImage> _preprocessImage(String imagePath) async {
    File? tempFile;
    try {
      final File imageFile = File(imagePath);
      if (!await imageFile.exists()) {
        throw Exception('Image file not found: $imagePath');
      }

      // Verify file size
      final fileSize = await imageFile.length();
      if (fileSize == 0) {
        throw Exception('Image file is empty: $imagePath');
      }
      print('Original image file size: $fileSize bytes');

      // Verify file is a valid image
      final bytes = await imageFile.readAsBytes();
      final img.Image? originalImage = img.decodeImage(bytes);
      if (originalImage == null) {
        throw Exception('Failed to decode image: Invalid image format');
      }

      print('Original image size: ${originalImage.width}x${originalImage.height}');
      if (originalImage.width == 0 || originalImage.height == 0) {
        throw Exception('Invalid image dimensions: ${originalImage.width}x${originalImage.height}');
      }

      // Calculate scaling to maintain aspect ratio
      double scale = inputSize / math.max(originalImage.width, originalImage.height);
      int newWidth = (originalImage.width * scale).round();
      int newHeight = (originalImage.height * scale).round();

      // Resize the image while maintaining aspect ratio
      final img.Image resizedImage = img.copyResize(
        originalImage,
        width: newWidth,
        height: newHeight,
        interpolation: img.Interpolation.linear
      );

      print('Resized image size: ${resizedImage.width}x${resizedImage.height}');

      // Create a new black image with padding
      final img.Image paddedImage = img.Image(width: inputSize, height: inputSize);

      // Fill with black padding
      for (int y = 0; y < inputSize; y++) {
        for (int x = 0; x < inputSize; x++) {
          paddedImage.setPixelRgba(x, y, 0, 0, 0, 255);
        }
      }

      // Calculate padding
      int xOffset = ((inputSize - newWidth) / 2).round();
      int yOffset = ((inputSize - newHeight) / 2).round();

      // Copy the resized image onto the padded image
      for (int y = 0; y < resizedImage.height; y++) {
        for (int x = 0; x < resizedImage.width; x++) {
          final pixel = resizedImage.getPixel(x, y);
          // Extract RGB values using pixel properties
          final r = pixel.r;  // Already in range 0-255
          final g = pixel.g;
          final b = pixel.b;
          final a = pixel.a;
          
          paddedImage.setPixelRgba(x + xOffset, y + yOffset, r, g, b, a);
        }
      }

      // Apply normalization to the padded image
      final normalizedImage = preprocessImage(paddedImage);

      // Save the preprocessed image to a temporary file
      final Directory tempDir = await getTemporaryDirectory();
      final String tempPath = '${tempDir.path}/preprocessed_${DateTime.now().millisecondsSinceEpoch}.jpg';
      tempFile = File(tempPath);
      
      // Write file synchronously to ensure it's complete before processing
      final jpgBytes = img.encodeJpg(normalizedImage, quality: 100);
      await tempFile.writeAsBytes(jpgBytes);
      
      // Verify the written file
      if (!await tempFile.exists()) {
        throw Exception('Failed to save preprocessed image');
      }
      
      final processedFileSize = await tempFile.length();
      if (processedFileSize == 0) {
        throw Exception('Preprocessed image file is empty');
      }
      
      // Verify the saved file can be decoded
      final savedImage = img.decodeImage(await tempFile.readAsBytes());
      if (savedImage == null) {
        throw Exception('Failed to verify saved preprocessed image');
      }
      
      print('Preprocessed image saved to: $tempPath');
      print('Preprocessed image size: ${normalizedImage.width}x${normalizedImage.height}');
      print('Preprocessed file size: $processedFileSize bytes');

      // Create InputImage from File object
      return InputImage.fromFile(tempFile);
    } catch (e) {
      print('Error preprocessing image: $e');
      // Clean up temporary file if it exists
      if (tempFile != null && await tempFile.exists()) {
        try {
          await tempFile.delete();
          print('Cleaned up temporary file after error');
        } catch (e) {
          print('Failed to clean up temporary file: $e');
        }
      }
      rethrow;
    }
  }

  Future<void> loadModel() async {
    try {
      // Load labels
      final labelData = await rootBundle.loadString('assets/label.txt');
      _labels = labelData.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      print('Labels loaded: $_labels');

      // Initialize counts
      for (var label in _labels) {
        objectCounts[label] = 0;
      }

      // Get model path from assets
      final modelPath = await _getLocalPath('model.tflite');
      print('Model path: $modelPath');

      final options = LocalObjectDetectorOptions(
        mode: DetectionMode.stream,
        modelPath: modelPath,
        classifyObjects: true,
        multipleObjects: true,
        confidenceThreshold: confidenceThreshold,
      );
      
      _detector = ObjectDetector(options: options);
      print('✅ Model loaded successfully');
    } catch (e, stackTrace) {
      print('❌ Error loading model: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }

  Future<(List<DetectionResult>, Map<String, int>)> detectObjects(String imagePath) async {
    File? tempFile;
    try {
      print('\n=== Starting detection ===');
      print('Processing image: $imagePath');
      
      if (_detector == null) {
        print('Initializing detector...');
        await loadModel();
        if (_detector == null) {
          throw Exception('Failed to initialize detector');
        }
      }
      
      // Verify input file exists and is valid
      final inputFile = File(imagePath);
      if (!await inputFile.exists()) {
        throw Exception('Input image file not found: $imagePath');
      }
      
      final inputFileSize = await inputFile.length();
      if (inputFileSize == 0) {
        throw Exception('Input image file is empty');
      }
      print('Input file size: $inputFileSize bytes');
      
      // Reset counts for new detection
      objectCounts.updateAll((key, value) => 0);
      
      // Preprocess the image
      final inputImage = await _preprocessImage(imagePath);
      print('Image preprocessed successfully');
      
      // Store reference to temporary file for cleanup
      tempFile = File(inputImage.filePath!);
      
      // Verify the preprocessed image file
      if (!await tempFile.exists()) {
        throw Exception('Preprocessed image file not found: ${inputImage.filePath}');
      }
      
      final preprocessedFileSize = await tempFile.length();
      if (preprocessedFileSize == 0) {
        throw Exception('Preprocessed image file is empty');
      }
      print('Preprocessed file size: $preprocessedFileSize bytes');
      
      // Process the image
      print('Starting object detection...');
      final List<DetectedObject> objects = await _detector!.processImage(inputImage);
      print('Raw detections: ${objects.length} objects found');
      
      final List<DetectionResult> results = objects.map((object) {
        final rect = object.boundingBox;
        String label = 'Unknown';
        double confidence = 0.0;
        
        if (object.labels.isNotEmpty) {
          final bestLabel = object.labels.reduce((a, b) => a.confidence > b.confidence ? a : b);
          label = bestLabel.text;
          confidence = bestLabel.confidence;
          
          // Increment count for this class
          objectCounts[label] = (objectCounts[label] ?? 0) + 1;
          
          print('Detection: $label with confidence ${(confidence * 100).toStringAsFixed(5)}%');
        }
        
        return DetectionResult(
          label: label,
          confidence: confidence,
          boundingBox: rect,
        );
      }).where((result) => result.confidence >= confidenceThreshold).toList();

      // Print counts
      objectCounts.forEach((label, count) {
        if (count > 0) {
          print('Counted $count $label');
        }
      });

      print('Detection complete. Found ${results.length} valid objects');
      
      // Create a new Map<String, int> with the correct types
      final Map<String, int> typedCounts = Map<String, int>.from(objectCounts);
      
      return (results, typedCounts);
    } catch (e, stackTrace) {
      print('❌ Error during detection: $e');
      print('Stack trace: $stackTrace');
      return (<DetectionResult>[], <String, int>{});
    } finally {
      // Clean up temporary file
      if (tempFile != null && await tempFile.exists()) {
        try {
          await tempFile.delete();
          print('Temporary file cleaned up successfully');
        } catch (e) {
          print('Warning: Could not delete temporary file: $e');
        }
      }
    }
  }

  void dispose() {
    _detector?.close();
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
  String timestamp = '';
  Timer? _timer;
  String? _lastCapturedImagePath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
    _startTimestamp();
  }

  Future<void> _initializeCamera() async {
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

  Future<void> _captureImage() async {
    if (isProcessingImage || _controller == null || !_controller!.value.isInitialized) {
      return;
    }

    setState(() {
      isProcessingImage = true;
    });

    try {
      final XFile? imageFile = await _controller?.takePicture();
      if (imageFile == null) throw Exception('Failed to capture image');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Image captured successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Error during capture: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isProcessingImage = false;
        });
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
                const SizedBox(height: 8),
                Text('Time: $timestamp'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/dashboard',
                  (route) => false,
                );
              },
              child: const Text('Save Session'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fingerlings Detection'),
        actions: [
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
                onPressed: isProcessingImage ? null : _captureImage,
                child: Icon(isProcessingImage ? Icons.hourglass_empty : Icons.camera),
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
              child: Text(
                timestamp,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

class DetectionPainter extends CustomPainter {
  final List<DetectionResult> detections;
  final Size previewSize;
  final Size screenSize;
  late final TextPainter textPainter;

  DetectionPainter({
    required this.detections,
    required this.previewSize,
    required this.screenSize,
  }) {
    textPainter = TextPainter(
      textAlign: TextAlign.left,
      textDirection: ui.TextDirection.ltr,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Colors.green;

    for (var detection in detections) {
      final scaleX = screenSize.width / previewSize.width;
      final scaleY = screenSize.height / previewSize.height;

      final scaledRect = Rect.fromLTRB(
        detection.boundingBox.left * scaleX,
        detection.boundingBox.top * scaleY,
        detection.boundingBox.right * scaleX,
        detection.boundingBox.bottom * scaleY,
      );

      canvas.drawRect(scaledRect, paint);

      textPainter.text = TextSpan(
        text: '${detection.label} ${(detection.confidence * 100).toStringAsFixed(0)}%',
        style: const TextStyle(
          color: Colors.green,
          fontSize: 16,
          backgroundColor: Colors.black54,
        ),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(scaledRect.left, scaledRect.top - 20),
      );
    }
  }

  @override
  bool shouldRepaint(DetectionPainter oldDelegate) {
    return oldDelegate.detections != detections;
  }
}