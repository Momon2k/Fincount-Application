import 'package:http/http.dart' as http;
import 'dart:convert';

/// Final test with EXACT format FastAPI expects
void main() async {
  print('🧪 Testing Session API with CORRECT Format\n');

  const String baseUrl = 'https://fincount-api-production.up.railway.app/api';

  // Login
  print('═══════════════════════════════════════');
  print('STEP 1: Login');
  print('═══════════════════════════════════════');
  final token = await loginAndGetToken(baseUrl);

  if (token == null) {
    print('❌ Failed to get token');
    return;
  }

  print('\n═══════════════════════════════════════');
  print('STEP 2: Create Session with Correct Format');
  print('═══════════════════════════════════════');
  await testCorrectFormat(baseUrl, token);

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

Future<void> testCorrectFormat(String baseUrl, String token) async {
  print('📡 Testing with EXACT FastAPI format\n');

  // This is the EXACT format FastAPI expects based on validation errors
  final sessionData = {
    'batchId': 'BF-20251116-001', // camelCase (required)
    'species': 'Tilapia', // required
    'location': 'Pond A', // required
    'notes': 'Test session from Flutter app', // required
    'counts': {
      // plural, object (required)
      'fingerlings': 150,
      'juveniles': 50,
      'adults': 20,
    },
    'timestamp': DateTime.now().toIso8601String(), // required
    'imageUrl': 'https://example.com/image.jpg', // camelCase (required)
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
    print('');

    if (response.statusCode == 201 || response.statusCode == 200) {
      print('✅ SUCCESS: Session created!');
      print('🎉 Flutter model format is CORRECT!');
      print('💡 The app will work perfectly with this format!');

      // Parse and display created session
      try {
        final responseData = jsonDecode(response.body);
        if (responseData['data'] != null) {
          print('\n📋 Created Session:');
          print('   ID: ${responseData['data']['id']}');
          print('   Batch: ${responseData['data']['batchId']}');
          print('   Species: ${responseData['data']['species']}');
          print('   Location: ${responseData['data']['location']}');
          print('   Counts: ${responseData['data']['counts']}');
        }
      } catch (e) {
        // Ignore parsing errors
      }
    } else if (response.statusCode == 422) {
      print('❌ VALIDATION ERROR');
      print('⚠️  Still incorrect - check validation details below');

      try {
        final errorData = jsonDecode(response.body);
        if (errorData['detail'] != null && errorData['detail'] is List) {
          print('\n📋 Validation Errors:');
          for (var error in errorData['detail']) {
            print('   - Field: ${error['loc']}');
            print('     Error: ${error['msg']}');
          }
        }
      } catch (e) {
        // Ignore
      }
    } else if (response.statusCode == 500) {
      print('❌ SERVER ERROR');
      print('⚠️  FastAPI internal error');
    } else {
      print('⚠️  Unexpected status: ${response.statusCode}');
    }
  } catch (e) {
    print('❌ ERROR: $e');
  }
}
