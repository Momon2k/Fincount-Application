//tflite_service.dart

import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:async';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// Data classes for batch processing
class DetectionRequest {
  final String id;
  final File imageFile;
  final double confidenceThreshold;
  final double nmsThreshold;
  final DateTime timestamp;

  DetectionRequest({
    required this.id,
    required this.imageFile,
    this.confidenceThreshold = 0.5,
    this.nmsThreshold = 0.4,
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
  }) : successCount = results.where((r) => r.isSuccess).length,
       failureCount = results.where((r) => !r.isSuccess).length;
}

// Highly optimized image preprocessing with memory pooling
class ImagePreprocessor {
  static final Map<String, Uint8List> _cache = {};
  static final Map<int, ByteData> _bufferPool = {};
  static const int maxCacheSize = 50;
  static const int targetSize = 640;
  static const int inputSize = 640 * 640 * 3;

  // Pre-allocate buffers for different sizes
  static ByteData _getBuffer(int size) {
    if (!_bufferPool.containsKey(size)) {
      _bufferPool[size] = ByteData(size * 4); // Float32 = 4 bytes
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
      // Read image bytes with memory mapping for large files
      final bytes = await _readImageBytes(imageFile);
      
      // Fast decode with reduced memory allocations
      final image = img.decodeImage(bytes);
      if (image == null) {
        throw Exception('Could not decode image: ${imageFile.path}');
      }

      // Ultra-fast resize using nearest neighbor for speed
      final resized = _ultraFastResize(image, size);
      
      // Convert to float32 with pre-allocated buffer
      final inputData = _imageToFloat32ArrayFast(resized, size);
      
      // Cache management
      if (useCache) {
        _manageCache(cacheKey, inputData);
      }

      print('Image preprocessing completed in ${stopwatch.elapsedMilliseconds}ms');
      return inputData;
      
    } catch (e) {
      print('Error preprocessing image ${imageFile.path}: $e');
      rethrow;
    }
  }

  // Memory-mapped file reading for large images
  static Future<Uint8List> _readImageBytes(File imageFile) async {
    final fileSize = await imageFile.length();
    
    if (fileSize > 10 * 1024 * 1024) { // 10MB threshold
      // Use memory mapping for large files
      final randomAccessFile = await imageFile.open();
      final bytes = await randomAccessFile.read(fileSize);
      await randomAccessFile.close();
      return bytes;
    } else {
      // Direct read for smaller files
      return await imageFile.readAsBytes();
    }
  }

  // Ultra-fast resize using nearest neighbor sampling
  static img.Image _ultraFastResize(img.Image image, int targetSize) {
    if (image.width == targetSize && image.height == targetSize) {
      return image;
    }

    final resized = img.Image(width: targetSize, height: targetSize);
    final xRatio = image.width / targetSize;
    final yRatio = image.height / targetSize;

    // Nearest neighbor interpolation - fastest method
    for (int y = 0; y < targetSize; y++) {
      for (int x = 0; x < targetSize; x++) {
        final srcX = (x * xRatio).floor();
        final srcY = (y * yRatio).floor();
        resized.setPixel(x, y, image.getPixel(srcX, srcY));
      }
    }

    return resized;
  }

  // Optimized float32 conversion with pre-allocated buffer
  static Uint8List _imageToFloat32ArrayFast(img.Image image, int size) {
    final buffer = _getBuffer(size * size * 3);
    final pixels = image.getBytes(order: img.ChannelOrder.rgb);
    
    // Direct conversion without intermediate arrays
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

// Optimized TFLite service with model caching and thread pool
class TFLiteService {
  static final TFLiteService _instance = TFLiteService._internal();
  factory TFLiteService() => _instance;
  TFLiteService._internal();

  Interpreter? _interpreter;
  bool _isInitialized = false;
  
  // Pre-allocated tensors for better performance
  late final List<List<List<List<double>>>> _inputTensor;
  late final List<List<List<double>>> _outputTensor;
  
  // Performance monitoring
  final List<Duration> _processingTimes = [];
  int _totalProcessed = 0;
  
  // Thread pool for parallel processing
  final List<Isolate> _isolatePool = [];
  final List<SendPort> _sendPorts = [];
  final List<bool> _isolateAvailable = [];
  static const int poolSize = 3;
  
  // Batch processing queue
  final List<DetectionRequest> _batchQueue = [];
  final StreamController<BatchResult> _batchResultController = StreamController<BatchResult>.broadcast();
  Timer? _batchTimer;
  
  // Configuration
  static const int batchSize = 8; // Increased batch size
  static const Duration batchTimeout = Duration(milliseconds: 500); // Reduced timeout
  
  Stream<BatchResult> get batchResults => _batchResultController.stream;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Initialize interpreter with basic optimizations
      _interpreter = await Interpreter.fromAsset(
        'assets/models/model.tflite',
        options: InterpreterOptions()
          ..threads = 4, // Use multiple threads
      );
      
      // Pre-allocate tensors to avoid repeated allocations
      _inputTensor = List.generate(1, (b) =>
        List.generate(640, (h) =>
          List.generate(640, (w) =>
            List.generate(3, (c) => 0.0)
          )
        )
      );
      
      _outputTensor = List.generate(1, (batch) => 
        List.generate(5, (channel) => 
          List.filled(8400, 0.0)
        )
      );
      
      _interpreter!.allocateTensors();
      
      // Initialize isolate pool for parallel processing
      await _initializeIsolatePool();
      
      _isInitialized = true;
      print('TFLite service initialized successfully with ${_isolatePool.length} isolates');
      
      // Start batch processing timer
      _startBatchTimer();
      
    } catch (e) {
      print('Error initializing TFLite: $e');
      rethrow;
    }
  }

