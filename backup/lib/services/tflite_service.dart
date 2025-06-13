import 'dart:io';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

class TFLiteService {
  static TFLiteService? _instance;
  late final Interpreter _interpreter;
  
  // Singleton pattern
  static TFLiteService get instance {
    _instance ??= TFLiteService._();
    return _instance!;
  }

  TFLiteService._();

  Future<void> initialize() async {
    try {
      final modelPath = 'assets/best_float32.tflite';
      _interpreter = await Interpreter.fromAsset(modelPath);
      print('TFLite model loaded successfully');
    } catch (e) {
      print('Error loading model: $e');
      rethrow;
    }
  }

  Future<List<dynamic>> detectObjects(File imageFile) async {
    try {
      // Load and preprocess the image
      final bytes = await imageFile.readAsBytes();
      final image = img.decodeImage(bytes)!;
      
      // Resize image to match model input size
      final resizedImage = img.copyResize(image, width: 640, height: 640);
      
      // Convert image to float32 array and normalize
      var imageMatrix = List.generate(
        640,
        (y) => List.generate(
          640,
          (x) {
            final pixel = resizedImage.getPixel(x, y);
            // Get RGB values using image package methods
            return [
              resizedImage.getPixelSafe(x, y).r.toDouble() / 255.0,
              resizedImage.getPixelSafe(x, y).g.toDouble() / 255.0,
              resizedImage.getPixelSafe(x, y).b.toDouble() / 255.0,
            ];
          },
        ),
      );

      // Prepare input tensor
      var input = [imageMatrix];
      
      // Prepare output tensor
      var outputShape = [1, 8400, 7]; // Adjust based on your model's output shape
      var outputs = List.filled(1 * 8400 * 7, 0.0).reshape(outputShape);
      
      // Run inference
      _interpreter.run(input, outputs);
      
      return outputs;
    } catch (e) {
      print('Error during object detection: $e');
      rethrow;
    }
  }

  void dispose() {
    _interpreter.close();
  }
} 