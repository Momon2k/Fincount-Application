class ApiConfig {
  // Change this based on your environment
  // static const String baseUrl = 'http://192.168.1.9:3000/api'; // Network URL
  // static const String baseUrl = 'http://10.0.2.2:3000/api'; // Android emulator
  // static const String baseUrl = 'http://localhost:3000/api'; // iOS simulator
  static const String baseUrl =
      'https://fincount-api-production.up.railway.app/api'; // Production

  // API Endpoints
  static const String users = '$baseUrl/user';
  static const String batches = '$baseUrl/batches';
  static const String sessions = '$baseUrl/sessions';
  static const String auth = '$baseUrl/auth';
  static const String upload = '$baseUrl/upload';
  static const String sync = '$baseUrl/sync';
  static const String health = '$baseUrl/health';

  // Timeout configuration
  static const Duration timeout = Duration(seconds: 30);

  static const Duration connectionTimeout = Duration(seconds: 10);

  // Retry configuration
  static const int maxRetries = 3;
  static const Duration retryDelay = Duration(seconds: 2);
}
