import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'Login_Page.dart';
import 'models/session_model.dart';
import 'services/object_detection_service.dart';
import 'Dashboard_Page.dart';
import 'Camera_Page.dart';
import 'Batches_Page.dart';
import 'History_Page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    // Initialize Hive
    await Hive.initFlutter();
    
    // Register Adapters
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(SessionModelAdapter());
    }
    
    // Open Boxes
    await Hive.openBox<SessionModel>('sessions');
    
    runApp(const MyApp());
  } catch (e) {
    print('Error initializing app: $e');
    runApp(const MyApp());
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fish Detection App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        textTheme: GoogleFonts.interTextTheme(
          Theme.of(context).textTheme,
        ),
        // Apply the font to specific components
        appBarTheme: AppBarTheme(
          titleTextStyle: GoogleFonts.inter(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        // Button text theme
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            textStyle: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      initialRoute: '/dashboard',
      routes: {
        '/dashboard': (context) => const DashboardPage(),
        '/camera': (context) => const CameraPage(
              batchId: '',
              species: '',
              location: '',
            ),
        '/batches': (context) => const BatchesPage(),
        '/history': (context) => const HistoryPage(),
      },
      onGenerateRoute: (settings) {
        // Handle dynamic routes with parameters
        if (settings.name?.startsWith('/camera/') == true) {
          final args = settings.arguments as Map<String, String>;
          return MaterialPageRoute(
            builder: (context) => CameraPage(
              batchId: args['batchId'] ?? '',
              species: args['species'] ?? '',
              location: args['location'] ?? '',
              notes: args['notes'] ?? '',
            ),
          );
        }
        return null;
      },
    );
  }
}
