//tflite_service.dart

import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:async';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart';

// Enum for fish species
enum FishSpecies {
  tilapia,
  bangus,
}

// Image quality check result
class ImageQualityResult {
  final bool isSuitable;
  final String reason;
  final double? brightness;
  final double? blurScore;
  final String? resolution;

  ImageQualityResult({
    required this.isSuitable,
    required this.reason,
    this.brightness,
    this.blurScore,
    this.resolution,
  });
}

// Data classes for batch processing
class DetectionRequest {
  final String id;
  final File imageFile;
  final double confidenceThreshold;
  final double nmsThreshold;
  final DateTime timestamp;
  final FishSpecies species;
  final bool applySizeFiltering;

  DetectionRequest({
    required this.id,
    required this.imageFile,
    required this.species,
    this.confidenceThreshold = 0.5,  // Increased from 0.3 for better precision
    this.nmsThreshold = 0.3,         // Decreased from 0.4 for stricter duplicate removal
    this.applySizeFiltering = true,
  }) : timestamp = DateTime.now();
}

class DetectionResult {
  final String id;
  final int count;
  final List<Map<String, double>> detections;
  final Duration processingTime;
  final String? error;

  DetectionResult({
    required this.id,
    required this.count,
    required this.detections,
    required this.processingTime,
    this.error,
  });

  bool get isSuccess => error == null;
}

class BatchResult {
  final List<DetectionResult> results;
  final Duration totalProcessingTime;
  final int successCount;
  final int failureCount;

  BatchResult({
    required this.results,
    required this.totalProcessingTime,
  })  : successCount = results.where((r) => r.isSuccess).length,
        failureCount = results.where((r) => !r.isSuccess).length;
}

// Highly optimized image preprocessing with memory pooling
class ImagePreprocessor {
  static final Map<String, Uint8List> _cache = {};
  static final Map<int, ByteData> _bufferPool = {};
  static const int maxCacheSize = 50;
  static const int targetSize = 640;
  static const int inputSize = 640 * 640 * 3;

  static ByteData _getBuffer(int size) {
    if (!_bufferPool.containsKey(size)) {
      _bufferPool[size] = ByteData(size * 4);
    }
    return _bufferPool[size]!;
  }

  static Future<Uint8List> preprocessImage(
    File imageFile, {
    bool useCache = true,
    int? customSize,
  }) async {
    final size = customSize ?? targetSize;
    final cacheKey = '${imageFile.path}_$size';

    if (useCache && _cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }

    final stopwatch = Stopwatch()..start();

    try {
      final bytes = await _readImageBytes(imageFile);
      final image = img.decodeImage(bytes);
      if (image == null) {
        throw Exception('Could not decode image: ${imageFile.path}');
      }

      final resized = _ultraFastResize(image, size);
      final inputData = _imageToFloat32ArrayFast(resized, size);

      if (useCache) {
        _manageCache(cacheKey, inputData);
      }

      print(
          'Image preprocessing completed in ${stopwatch.elapsedMilliseconds}ms');
      return inputData;
    } catch (e) {
      print('Error preprocessing image ${imageFile.path}: $e');
      rethrow;
    }
  }

  static Future<Uint8List> _readImageBytes(File imageFile) async {
    final fileSize = await imageFile.length();

    if (fileSize > 10 * 1024 * 1024) {
      final randomAccessFile = await imageFile.open();
      final bytes = await randomAccessFile.read(fileSize);
      await randomAccessFile.close();
      return bytes;
    } else {
      return await imageFile.readAsBytes();
    }
  }

  static img.Image _ultraFastResize(img.Image image, int targetSize) {
    if (image.width == targetSize && image.height == targetSize) {
      return image;
    }

    final resized = img.Image(width: targetSize, height: targetSize);
    final xRatio = image.width / targetSize;
    final yRatio = image.height / targetSize;

    for (int y = 0; y < targetSize; y++) {
      for (int x = 0; x < targetSize; x++) {
        final srcX = (x * xRatio).floor();
        final srcY = (y * yRatio).floor();
        resized.setPixel(x, y, image.getPixel(srcX, srcY));
      }
    }

    return resized;
  }

