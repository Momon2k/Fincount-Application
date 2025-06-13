import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';

class ObjectDetectionService {
  late ObjectDetector _objectDetector;
  bool _isInitialized = false;
  List<Rect> _previousDetections = [];
  DateTime _lastDetectionTime = DateTime.now();

  // Constants for fingerling detection
  static const double MIN_CONFIDENCE = 0.25;  // Minimum confidence threshold for fingerling detection
  static const double MAX_RELATIVE_SIZE = 0.6; // Maximum size relative to image (increased for close-up shots)
  static const double MIN_RELATIVE_SIZE = 0.01; // Minimum size relative to image (for distant fingerlings)

  // Color ranges for red tilapia fingerlings
  static const double RED_THRESHOLD = 100;    // Lowered to catch lighter colored fish
  static const double GREEN_THRESHOLD = 130;   // Adjusted for blue background
  static const double BLUE_THRESHOLD = 130;    // Adjusted for blue background

  // Initialize the object detector with custom model
  Future<void> initialize() async {
    try {
      print('\n=== Initializing Object Detector ===');
      
      // Get the model file from assets
      final modelPath = await _getModel();
      print('Model path obtained: $modelPath');
      
      print('Creating detector options...');
      final options = LocalObjectDetectorOptions(
        mode: DetectionMode.single,  // Changed to single for more accurate processing
        modelPath: modelPath,
        classifyObjects: true,
        multipleObjects: true,
        confidenceThreshold: MIN_CONFIDENCE
      );
      print('Detector options created');
      
      print('Initializing detector...');
      _objectDetector = ObjectDetector(options: options);
      _isInitialized = true;
      print('Detector initialized successfully');
      
      // Verify detector
      if (_objectDetector == null) {
        throw Exception('Detector is null after initialization');
      }
      
      print('=== Initialization Complete ===\n');
    } catch (e) {
      print('\nERROR in initialization:');
      print('Error message: $e');
      print('Stack trace: ${StackTrace.current}');
      _isInitialized = false;
      throw Exception('Failed to initialize object detector: $e');
    }
  }

