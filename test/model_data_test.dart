import 'package:http/http.dart' as http;
import 'dart:convert';

/// Test batch and session creation with actual Flutter model data
void main() async {
  print('🧪 Testing Batch and Session Data Models\n');

  const String baseUrl = 'https://fincount-api-production.up.railway.app/api';

  // First, login to get token
  print('═══════════════════════════════════════');
  print('STEP 1: Login to get authentication token');
  print('═══════════════════════════════════════');
  final token = await loginAndGetToken(baseUrl);

  if (token == null) {
    print('❌ Failed to get token. Cannot proceed with tests.');
    return;
  }

  print('\n═══════════════════════════════════════');
  print('STEP 2: Test Batch Creation');
  print('═══════════════════════════════════════');
  await testBatchCreation(baseUrl, token);

  print('\n═══════════════════════════════════════');
  print('STEP 3: Test Session Creation');
  print('═══════════════════════════════════════');
  await testSessionCreation(baseUrl, token);

  print('\n\n✅ Model Data Test Complete!');
  print('═══════════════════════════════════════\n');
}

Future<String?> loginAndGetToken(String baseUrl) async {
  print('📡 Logging in as admin...');

  try {
    final uri = Uri.parse('$baseUrl/auth/login');
    final response = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({
            'email': 'admin@fincount.com',
            'password': 'admin123',
          }),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      print('✅ Login successful');
      print('🔑 Token received');
      return data['token'];
    } else {
      print('❌ Login failed: ${response.statusCode}');
      return null;
    }
  } catch (e) {
    print('❌ Error: $e');
    return null;
  }
}

Future<void> testBatchCreation(String baseUrl, String token) async {
  print('📡 Endpoint: POST $baseUrl/batches');
  print('📝 Testing with Flutter Batch model data format\n');

  // This is the exact format the Flutter app sends
  final batchData = {
    'id': 'batch-${DateTime.now().millisecondsSinceEpoch}',
    'name': 'Test Batch ${DateTime.now().hour}:${DateTime.now().minute}',
    'description': 'Test batch created from Flutter app',
    'userId': 'fa1c3896-50a9-41b8-a573-a4c9dc1266bf', // Admin user ID
    'totalCount': 0,
    'createdAt': DateTime.now().toIso8601String(),
    'updatedAt': DateTime.now().toIso8601String(),
    'isActive': true,
  };

  print('📄 Request Body:');
  print(jsonEncode(batchData));
  print('');

  try {
    final uri = Uri.parse('$baseUrl/batches');
    final response = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(batchData),
        )
        .timeout(const Duration(seconds: 10));

    print('📊 Status Code: ${response.statusCode}');
    print('📄 Response Body: ${response.body}');

    if (response.statusCode == 201 || response.statusCode == 200) {
      print('✅ PASS: Batch created successfully');
      print('💡 Flutter Batch model format is compatible!');
    } else if (response.statusCode == 422) {
      print('❌ FAIL: Validation error');
      print('⚠️  Data format mismatch - needs adjustment');
    } else {
      print('⚠️  WARNING: Unexpected status code');
    }
  } catch (e) {
    print('❌ ERROR: $e');
  }
}

Future<void> testSessionCreation(String baseUrl, String token) async {
  print('📡 Endpoint: POST $baseUrl/sessions');
  print('📝 Testing with Flutter Session model data format\n');

  // This is the exact format the Flutter app sends
  final sessionData = {
    'id': 'session-${DateTime.now().millisecondsSinceEpoch}',
    'batchId': 'BF-20251115-001', // Example batch ID
    'species': 'Tilapia',
    'location': 'Pond A',
    'notes': 'Test session from Flutter app',
    'counts': {
      'fingerlings': 150,
      'juveniles': 50,
      'adults': 20,
    },
    'timestamp': DateTime.now().toIso8601String(),
    'imageUrl': 'https://example.com/image.jpg',
  };

  print('📄 Request Body:');
  print(jsonEncode(sessionData));
  print('');

  try {
    final uri = Uri.parse('$baseUrl/sessions');
    final response = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode(sessionData),
        )
        .timeout(const Duration(seconds: 10));

    print('📊 Status Code: ${response.statusCode}');
    print('📄 Response Body: ${response.body}');

    if (response.statusCode == 201 || response.statusCode == 200) {
      print('✅ PASS: Session created successfully');
      print('💡 Flutter Session model format is compatible!');
    } else if (response.statusCode == 422) {
      print('❌ FAIL: Validation error');
      print('⚠️  Data format mismatch - needs adjustment');

      // Try to parse validation errors
      try {
        final errorData = jsonDecode(response.body);
        if (errorData['detail'] != null) {
          print('\n📋 Validation Errors:');
          if (errorData['detail'] is List) {
            for (var error in errorData['detail']) {
              print('   - ${error['loc']}: ${error['msg']}');
            }
          } else {
            print('   ${errorData['detail']}');
          }
        }
      } catch (e) {
        // Ignore parsing errors
      }
    } else {
      print('⚠️  WARNING: Unexpected status code');
    }
  } catch (e) {
    print('❌ ERROR: $e');
  }
}