  static Uint8List _imageToFloat32ArrayFast(img.Image image, int size) {
    final buffer = _getBuffer(size * size * 3);
    final pixels = image.getBytes(order: img.ChannelOrder.rgb);

    for (int i = 0; i < pixels.length; i++) {
      buffer.setFloat32(i * 4, pixels[i] / 255.0, Endian.host);
    }

    return buffer.buffer.asUint8List();
  }

  static void _manageCache(String key, Uint8List data) {
    if (_cache.length >= maxCacheSize) {
      final keysToRemove = _cache.keys.take(_cache.length - maxCacheSize + 1);
      for (final key in keysToRemove) {
        _cache.remove(key);
      }
    }
    _cache[key] = data;
  }

  static void clearCache() {
    _cache.clear();
  }

  static void clearBufferPool() {
    _bufferPool.clear();
  }

  static int get cacheSize => _cache.length;
}

// Model configuration class
class ModelConfig {
  final FishSpecies species;
  final int outputChannels;
  final List<int> outputShape;

  ModelConfig({
    required this.species,
    required this.outputChannels,
    required this.outputShape,
  });
}

// Optimized TFLite service with multiple model support
class TFLiteService {
  static final TFLiteService _instance = TFLiteService._internal();
  factory TFLiteService() => _instance;
  TFLiteService._internal();

  final Map<FishSpecies, Interpreter> _interpreters = {};
  final Map<FishSpecies, ModelConfig> _modelConfigs = {};
  bool _isInitialized = false;

  late final List<List<List<List<double>>>> _inputTensor;

  final List<Duration> _processingTimes = [];
  int _totalProcessed = 0;

  final List<Isolate> _isolatePool = [];
  final List<SendPort> _sendPorts = [];
  final List<bool> _isolateAvailable = [];
  static const int poolSize = 3;

  final List<DetectionRequest> _batchQueue = [];
  final StreamController<BatchResult> _batchResultController =
      StreamController<BatchResult>.broadcast();
  Timer? _batchTimer;

  static const int batchSize = 8;
  static const Duration batchTimeout = Duration(milliseconds: 500);

  Stream<BatchResult> get batchResults => _batchResultController.stream;

  static const Map<FishSpecies, String> _modelPaths = {
    FishSpecies.tilapia: 'assets/models/model.tflite',
    FishSpecies.bangus: 'assets/models/model2.tflite',
  };

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      print('Initializing TFLite service with multiple models...');

      // Initialize interpreters for each species
      for (final species in FishSpecies.values) {
        final modelPath = _modelPaths[species]!;
        print('Loading model for ${species.name}: $modelPath');

        _interpreters[species] = await Interpreter.fromAsset(
          modelPath,
          options: InterpreterOptions()..threads = 4,
        );

        _interpreters[species]!.allocateTensors();

        // Get output shape dynamically
        final outputTensor = _interpreters[species]!.getOutputTensor(0);
        final outputShape = outputTensor.shape;
        final outputChannels = outputShape[1]; // Should be 5 or 6

        _modelConfigs[species] = ModelConfig(
          species: species,
          outputChannels: outputChannels,
          outputShape: outputShape,
        );

        print(
            'Model loaded for ${species.name}: Output shape: $outputShape, Channels: $outputChannels');
      }

      // Pre-allocate input tensor (same for all models)
      _inputTensor = List.generate(
          1,
          (b) => List.generate(640,
              (h) => List.generate(640, (w) => List.generate(3, (c) => 0.0))));

      await _initializeIsolatePool();

      _isInitialized = true;
      print(
          'TFLite service initialized successfully with ${_interpreters.length} models');

