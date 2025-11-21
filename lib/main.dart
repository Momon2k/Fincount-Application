import 'package:fish_detection_app/Login_Page.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'models/session_model.dart';
import 'Dashboard_Page.dart';
import 'Camera_Page.dart';
import 'Batches_Page.dart';
import 'History_Page.dart';
import 'services/user_session_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Load environment variables
    await dotenv.load(fileName: ".env");

    // Initialize Hive
    await Hive.initFlutter();

    // Register Adapters
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(SessionModelAdapter());
    }

    // Try to restore user session from storage
    final sessionRestored = await UserSessionManager.initializeFromStoredSession();
    
    if (sessionRestored) {
      print('✅ User session restored on app start');
    } else {
      print('ℹ️ No previous session found, user needs to login');
    }

    runApp(MyApp(hasStoredSession: sessionRestored));
  } catch (e) {
    print('Error initializing app: $e');
    runApp(const MyApp(hasStoredSession: false));
  }
}

class MyApp extends StatelessWidget {
  final bool hasStoredSession;
  
  const MyApp({super.key, this.hasStoredSession = false});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fish Detection App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        textTheme: GoogleFonts.interTextTheme(Theme.of(context).textTheme),
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
      initialRoute: hasStoredSession ? '/dashboard' : '/login',
      routes: {
        '/login': (context) => const LoginPage(),
        '/dashboard': (context) => const DashboardPage(),
        '/camera': (context) =>
            const CameraPage(batchId: '', species: '', location: ''),
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