  Future<String> _getModel() async {
    try {
      print('\n=== Model Loading Process ===');
      // Get application documents directory
      final Directory appDir = await getApplicationDocumentsDirectory();
      final String modelPath = join(appDir.path, 'best_float32.tflite');
      print('Target model path: $modelPath');

      // Check if the model file already exists
      final File modelFile = File(modelPath);
      if (!await modelFile.exists()) {
        print('Model file not found in app directory, copying from assets...');
        try {
          // Ensure the directory exists
          if (!await appDir.exists()) {
            await appDir.create(recursive: true);
            print('Created app directory');
          }

          // Copy the model file from assets
          final ByteData data = await rootBundle.load('assets/best_float32.tflite');
          print('Model file loaded from assets: ${data.lengthInBytes} bytes');
          
          // Write to app directory
          final List<int> bytes = data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          );
          await modelFile.writeAsBytes(bytes, flush: true);
          print('Model file written successfully to: $modelPath');
          
          // Verify the written file
          if (await modelFile.exists()) {
            final fileSize = await modelFile.length();
            print('Verified written file size: $fileSize bytes');
            if (fileSize != data.lengthInBytes) {
              throw Exception('File size mismatch after writing');
            }
          } else {
            throw Exception('File not found after writing');
          }
        } catch (e) {
          print('Error copying model file: $e');
          print('Stack trace: ${StackTrace.current}');
          throw Exception('Failed to copy model file: $e');
        }
      } else {
        final fileSize = await modelFile.length();
        print('Using existing model file at: $modelPath');
        print('Existing file size: $fileSize bytes');
      }

      // Verify the model file is readable
      try {
        final modelBytes = await modelFile.readAsBytes();
        print('Successfully read model file: ${modelBytes.length} bytes');
        if (modelBytes.isEmpty) {
          throw Exception('Model file is empty');
        }
      } catch (e) {
        print('Error reading model file: $e');
        throw Exception('Failed to read model file: $e');
      }

      return modelPath;
    } catch (e) {
      print('Fatal error in _getModel: $e');
      print('Stack trace: ${StackTrace.current}');
      throw Exception('Failed to get model: $e');
    }
  }

  Future<List<DetectedObject>> detectObjects(File imageFile) async {
    if (!_isInitialized) {
      print('Initializing object detector...');
      await initialize();
    }

    try {
      print('\n=== Starting Detection Process ===');
      print('Input image path: ${imageFile.path}');
      print('Input image exists: ${await imageFile.exists()}');
      print('Input image size: ${await imageFile.length()} bytes');
      
      // Load and preprocess the image
      final bytes = await imageFile.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) throw Exception('Failed to decode image');
      
      // Resize to model input size
      final processedImage = img.copyResize(
        image,
        width: 640,
        height: 640,
        interpolation: img.Interpolation.cubic
      );
      
      // Convert to float32 format (normalize to [0,1])
      final normalized = img.Image.from(processedImage);
      for (var y = 0; y < normalized.height; y++) {
        for (var x = 0; x < normalized.width; x++) {
          final pixel = normalized.getPixel(x, y);
          normalized.setPixel(x, y, img.ColorRgba8(
            (pixel.r.toDouble() / 255.0).round(),
            (pixel.g.toDouble() / 255.0).round(),
            (pixel.b.toDouble() / 255.0).round(),
            pixel.a.toInt()
          ));
        }
      }
      
      // Save the processed image
      final tempDir = await getTemporaryDirectory();
      final tempPath = join(tempDir.path, 'processed_${DateTime.now().millisecondsSinceEpoch}.jpg');
      final processedFile = File(tempPath);
      await processedFile.writeAsBytes(img.encodeJpg(normalized, quality: 100));
      
      // Create input image with metadata
      final inputImage = InputImage.fromFile(processedFile);
      
      // Process with detector
      print('\n--- ML Kit Processing ---');
      print('Starting ML Kit object detection...');
      final objects = await _objectDetector.processImage(inputImage);
      print('ML Kit processing complete');
      print('Raw detections found: ${objects.length}');
      
      // Clean up temporary file
      await processedFile.delete();
      
      return objects;
    } catch (e) {
      print('\nERROR in detectObjects:');
      print('Error message: $e');
      print('Stack trace: ${StackTrace.current}');
      return [];
    }
  }

  Future<File> _preprocessImage(File imageFile) async {
    try {
      print('\n=== Image Preprocessing Steps ===');
      print('1. Reading image...');
      final bytes = await imageFile.readAsBytes();
      print('- Bytes read: ${bytes.length}');
      
      print('\n2. Decoding image...');
      final image = img.decodeImage(bytes);
      if (image == null) {
        throw Exception('Failed to decode image');
      }
      print('- Original dimensions: ${image.width}x${image.height}');

      print('\n3. Handling orientation...');
      var oriented = image;
      if (image.width < image.height) {
        print('- Rotating to landscape...');
        oriented = img.copyRotate(image, angle: 90);
        print('- After rotation: ${oriented.width}x${oriented.height}');
      }

      print('\n4. Applying color adjustments...');
      // Convert to float32 and normalize
      final targetSize = 640; // Changed to match common model input size
      var normalized = img.copyResize(
        oriented,
        width: targetSize,
        height: targetSize,
        interpolation: img.Interpolation.cubic
      );
      
      // Apply normalization to match model's expected input
      for (var y = 0; y < normalized.height; y++) {
        for (var x = 0; x < normalized.width; x++) {
          final pixel = normalized.getPixel(x, y);
          // Normalize to [0, 1] range and ensure proper type casting
          normalized.setPixel(x, y, img.ColorRgba8(
            (pixel.r.toDouble() / 255.0).round(),
            (pixel.g.toDouble() / 255.0).round(),
            (pixel.b.toDouble() / 255.0).round(),
            pixel.a.toInt()  // Properly cast alpha to int
          ));
        }
      }
      
      print('- Normalization applied');

      if (normalized.width != targetSize || normalized.height != targetSize) {
        throw Exception('Image resize failed. Got: ${normalized.width}x${normalized.height}, Expected: ${targetSize}x${targetSize}');
      }
      print('- Resized to: ${normalized.width}x${normalized.height}');

      print('\n5. Saving processed image...');
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final processedPath = join(tempDir.path, 'processed_$timestamp.jpg');
      
      // Save with high quality to preserve details
      final processedFile = File(processedPath);
      await processedFile.writeAsBytes(img.encodeJpg(normalized, quality: 100));
      
      // Save debug image
      final debugPath = join(tempDir.path, 'debug_$timestamp.jpg');
      await File(debugPath).writeAsBytes(img.encodeJpg(normalized, quality: 100));
      print('- Debug image saved to: $debugPath');

      return processedFile;
    } catch (e) {
      print('\nERROR in preprocessing:');
      print('Error message: $e');
      print('Stack trace: ${StackTrace.current}');
      throw e;
    }
  }

  img.Image _adjustColorBalance(img.Image image) {
    final output = img.Image.from(image);
    
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        
        // Get RGB values
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();
        
        // Check if pixel is in the blue background range
        if (b > 150 && b > r && b > g) {
          // Reduce blue intensity to make fish stand out more
          final newB = (b * 0.8).toInt().clamp(0, 255);
          output.setPixel(x, y, img.ColorRgba8(r, g, newB, pixel.a.toInt()));
        } else if (r > g && r > b) {
          // Enhance reddish colors (likely fish)
          final newR = (r * 1.2).toInt().clamp(0, 255);
          output.setPixel(x, y, img.ColorRgba8(newR, g, b, pixel.a.toInt()));
        }
      }
    }
    return output;
  }

  List<DetectedObject> _processDetections(
    List<DetectedObject> objects,
    double imageWidth,
    double imageHeight,
    DateTime currentTime
  ) {
    final validDetections = <DetectedObject>[];
    final now = DateTime.now();
    
    for (var object in objects) {
      // Enhanced size filtering
      final box = object.boundingBox;
      final relativeWidth = box.width / imageWidth;
      final relativeHeight = box.height / imageHeight;
      final relativeArea = relativeWidth * relativeHeight;
      final aspectRatio = box.width / box.height;
      
      print('\nEvaluating detection:');
      print('- Box dimensions: ${box.width}x${box.height}');
      print('- Relative area: $relativeArea');
      print('- Aspect ratio: $aspectRatio');
      
      // Skip if object size is outside acceptable range
      if (relativeArea > MAX_RELATIVE_SIZE || relativeArea < MIN_RELATIVE_SIZE) {
        print('Object filtered out due to size: $relativeArea');
        continue;
      }

      // Calculate enhanced confidence score
      double confidenceScore = 0.0;
      if (object.labels.isNotEmpty) {
        confidenceScore = object.labels.first.confidence;
        print('- Initial confidence: $confidenceScore');
        
        // Boost confidence based on aspect ratio (typical fingerling shape)
        if (aspectRatio >= 1.5 && aspectRatio <= 4.0) {  // Widened aspect ratio range
          final aspectBoost = 1.3;
          confidenceScore *= aspectBoost;
          print('- Applied aspect ratio boost: $aspectBoost');
        }
        
        // Boost confidence based on size
        final optimalArea = (MAX_RELATIVE_SIZE + MIN_RELATIVE_SIZE) / 2;
        final areaDifference = (relativeArea - optimalArea).abs();
        final areaBoost = 1.0 - (areaDifference / optimalArea);
        confidenceScore *= (1.0 + areaBoost * 0.3);
        print('- Applied area boost: ${1.0 + areaBoost * 0.3}');
        
        // Additional checks for movement patterns
        if (_previousDetections.isNotEmpty) {
          for (var prevBox in _previousDetections) {
            if (_isNearby(box, prevBox)) {
              confidenceScore *= 1.2;
              print('- Applied nearby detection boost: 1.2');
              break;
            }
          }
        }
      }

      print('- Final confidence: $confidenceScore');

      // Accept detections with sufficient confidence
      if (confidenceScore >= MIN_CONFIDENCE) {
        validDetections.add(object);
        print('Valid detection added. Box: ${object.boundingBox}, Confidence: $confidenceScore');
      } else {
        print('Detection rejected due to low confidence');
      }
    }

    return validDetections;
  }

  bool _isNearby(Rect current, Rect previous) {
    final centerX1 = current.left + current.width / 2;
    final centerY1 = current.top + current.height / 2;
    final centerX2 = previous.left + previous.width / 2;
    final centerY2 = previous.top + previous.height / 2;
    
    final distance = math.sqrt(
      math.pow(centerX2 - centerX1, 2) + math.pow(centerY2 - centerY1, 2)
    );
    
    // Consider "nearby" if within 1.5x the average of the objects' dimensions
    final threshold = (current.width + current.height + previous.width + previous.height) / 2.67;
    return distance <= threshold;
  }

  bool _isLikelyFishColor(Color color) {
    // Optimized for red tilapia coloration
    return color.red > RED_THRESHOLD && 
           color.green < GREEN_THRESHOLD && 
           color.blue < BLUE_THRESHOLD;
  }

  Color _calculateAverageColor(Rect box) {
    // Placeholder for color calculation
    // In a real implementation, you would sample pixels from the image
    // within the detection box and calculate their average
    return Colors.orange; // Default to orange for now
  }

  Future<Map<String, dynamic>> getDetectionResults(File imageFile) async {
    try {
      print('\n=== Starting getDetectionResults ===');
      print('Input image path: ${imageFile.path}');
      print('File exists: ${await imageFile.exists()}');
      print('File size: ${await imageFile.length()} bytes');

      if (!_isInitialized) {
        print('Initializing detector...');
        await initialize();
      }

      print('Detecting objects...');
      final objects = await detectObjects(imageFile);
      print('Detection complete. Found ${objects.length} objects');

      // Apply additional processing for better accuracy
      final processedImage = img.decodeImage(await imageFile.readAsBytes());
      if (processedImage != null) {
        // Apply image enhancements
        final enhanced = _adjustColorBalance(processedImage);
        final sharpened = _sharpenImage(enhanced);
        final equalized = _applyAdaptiveHistogramEqualization(sharpened);

        // Save enhanced image for debugging
        final tempDir = await getTemporaryDirectory();
        final enhancedPath = join(tempDir.path, 'enhanced_${DateTime.now().millisecondsSinceEpoch}.jpg');
        await File(enhancedPath).writeAsBytes(img.encodeJpg(equalized));
        print('Enhanced image saved to: $enhancedPath');
      }

      // Filter results
      final validObjects = objects.where((obj) {
        if (obj.labels.isEmpty) return false;
        final confidence = obj.labels.first.confidence;
        final box = obj.boundingBox;
        
        // Calculate aspect ratio
        final aspectRatio = box.width / box.height;
        
        print('Object evaluation:');
        print('- Confidence: $confidence');
        print('- Aspect ratio: $aspectRatio');
        print('- Box: $box');
        
        // Enhanced filtering criteria
        return confidence >= MIN_CONFIDENCE &&
               aspectRatio >= 1.5 && aspectRatio <= 3.5 && // Typical fish shape
               box.width >= 20 && box.height >= 10; // Minimum size thresholds
      }).toList();

      print('Valid objects after filtering: ${validObjects.length}');
      
      return {
        'fishCount': validObjects.length,
        'detectedObjects': validObjects,
        'totalObjects': objects.length,
      };
    } catch (e, stackTrace) {
      print('Error in getDetectionResults:');
      print('Error: $e');
      print('Stack trace: $stackTrace');
      return {
        'fishCount': 0,
        'detectedObjects': <DetectedObject>[],
        'totalObjects': 0,
        'error': e.toString(),
      };
    }
  }

  void dispose() {
    if (_isInitialized) {
      _objectDetector.close();
      _isInitialized = false;
    }
  }

  // Add new method for adaptive histogram equalization
  img.Image _applyAdaptiveHistogramEqualization(img.Image input) {
    final output = img.Image.from(input);
    final width = input.width;
    final height = input.height;
    
    // Process each color channel separately
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final pixel = input.getPixel(x, y);
        
        // Apply CLAHE-like enhancement
        final r = _enhanceChannel(pixel.r.toInt(), 2.0);
        final g = _enhanceChannel(pixel.g.toInt(), 1.8);
        final b = _enhanceChannel(pixel.b.toInt(), 1.8);
        
        output.setPixel(x, y, img.ColorRgba8(r, g, b, pixel.a.toInt()));
      }
    }
    return output;
  }

  int _enhanceChannel(int value, double factor) {
    final normalized = value / 255.0;
    final enhanced = math.pow(normalized, 1.0 / factor) * 255.0;
    return enhanced.clamp(0, 255).toInt();
  }

  img.Image _sharpenImage(img.Image input) {
    final output = img.Image.from(input);
    final width = input.width;
    final height = input.height;
    
    // Sharpening kernel
    const kernel = [
      [-1, -1, -1],
      [-1,  9, -1],
      [-1, -1, -1]
    ];
    
    // Apply convolution
    for (var y = 1; y < height - 1; y++) {
      for (var x = 1; x < width - 1; x++) {
        var r = 0, g = 0, b = 0;
        
        // Apply kernel
        for (var ky = -1; ky <= 1; ky++) {
          for (var kx = -1; kx <= 1; kx++) {
            final pixel = input.getPixel(x + kx, y + ky);
            final k = kernel[ky + 1][kx + 1];
            
            r += pixel.r.toInt() * k;
            g += pixel.g.toInt() * k;
            b += pixel.b.toInt() * k;
          }
        }
        
        // Clamp values
        r = r.clamp(0, 255);
        g = g.clamp(0, 255);
        b = b.clamp(0, 255);
        
        output.setPixel(x, y, img.ColorRgba8(r, g, b, input.getPixel(x, y).a.toInt()));
      }
    }
    return output;
  }
}

extension RectExtension on Rect {
  ui.Rect toRect() {
    return ui.Rect.fromLTWH(left.toDouble(), top.toDouble(), width.toDouble(), height.toDouble());
  }
}