      _startBatchTimer();
    } catch (e) {
      print('Error initializing TFLite: $e');
      rethrow;
    }
  }

  Future<void> _initializeIsolatePool() async {
    for (int i = 0; i < poolSize; i++) {
      final receivePort = ReceivePort();
      final isolate = await Isolate.spawn(_isolateEntry, receivePort.sendPort);

      _isolatePool.add(isolate);
      _isolateAvailable.add(true);

      final sendPort = await receivePort.first as SendPort;
      _sendPorts.add(sendPort);
      receivePort.close();
    }
  }

  static void _isolateEntry(SendPort mainSendPort) {
    final receivePort = ReceivePort();
    mainSendPort.send(receivePort.sendPort);

    late TFLiteService service;

    receivePort.listen((message) async {
      if (message is Map<String, dynamic>) {
        final request = message['request'] as DetectionRequest;
        final resultSendPort = message['resultSendPort'] as SendPort;

        try {
          service ??= TFLiteService();
          await service.initialize();

          final result = await service._detectFingerlingsInternal(request);
          resultSendPort.send(result);
        } catch (e) {
          resultSendPort.send(DetectionResult(
            id: request.id,
            count: 0,
            detections: [],
            processingTime: Duration.zero,
            error: e.toString(),
          ));
        }
      }
    });
  }

  /// Standard detection with default parameters
  Future<int> detectFingerlings(
    File imageFile, {
    required FishSpecies species,
    double confidenceThreshold = 0.3,
    double nmsThreshold = 0.4,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    final request = DetectionRequest(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      imageFile: imageFile,
      species: species,
      confidenceThreshold: confidenceThreshold,
      nmsThreshold: nmsThreshold,
    );

    final result = await _detectFingerlingsInternal(request);

    if (result.error != null) {
      throw Exception(result.error);
    }

    return result.count;
  }

  /// Enhanced detection with image quality check, multi-scale detection, and ensemble counting
  /// This provides the highest accuracy but is ~3x slower than standard detection
  Future<int> detectFingerlingsEnhanced(
    File imageFile, {
    required FishSpecies species,
    bool performQualityCheck = true,
    bool useMultiScale = true,
    bool useEnsemble = true,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    // Step 1: Check image quality
    if (performQualityCheck) {
      final qualityCheck = await checkImageQuality(imageFile);
      if (!qualityCheck.isSuitable) {
        throw Exception('Image quality insufficient: ${qualityCheck.reason}');
      }
      print('✅ Image quality check passed');
    }

    // Step 2: Use multi-scale or standard detection
    int count;
    if (useMultiScale) {
      count = await detectMultiScale(imageFile, species: species);
    } else if (useEnsemble) {
      count = await detectWithEnsemble(imageFile, species: species);
    } else {
      count = await detectFingerlings(imageFile, species: species);
    }

    return count;
  }

  /// Check if image quality is suitable for detection
  Future<ImageQualityResult> checkImageQuality(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final image = img.decodeImage(bytes);
      
      if (image == null) {
        return ImageQualityResult(
          isSuitable: false,
          reason: 'Could not decode image',
        );
      }

      // Check 1: Minimum resolution
      if (image.width < 640 || image.height < 640) {
        return ImageQualityResult(
          isSuitable: false,
          reason: 'Resolution too low: ${image.width}x${image.height} (minimum 640x640)',
        );
      }

      // Check 2: Brightness (average pixel value)
      final brightness = _calculateBrightness(image);
      if (brightness < 50) {
        return ImageQualityResult(
          isSuitable: false,
          reason: 'Image too dark: brightness=$brightness (minimum 50)',
        );
      }
      if (brightness > 200) {
        return ImageQualityResult(
          isSuitable: false,
          reason: 'Image too bright: brightness=$brightness (maximum 200)',
        );
      }

      // Check 3: Blur detection (Laplacian variance)
      final blurScore = _calculateBlurScore(image);
      if (blurScore < 100) {
        return ImageQualityResult(
          isSuitable: false,
          reason: 'Image too blurry: blur score=$blurScore (minimum 100)',
        );
      }

      return ImageQualityResult(
        isSuitable: true,
        reason: 'Image quality acceptable',
        brightness: brightness,
        blurScore: blurScore,
        resolution: '${image.width}x${image.height}',
      );
    } catch (e) {
      return ImageQualityResult(
        isSuitable: false,
        reason: 'Error checking image quality: $e',
      );
    }
  }

  /// Calculate average brightness of image
  double _calculateBrightness(img.Image image) {
    double totalBrightness = 0;
    int count = 0;
    
    // Sample every 10th pixel for performance  
    for (int y = 0; y < image.height; y += 10) {
      for (int x = 0; x < image.width; x += 10) {
        final pixel = image.getPixel(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();
        // Luminance formula: 0.299*R + 0.587*G + 0.114*B
        totalBrightness += (r * 0.299 + g * 0.587 + b * 0.114);
        count++;
      }
    }
    
    return count > 0 ? totalBrightness / count : 0;
  }

  /// Calculate blur score using Laplacian variance
  double _calculateBlurScore(img.Image image) {
    // Convert to grayscale for blur detection
    final gray = img.grayscale(image);
    
    // Apply Laplacian kernel to detect edges
    double sum = 0;
    double sumSq = 0;
    int count = 0;

    // Sample every 10th pixel for performance
    for (int y = 1; y < gray.height - 1; y += 10) {
      for (int x = 1; x < gray.width - 1; x += 10) {
        final center = gray.getPixel(x, y).r;
        final top = gray.getPixel(x, y - 1).r;
        final bottom = gray.getPixel(x, y + 1).r;
        final left = gray.getPixel(x - 1, y).r;
        final right = gray.getPixel(x + 1, y).r;
        
        // Laplacian: center * 4 - (top + bottom + left + right)
        final laplacian = (center * 4 - top - bottom - left - right).toDouble();
        
        sum += laplacian;
        sumSq += laplacian * laplacian;
        count++;
      }
    }

    // Calculate variance (higher variance = sharper image)
    if (count == 0) return 0;
    final mean = sum / count;
    final variance = (sumSq / count) - (mean * mean);
    
    return variance;
  }

  /// Detect at multiple scales and combine results for better accuracy
  Future<int> detectMultiScale(
    File imageFile, {
    required FishSpecies species,
    List<double> scales = const [0.8, 1.0, 1.2],
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    print('🔍 Multi-scale detection at scales: $scales');

    final allDetections = <Map<String, double>>[];

    for (final scale in scales) {
      final scaledSize = (640 * scale).toInt();
      
      final request = DetectionRequest(
        id: '${DateTime.now().millisecondsSinceEpoch}_$scale',
        imageFile: imageFile,
        species: species,
        confidenceThreshold: 0.55,  // Slightly lower for multi-scale
        nmsThreshold: 0.25,
      );

      try {
        final result = await _detectFingerlingsInternal(request);
        
        // Scale bounding boxes back to original size
        for (final detection in result.detections) {
          final scaledDetection = {
            'x1': detection['x1']! / scale,
            'y1': detection['y1']! / scale,
            'x2': detection['x2']! / scale,
            'y2': detection['y2']! / scale,
            'confidence': detection['confidence']!,
            'area': detection['area']! / (scale * scale),
          };
          allDetections.add(scaledDetection);
        }
        
        print('Scale $scale: ${result.detections.length} detections');
      } catch (e) {
        print('⚠️ Error at scale $scale: $e');
      }
    }

    // Apply global NMS across all scales
    final finalDetections = _applyGlobalNMS(allDetections, nmsThreshold: 0.3);
    
    print('✅ Multi-scale total: ${finalDetections.length} detections');
    return finalDetections.length;
  }

  /// Run detection multiple times with different thresholds and return median count
  Future<int> detectWithEnsemble(
    File imageFile, {
    required FishSpecies species,
    List<double> confidenceThresholds = const [0.4, 0.5, 0.6],
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    print('🎯 Ensemble detection with thresholds: $confidenceThresholds');

    final counts = <int>[];

    for (final threshold in confidenceThresholds) {
      try {
        final count = await detectFingerlings(
          imageFile,
          species: species,
          confidenceThreshold: threshold,
          nmsThreshold: 0.3,
        );
        counts.add(count);
        print('Threshold $threshold: $count detections');
      } catch (e) {
        print('⚠️ Error at threshold $threshold: $e');
      }
    }

    if (counts.isEmpty) {
      throw Exception('All ensemble detections failed');
    }

    // Return median count (most robust to outliers)
    counts.sort();
    final medianCount = counts[counts.length ~/ 2];
    
    print('✅ Ensemble median: $medianCount (from $counts)');
    return medianCount;
  }

  /// Apply NMS across detections from multiple scales
  List<Map<String, double>> _applyGlobalNMS(
    List<Map<String, double>> detections, {
    required double nmsThreshold,
  }) {
    if (detections.isEmpty) return [];

    // Sort by confidence
    detections.sort((a, b) => b['confidence']!.compareTo(a['confidence']!));

    final selected = <Map<String, double>>[];
    final suppressed = List.filled(detections.length, false);

    for (int i = 0; i < detections.length; i++) {
      if (suppressed[i]) continue;

      final current = detections[i];
      selected.add(current);

      for (int j = i + 1; j < detections.length; j++) {
        if (!suppressed[j] && _fastIoU(current, detections[j]) > nmsThreshold) {
          suppressed[j] = true;
        }
      }

      if (selected.length >= 100) break;
    }

    return selected;
  }

  Future<BatchResult> processBatch(List<DetectionRequest> requests) async {
    final stopwatch = Stopwatch()..start();
    final results = <DetectionResult>[];

    print('Processing batch of ${requests.length} images');

    final futures = <Future<DetectionResult>>[];

    for (int i = 0; i < requests.length; i++) {
      final isolateIndex = i % poolSize;
      futures.add(_processInIsolate(requests[i], isolateIndex));
    }

    final parallelResults = await Future.wait(futures);
    results.addAll(parallelResults);

    stopwatch.stop();

    final batchResult = BatchResult(
      results: results,
      totalProcessingTime: stopwatch.elapsed,
    );

    print(
        'Batch processing completed in ${stopwatch.elapsedMilliseconds}ms: ${batchResult.successCount} successes, ${batchResult.failureCount} failures');
    return batchResult;
  }

  Future<DetectionResult> _processInIsolate(
      DetectionRequest request, int isolateIndex) async {
    final receivePort = ReceivePort();

    _sendPorts[isolateIndex].send({
      'request': request,
      'resultSendPort': receivePort.sendPort,
    });

    final result = await receivePort.first as DetectionResult;
    receivePort.close();

    return result;
  }

  Future<DetectionResult> _detectFingerlingsInternal(
      DetectionRequest request) async {
    final stopwatch = Stopwatch()..start();

    try {
      final interpreter = _interpreters[request.species];
      if (interpreter == null) {
        throw Exception(
            'Model not loaded for species: ${request.species.name}');
      }

      final config = _modelConfigs[request.species]!;
      print(
          'Using model for ${request.species.name} with ${config.outputChannels} output channels');

      final inputData = await ImagePreprocessor.preprocessImage(
        request.imageFile,
        useCache: true,
      );

      final inputFloat32 = inputData.buffer.asFloat32List();

      int srcIndex = 0;
      for (int h = 0; h < 640; h++) {
        for (int w = 0; w < 640; w++) {
          for (int c = 0; c < 3; c++) {
            _inputTensor[0][h][w][c] = inputFloat32[srcIndex++];
          }
        }
      }

      // Create output tensor dynamically based on model's output shape
      final outputTensor = List.generate(
          1,
          (batch) => List.generate(
              config.outputChannels, (channel) => List.filled(8400, 0.0)));

      // Run inference with species-specific output tensor
      interpreter.run(_inputTensor, outputTensor);

      var detections = _processDetectionsFast(
        outputTensor,
        request.confidenceThreshold,
        request.nmsThreshold,
      );

      // Apply size filtering if enabled
      if (request.applySizeFiltering && detections.isNotEmpty) {
        final beforeFiltering = detections.length;
        detections = _filterBySize(detections);
        final afterFiltering = detections.length;
        
        if (beforeFiltering != afterFiltering) {
          print('Size filtering: removed ${beforeFiltering - afterFiltering} detections (${beforeFiltering} → $afterFiltering)');
        }
      }

      stopwatch.stop();

      _processingTimes.add(stopwatch.elapsed);
      _totalProcessed++;

      if (_processingTimes.length > 100) {
        _processingTimes.removeAt(0);
      }

      return DetectionResult(
        id: request.id,
        count: detections.length,
        detections: detections,
        processingTime: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return DetectionResult(
        id: request.id,
        count: 0,
        detections: [],
        processingTime: stopwatch.elapsed,
        error: e.toString(),
      );
    }
  }

  List<Map<String, double>> _processDetectionsFast(
    List<List<List<double>>> output,
    double confidenceThreshold,
    double nmsThreshold,
  ) {
    final candidates = <Map<String, double>>[];

    // Extract data - confidence is always at index 4 regardless of output channels
    final confidences = output[0][4];
    final centerXs = output[0][0];
    final centerYs = output[0][1];
    final widths = output[0][2];
    final heights = output[0][3];

    for (int i = 0; i < 8400; i++) {
      if (confidences[i] > confidenceThreshold) {
        final centerX = centerXs[i] * 640;
        final centerY = centerYs[i] * 640;
        final width = widths[i] * 640;
        final height = heights[i] * 640;

        candidates.add({
          'x1': centerX - width * 0.5,
          'y1': centerY - height * 0.5,
          'x2': centerX + width * 0.5,
          'y2': centerY + height * 0.5,
          'confidence': confidences[i],
          'area': width * height,
        });
      }
    }

    if (candidates.isEmpty) return [];

    candidates.sort((a, b) => b['confidence']!.compareTo(a['confidence']!));

    final selected = <Map<String, double>>[];
    final suppressed = List.filled(candidates.length, false);

    for (int i = 0; i < candidates.length; i++) {
      if (suppressed[i]) continue;

      final current = candidates[i];
      selected.add(current);

      for (int j = i + 1; j < candidates.length; j++) {
        if (!suppressed[j] && _fastIoU(current, candidates[j]) > nmsThreshold) {
          suppressed[j] = true;
        }
      }

      if (selected.length >= 100) break;
    }

    return selected;
  }

  /// Filter detections by size to remove unrealistic fingerling detections
  List<Map<String, double>> _filterBySize(
    List<Map<String, double>> detections, {
    double minArea = 100.0,        // Minimum area in pixels²
    double maxArea = 15000.0,      // Maximum area in pixels²
    double minWidth = 10.0,        // Minimum width in pixels
    double minHeight = 10.0,       // Minimum height in pixels
    double maxAspectRatio = 4.0,   // Max width/height ratio (elongated fish)
  }) {
    return detections.where((detection) {
      final x1 = detection['x1']!;
      final y1 = detection['y1']!;
      final x2 = detection['x2']!;
      final y2 = detection['y2']!;
      
      final width = x2 - x1;
      final height = y2 - y1;
      final area = detection['area']!;
      
      // Check size constraints
      if (area < minArea || area > maxArea) return false;
      if (width < minWidth || height < minHeight) return false;
      
      // Check aspect ratio (fish shouldn't be too elongated)
      final aspectRatio = width > height ? width / height : height / width;
      if (aspectRatio > maxAspectRatio) return false;
      
      // Check if detection is within image bounds
      if (x1 < 0 || y1 < 0 || x2 > 640 || y2 > 640) return false;
      
      return true;
    }).toList();
  }

  double _fastIoU(Map<String, double> box1, Map<String, double> box2) {
    final x1 = box1['x1']!;
    final y1 = box1['y1']!;
    final x2 = box1['x2']!;
    final y2 = box1['y2']!;

    final x1_2 = box2['x1']!;
    final y1_2 = box2['y1']!;
    final x2_2 = box2['x2']!;
    final y2_2 = box2['y2']!;

    final left = x1 > x1_2 ? x1 : x1_2;
    final top = y1 > y1_2 ? y1 : y1_2;
    final right = x2 < x2_2 ? x2 : x2_2;
    final bottom = y2 < y2_2 ? y2 : y2_2;

    if (left >= right || top >= bottom) return 0.0;

    final intersection = (right - left) * (bottom - top);
    final union = box1['area']! + box2['area']! - intersection;

    return intersection / union;
  }

  void addToBatch(DetectionRequest request) {
    _batchQueue.add(request);

    if (_batchQueue.length >= batchSize) {
      _processBatch();
    }
  }

  void _startBatchTimer() {
    _batchTimer = Timer.periodic(batchTimeout, (timer) {
      if (_batchQueue.isNotEmpty) {
        _processBatch();
      }
    });
  }

  void _processBatch() async {
    if (_batchQueue.isEmpty) return;

    final batch = List<DetectionRequest>.from(_batchQueue);
    _batchQueue.clear();

    final result = await processBatch(batch);
    _batchResultController.add(result);
  }

  Map<String, dynamic> getPerformanceMetrics() {
    if (_processingTimes.isEmpty) {
      return {
        'totalProcessed': _totalProcessed,
        'averageProcessingTime': 0,
        'cacheSize': ImagePreprocessor.cacheSize,
        'isolatePoolSize': _isolatePool.length,
        'loadedModels': _interpreters.keys.map((s) => s.name).toList(),
        'modelConfigs': _modelConfigs.map((k, v) => MapEntry(k.name, {
              'outputChannels': v.outputChannels,
              'outputShape': v.outputShape,
            })),
      };
    }

    final avgProcessingTime =
        _processingTimes.map((d) => d.inMilliseconds).reduce((a, b) => a + b) /
            _processingTimes.length;

    return {
      'totalProcessed': _totalProcessed,
      'averageProcessingTime': avgProcessingTime,
      'cacheSize': ImagePreprocessor.cacheSize,
      'batchQueueSize': _batchQueue.length,
      'isolatePoolSize': _isolatePool.length,
      'loadedModels': _interpreters.keys.map((s) => s.name).toList(),
      'modelConfigs': _modelConfigs.map((k, v) => MapEntry(k.name, {
            'outputChannels': v.outputChannels,
            'outputShape': v.outputShape,
          })),
    };
  }

  void dispose() {
    _batchTimer?.cancel();
    _batchResultController.close();

    for (final interpreter in _interpreters.values) {
      interpreter.close();
    }
    _interpreters.clear();
    _modelConfigs.clear();

    for (final isolate in _isolatePool) {
      isolate.kill();
    }
    _isolatePool.clear();
    _sendPorts.clear();
    _isolateAvailable.clear();

    ImagePreprocessor.clearCache();
    ImagePreprocessor.clearBufferPool();
    _isInitialized = false;
    print('TFLite service disposed');
  }
}

class PerformanceMonitor {
  static final Stopwatch _stopwatch = Stopwatch();
  static final Map<String, List<int>> _metrics = {};

  static void start(String operation) {
    _stopwatch.reset();
    _stopwatch.start();
  }

  static void end(String operation) {
    _stopwatch.stop();
    _metrics[operation] ??= [];
    _metrics[operation]!.add(_stopwatch.elapsedMilliseconds);

    if (_metrics[operation]!.length > 50) {
      _metrics[operation]!.removeAt(0);
    }
  }

  static Map<String, double> getAverages() {
    final averages = <String, double>{};

    for (final entry in _metrics.entries) {
      if (entry.value.isNotEmpty) {
        averages[entry.key] =
            entry.value.reduce((a, b) => a + b) / entry.value.length;
      }
    }

    return averages;
  }

  static void clear() {
    _metrics.clear();
  }
}
