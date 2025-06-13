import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class TFLiteHelper {
  static Future<void> initTFLite() async {
    if (Platform.isWindows) {
      // Get the application documents directory
      final appDocDir = await getApplicationDocumentsDirectory();
      final libraryPath = '${appDocDir.path}/tflite_flutter_plugin';
      
      // Ensure the directory exists
      await Directory(libraryPath).create(recursive: true);
      
      // List of required DLLs for Windows
      final dlls = [
        'tensorflowlite_c.dll',
      ];
      
      // Copy each DLL from assets to the library path
      for (final dll in dlls) {
        final file = File('$libraryPath/$dll');
        if (!await file.exists()) {
          final byteData = await rootBundle.load('assets/dlls/$dll');
          await file.writeAsBytes(byteData.buffer.asUint8List());
        }
      }
    }
  }

  static Future<Interpreter?> loadModel(String modelPath) async {
    try {
      return await Interpreter.fromAsset(modelPath);
    } catch (e) {
      print('Error loading model: $e');
      return null;
    }
  }
} 