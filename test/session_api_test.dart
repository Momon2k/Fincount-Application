import 'package:http/http.dart' as http;
import 'dart:convert';

/// Test session API with corrected data format
void main() async {
  print('🧪 Testing Session API with Corrected Format\n');

  const String baseUrl = 'https://fincount-api-production.up.railway.app/api';

  // Login first
  print('═══════════════════════════════════════');
  print('STEP 1: Login');
  print('═══════════════════════════════════════');
  final token = await loginAndGetToken(baseUrl);

  if (token == null) {
    print('❌ Failed to get token');
    return;
  }

  print('\n═══════════════════════════════════════');
  print('STEP 2: Test Session with Single Count');
  print('═══════════════════════════════════════');
  await testSessionWithSingleCount(baseUrl, token);

  print('\n═══════════════════════════════════════');
  print('STEP 3: Test Session with snake_case');
  print('═══════════════════════════════════════');
  await testSessionWithSnakeCase(baseUrl, token);

  print('\n═══════════════════════════════════════');
  print('STEP 4: Test Minimal Session Data');
  print('═══════════════════════════════════════');
  await testMinimalSession(baseUrl, token);

  print('\n\n✅ Session API Test Complete!');
  print('═══════════════════════════════════════\n');
}

Future<String?> loginAndGetToken(String baseUrl) async {
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
      return data['token'];
    }
    return null;
  } catch (e) {
    print('❌ Error: $e');
    return null;
  }
}

Future<void> testSessionWithSingleCount(String baseUrl, String token) async {
  print('📡 Testing with single count (camelCase)\n');

  final sessionData = {
    'batchId': 'BF-20251116-001',
    'species': 'Tilapia',
    'location': 'Pond A',
    'notes': 'Test session with single count',
    'count': 150, // Single number instead of counts object
    'timestamp': DateTime.now().toIso8601String(),
    'imageUrl': 'https://example.com/image.jpg',
  };

  print('📄 Request Body:');
  print(jsonEncode(sessionData));
  print('');

  await sendSessionRequest(baseUrl, token, sessionData);
}

Future<void> testSessionWithSnakeCase(String baseUrl, String token) async {
  print('📡 Testing with snake_case field names\n');

  final sessionData = {
    'batch_id': 'BF-20251116-002',
    'species': 'Tilapia',
    'location': 'Pond B',
    'notes': 'Test session with snake_case',
    'count': 200,
    'timestamp': DateTime.now().toIso8601String(),
    'image_url': 'https://example.com/image2.jpg',
  };

  print('📄 Request Body:');
  print(jsonEncode(sessionData));
  print('');

  await sendSessionRequest(baseUrl, token, sessionData);
}

Future<void> testMinimalSession(String baseUrl, String token) async {
  print('📡 Testing with minimal required fields only\n');

  final sessionData = {
    'batch_id': 'BF-20251116-003',
    'count': 100,
  };

  print('📄 Request Body:');
  print(jsonEncode(sessionData));
  print('');

  await sendSessionRequest(baseUrl, token, sessionData);
}

Future<void> sendSessionRequest(
  String baseUrl,
  String token,
  Map<String, dynamic> sessionData,
) async {
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
    print('');

    if (response.statusCode == 201 || response.statusCode == 200) {
      print('✅ SUCCESS: Session created!');
      print('💡 This format works with FastAPI!');
    } else if (response.statusCode == 422) {
      print('❌ VALIDATION ERROR');
      print('⚠️  Field format still incorrect');

      // Parse validation errors
      try {
        final errorData = jsonDecode(response.body);
        if (errorData['detail'] != null) {
          print('\n📋 Validation Errors:');
          if (errorData['detail'] is List) {
            for (var error in errorData['detail']) {
              print('   - Field: ${error['loc']}');
              print('     Error: ${error['msg']}');
              print('     Type: ${error['type']}');
            }
          } else {
            print('   ${errorData['detail']}');
          }
        }
      } catch (e) {
        // Ignore
      }
    } else if (response.statusCode == 500) {
      print('❌ SERVER ERROR');
      print('⚠️  FastAPI internal error - check server logs');
    } else {
      print('⚠️  Unexpected status: ${response.statusCode}');
    }
  } catch (e) {
    print('❌ ERROR: $e');
  }
}