  // Initialize isolate pool for parallel processing
  Future<void> _initializeIsolatePool() async {
    for (int i = 0; i < poolSize; i++) {
      final receivePort = ReceivePort();
      final isolate = await Isolate.spawn(_isolateEntry, receivePort.sendPort);
      
      _isolatePool.add(isolate);
      _isolateAvailable.add(true);
      
      // Get SendPort from isolate
      final sendPort = await receivePort.first as SendPort;
      _sendPorts.add(sendPort);
      receivePort.close();
    }
  }

  // Isolate entry point
  static void _isolateEntry(SendPort mainSendPort) {
    final receivePort = ReceivePort();
    mainSendPort.send(receivePort.sendPort);
    
    // Initialize TFLite in isolate
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

  // Single image detection (highly optimized)
  Future<int> detectFingerlings(File imageFile, {
    double confidenceThreshold = 0.5,
    double nmsThreshold = 0.4,
  }) async {
    if (!_isInitialized) {
      await initialize();
    }

    final request = DetectionRequest(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      imageFile: imageFile,
      confidenceThreshold: confidenceThreshold,
      nmsThreshold: nmsThreshold,
    );

    final result = await _detectFingerlingsInternal(request);
    
    if (result.error != null) {
      throw Exception(result.error);
    }
    
    return result.count;
  }

  // Optimized batch processing with parallel execution
  Future<BatchResult> processBatch(List<DetectionRequest> requests) async {
    final stopwatch = Stopwatch()..start();
    final results = <DetectionResult>[];
    
    print('Processing batch of ${requests.length} images');
    
    // Process in parallel using isolate pool
    final futures = <Future<DetectionResult>>[];
    
    for (int i = 0; i < requests.length; i++) {
      final isolateIndex = i % poolSize;
      futures.add(_processInIsolate(requests[i], isolateIndex));
    }
    
    // Wait for all results
    final parallelResults = await Future.wait(futures);
    results.addAll(parallelResults);
    
    stopwatch.stop();
    
    final batchResult = BatchResult(
      results: results,
      totalProcessingTime: stopwatch.elapsed,
    );
    
    print('Batch processing completed in ${stopwatch.elapsedMilliseconds}ms: ${batchResult.successCount} successes, ${batchResult.failureCount} failures');
    return batchResult;
  }

  // Process request in specific isolate
  Future<DetectionResult> _processInIsolate(DetectionRequest request, int isolateIndex) async {
    final receivePort = ReceivePort();
    
    _sendPorts[isolateIndex].send({
      'request': request,
      'resultSendPort': receivePort.sendPort,
    });
    
    final result = await receivePort.first as DetectionResult;
    receivePort.close();
    
    return result;
  }

  // Ultra-optimized internal detection
  Future<DetectionResult> _detectFingerlingsInternal(DetectionRequest request) async {
    final stopwatch = Stopwatch()..start();
    
    try {
      // Fast preprocessing with caching
      final inputData = await ImagePreprocessor.preprocessImage(
        request.imageFile,
        useCache: true,
      );

      // Direct tensor manipulation for speed
      final inputFloat32 = inputData.buffer.asFloat32List();
      
      // Copy to pre-allocated tensor (faster than reshape)
      int srcIndex = 0;
      for (int h = 0; h < 640; h++) {
        for (int w = 0; w < 640; w++) {
          for (int c = 0; c < 3; c++) {
            _inputTensor[0][h][w][c] = inputFloat32[srcIndex++];
          }
        }
      }

      // Run inference with pre-allocated output
      _interpreter!.run(_inputTensor, _outputTensor);

      // Ultra-fast detection processing
      final detections = _processDetectionsFast(
        _outputTensor,
        request.confidenceThreshold,
        request.nmsThreshold,
      );

      stopwatch.stop();
      
      // Update performance metrics
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

  // Ultra-fast detection processing with optimized algorithms
  List<Map<String, double>> _processDetectionsFast(
    List<List<List<double>>> output,
    double confidenceThreshold,
    double nmsThreshold,
  ) {
    final candidates = <Map<String, double>>[];
    
    // Step 1: Vectorized confidence filtering
    final confidences = output[0][4];
    final centerXs = output[0][0];
    final centerYs = output[0][1];
    final widths = output[0][2];
    final heights = output[0][3];
    
    // Pre-filter by confidence in batch
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
    
    // Step 2: Optimized NMS with early termination
    if (candidates.isEmpty) return [];
    
    // Sort by confidence (descending)
    candidates.sort((a, b) => b['confidence']!.compareTo(a['confidence']!));
    
    final selected = <Map<String, double>>[];
    final suppressed = List.filled(candidates.length, false);
    
    for (int i = 0; i < candidates.length; i++) {
      if (suppressed[i]) continue;
      
      final current = candidates[i];
      selected.add(current);
      
      // Mark overlapping boxes as suppressed
      for (int j = i + 1; j < candidates.length; j++) {
        if (!suppressed[j] && _fastIoU(current, candidates[j]) > nmsThreshold) {
          suppressed[j] = true;
        }
      }
      
      // Early termination if we have enough detections
      if (selected.length >= 100) break;
    }
    
    return selected;
  }

  // Optimized IoU calculation with early returns
  double _fastIoU(Map<String, double> box1, Map<String, double> box2) {
    final x1 = box1['x1']!;
    final y1 = box1['y1']!;
    final x2 = box1['x2']!;
    final y2 = box1['y2']!;
    
    final x1_2 = box2['x1']!;
    final y1_2 = box2['y1']!;
    final x2_2 = box2['x2']!;
    final y2_2 = box2['y2']!;
    
    // Calculate intersection bounds
    final left = x1 > x1_2 ? x1 : x1_2;
    final top = y1 > y1_2 ? y1 : y1_2;
    final right = x2 < x2_2 ? x2 : x2_2;
    final bottom = y2 < y2_2 ? y2 : y2_2;
    
    // Early return if no intersection
    if (left >= right || top >= bottom) return 0.0;
    
    final intersection = (right - left) * (bottom - top);
    final union = box1['area']! + box2['area']! - intersection;
    
    return intersection / union;
  }

  // Batch processing management
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

  // Performance monitoring
  Map<String, dynamic> getPerformanceMetrics() {
    if (_processingTimes.isEmpty) {
      return {
        'totalProcessed': _totalProcessed,
        'averageProcessingTime': 0,
        'cacheSize': ImagePreprocessor.cacheSize,
        'isolatePoolSize': _isolatePool.length,
      };
    }
    
    final avgProcessingTime = _processingTimes
        .map((d) => d.inMilliseconds)
        .reduce((a, b) => a + b) / _processingTimes.length;
    
    return {
      'totalProcessed': _totalProcessed,
      'averageProcessingTime': avgProcessingTime,
      'cacheSize': ImagePreprocessor.cacheSize,
      'batchQueueSize': _batchQueue.length,
      'isolatePoolSize': _isolatePool.length,
    };
  }

  // Cleanup and disposal
  void dispose() {
    _batchTimer?.cancel();
    _batchResultController.close();
    _interpreter?.close();
    
    // Clean up isolate pool
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

// Performance monitoring utilities
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
    
    // Keep only last 50 measurements
    if (_metrics[operation]!.length > 50) {
      _metrics[operation]!.removeAt(0);
    }
  }
  
  static Map<String, double> getAverages() {
    final averages = <String, double>{};
    
    for (final entry in _metrics.entries) {
      if (entry.value.isNotEmpty) {
        averages[entry.key] = entry.value.reduce((a, b) => a + b) / entry.value.length;
      }
    }
    
    return averages;
  }
  
  static void clear() {
    _metrics.clear();
  }
}