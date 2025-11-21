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
import 'services/connectivity_service.dart';

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

// Global navigator key for showing snackbars from anywhere
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class MyApp extends StatefulWidget {
  final bool hasStoredSession;
  
  const MyApp({super.key, this.hasStoredSession = false});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final ConnectivityService _connectivityService = ConnectivityService();

  @override
  void initState() {
    super.initState();
    
    // Initialize connectivity service if user has stored session
    if (widget.hasStoredSession) {
      _initializeConnectivityService();
    }
  }

  void _initializeConnectivityService() async {
    await _connectivityService.initialize();
    
    // Set up callback for sync completion notifications
    _connectivityService.onSyncComplete = (success, message) {
      _showSyncNotification(success, message);
    };
    
    print('✅ Auto-sync service activated');
  }

  void _showSyncNotification(bool success, String? message) {
    final context = navigatorKey.currentContext;
    if (context != null && message != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                success ? Icons.cloud_done : Icons.cloud_off,
                color: Colors.white,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: GoogleFonts.inter(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          backgroundColor: success ? Colors.green : Colors.orange,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _connectivityService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
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
      initialRoute: widget.hasStoredSession ? '/dashboard' : '/login',
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
