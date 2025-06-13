import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'dart:io';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'Dashboard_Page.dart';
import 'models/session_model.dart';
import 'services/tflite_service.dart';

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

class _CameraPageState extends State<CameraPage> {
  CameraController? _controller;
  List<CameraDescription>? cameras;
  int detectionCount = 0;
  String timestamp = '';
  List<Rect> detectionBoxes = [];
  Timer? _timer;
  Timer? _detectionTimer;
  bool isCountingActive = false;
  bool isProcessingFrame = false;

  @override
  void initState() {
    super.initState();
    initializeCamera();
    _updateTimestamp();
    // Start timer to update timestamp every second
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _updateTimestamp();
    });
  }

  void _updateTimestamp() {
    setState(() {
      timestamp = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
    });
  }

  void _startCounting() {
    if (!isCountingActive) {
      setState(() {
        isCountingActive = true;
      });
      
      // Start real-time detection every 500ms
      _detectionTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
        if (mounted && isCountingActive && !isProcessingFrame) {
          _processFrame();
        }
      });
    }
  }

  void _stopCounting() {
    setState(() {
      isCountingActive = false;
    });
    _detectionTimer?.cancel();
  }

  Future<void> _processFrame() async {
    if (_controller == null || !_controller!.value.isInitialized || isProcessingFrame) {
      return;
    }

    isProcessingFrame = true;

    try {
      // Capture frame
      final image = await _controller!.takePicture();
      
      // Process frame with TFLite model
      final results = await TFLiteService.instance.detectObjects(File(image.path));
      
      // Process detection results
      List<Rect> newBoxes = [];
      int newDetections = 0;

      // Process the raw model output into detection boxes
      var outputArray = results as List<List<List<double>>>;
      for (var detection in outputArray[0]) {
        double confidence = detection[4];
        if (confidence > 0.5) { // Confidence threshold
          // YOLO output format: [x_center, y_center, width, height, confidence, class_scores...]
          double x_center = detection[0];
          double y_center = detection[1];
          double width = detection[2];
          double height = detection[3];
          
          // Convert normalized coordinates to actual pixel coordinates
          double left = (x_center - width/2) * 350;
          double top = (y_center - height/2) * 450;
          double boxWidth = width * 350;
          double boxHeight = height * 450;
          
          newBoxes.add(Rect.fromLTWH(left, top, boxWidth, boxHeight));
          newDetections++;
        }
      }

      // Update UI
      if (mounted) {
        setState(() {
          detectionBoxes = newBoxes;
          detectionCount += newDetections;
        });
      }

      // Clean up the temporary file
      try {
        File(image.path).deleteSync();
      } catch (e) {
        print('Error deleting temporary file: $e');
      }
    } catch (e) {
      print('Error processing frame: $e');
    } finally {
      isProcessingFrame = false;
    }
  }

  Future<void> initializeCamera() async {
    cameras = await availableCameras();
    if (cameras != null && cameras!.isNotEmpty) {
      _controller = CameraController(
        cameras![0],
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _controller!.initialize();
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _resetCount() {
    setState(() {
      detectionCount = 0;
      detectionBoxes.clear();
    });
  }

  void _handleSaveSession() {
    if (isCountingActive) {
      _stopCounting();
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2196F3).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.save_outlined,
                    color: Color(0xFF2196F3),
                    size: 32,
                  ),
                ),
                const SizedBox(height: 16),
                
                Text(
                  'Save Session',
                  style: GoogleFonts.inter(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                
                Text(
                  'Review your session details',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 24),
                
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      _buildDetailRow(
                        icon: Icons.numbers,
                        label: 'Batch ID',
                        value: widget.batchId,
                      ),
                      const SizedBox(height: 12),
                      _buildDetailRow(
                        icon: Icons.category,
                        label: 'Species',
                        value: widget.species,
                      ),
                      const SizedBox(height: 12),
                      _buildDetailRow(
                        icon: Icons.analytics,
                        label: 'Count',
                        value: detectionCount.toString(),
                      ),
                      const SizedBox(height: 12),
                      _buildDetailRow(
                        icon: Icons.access_time,
                        label: 'Time',
                        value: timestamp,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Cancel',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          // Create and save session
                          final session = SessionModel(
                            batchId: widget.batchId,
                            species: widget.species,
                            location: widget.location,
                            notes: widget.notes,
                            date: DateTime.now(),
                            count: detectionCount,
                          );
                          
                          // Get the sessions box and add the new session
                          final sessionsBox = Hive.box<SessionModel>('sessions');
                          sessionsBox.add(session);

                          // Show success message
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Row(
                                children: [
                                  const Icon(Icons.check_circle, color: Colors.white),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Session saved successfully',
                                    style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                              backgroundColor: Colors.green,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          );

                          // Navigate to Dashboard
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const DashboardPage(initialIndex: 0),
                            ),
                            (route) => false,
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2196F3),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Save',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    _timer?.cancel();
    _detectionTimer?.cancel();
    super.dispose();
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF2196F3).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 20,
            color: const Color(0xFF2196F3),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Info container at the top
            Container(
              margin: const EdgeInsets.all(10),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Batch ID: ${widget.batchId}',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                        ),
                      ),
                      Text(
                        'Species: ${widget.species}',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                        ),
                      ),
                      Text(
                        'Time: $timestamp',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.blue),
                    ),
                    child: Text(
                      '$detectionCount',
                      style: GoogleFonts.inter(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Camera preview with detection boxes
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Center(
                    child: Container(
                      width: 350,
                      height: 450,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: CameraPreview(_controller!),
                      ),
                    ),
                  ),
                  CustomPaint(
                    painter: DetectionBoxPainter(detectionBoxes),
                    child: Container(),
                  ),
                ],
              ),
            ),
            // Bottom buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton.icon(
                      onPressed: isCountingActive ? _stopCounting : _startCounting,
                      icon: Icon(
                        isCountingActive ? Icons.stop : Icons.play_arrow,
                        size: 24,
                      ),
                      label: Text(
                        isCountingActive ? 'Stop Counting' : 'Start Counting',
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isCountingActive 
                            ? Colors.red 
                            : const Color(0xFF4CAF50),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: _resetCount,
                            icon: const Icon(
                              Icons.refresh,
                              size: 20,
                            ),
                            label: Text(
                              'Reset',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2196F3),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 2,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: _handleSaveSession,
                            icon: const Icon(
                              Icons.save,
                              size: 20,
                            ),
                            label: Text(
                              'Save session',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2196F3),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DetectionBoxPainter extends CustomPainter {
  final List<Rect> boxes;

  DetectionBoxPainter(this.boxes);

  @override
  void paint(Canvas canvas, Size size) {
    final boxPaint = Paint()
      ..color = Colors.green.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final labelPaint = Paint()
      ..color = Colors.green.withOpacity(0.7)
      ..style = PaintingStyle.fill;

    final textStyle = ui.TextStyle(
      color: Colors.white,
      fontSize: 12,
      fontWeight: FontWeight.bold,
    );

    for (var box in boxes) {
      // Draw detection box
      canvas.drawRect(box, boxPaint);

      // Draw label background
      final labelRect = Rect.fromLTWH(
        box.left,
        box.top - 20,
        60,
        20,
      );
      canvas.drawRect(labelRect, labelPaint);

      // Draw label text
      final paragraphStyle = ui.ParagraphStyle(
        textDirection: ui.TextDirection.ltr,
        textAlign: TextAlign.left,
      );
      final paragraphBuilder = ui.ParagraphBuilder(paragraphStyle)
        ..pushStyle(textStyle)
        ..addText('Fish');
      final paragraph = paragraphBuilder.build()
        ..layout(ui.ParagraphConstraints(width: 50));
      
      canvas.drawParagraph(
        paragraph,
        Offset(box.left + 5, box.top - 18),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
} 