import 'package:http/http.dart' as http;
import 'dart:convert';

/// Comprehensive API test using actual Flutter app data formats
void main() async {
  print('🧪 Full API Connection Test\n');
  print('Testing with actual Flutter app data formats\n');

  const String baseUrl = 'https://fincount-api-production.up.railway.app/api';

  // Test 1: Health Check
  print('═══════════════════════════════════════');
  print('TEST 1: Health Check');
  print('═══════════════════════════════════════');
  await testHealthCheck(baseUrl);

  print('\n═══════════════════════════════════════');
  print('TEST 2: Login with Admin Credentials');
  print('═══════════════════════════════════════');
  await testLogin(baseUrl, 'admin@fincount.com', 'admin123');

  print('\n═══════════════════════════════════════');
  print('TEST 3: Login with Test User');
  print('═══════════════════════════════════════');
  await testLogin(baseUrl, 'user@fincount.com', 'user123');

  print('\n═══════════════════════════════════════');
  print('TEST 4: Registration');
  print('═══════════════════════════════════════');
  await testRegistration(baseUrl);

  print('\n═══════════════════════════════════════');
  print('TEST 5: Get Batches (No Auth)');
  print('═══════════════════════════════════════');
  await testGetBatches(baseUrl, null);

  print('\n═══════════════════════════════════════');
  print('TEST 6: Get Sessions (No Auth)');
  print('═══════════════════════════════════════');
  await testGetSessions(baseUrl, null);

  print('\n\n✅ Full API Test Complete!');
  print('═══════════════════════════════════════\n');
}

Future<void> testHealthCheck(String baseUrl) async {
  print('📡 Endpoint: GET $baseUrl/health');

  try {
    final uri = Uri.parse('$baseUrl/health');
    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ).timeout(const Duration(seconds: 10));

    print('📊 Status Code: ${response.statusCode}');
    print('📄 Response Body: ${response.body}');

    if (response.statusCode == 200) {
      print('✅ PASS: Health check successful');
    } else if (response.statusCode == 502) {
      print('❌ FAIL: API is down (502 Bad Gateway)');
      print('⚠️  Railway application is not responding');
    } else {
      print('⚠️  WARNING: Unexpected status code');
    }
  } catch (e) {
    print('❌ ERROR: $e');
  }
}

Future<void> testLogin(String baseUrl, String email, String password) async {
  print('📡 Endpoint: POST $baseUrl/auth/login');
  print('📝 Request Body:');

  final requestBody = {
    'email': email,
    'password': password,
  };

  print('   ${jsonEncode(requestBody)}');

  try {
    final uri = Uri.parse('$baseUrl/auth/login');
    final response = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(requestBody),
        )
        .timeout(const Duration(seconds: 10));

    print('📊 Status Code: ${response.statusCode}');
    print('📄 Response Body: ${response.body}');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['token'] != null) {
        print('✅ PASS: Login successful');
        print('🔑 Token: ${data['token'].substring(0, 30)}...');
      } else {
        print('⚠️  WARNING: No token in response');
      }
    } else if (response.statusCode == 401) {
      print('❌ FAIL: Invalid credentials');
      print('💡 TIP: Database might not be seeded with default users');
    } else if (response.statusCode == 502) {
      print('❌ FAIL: API is down (502 Bad Gateway)');
    } else {
      print('⚠️  WARNING: Unexpected status code');
    }
  } catch (e) {
    print('❌ ERROR: $e');
  }
}

Future<void> testRegistration(String baseUrl) async {
  print('📡 Endpoint: POST $baseUrl/auth/register');
  print('📝 Request Body:');

  final requestBody = {
    'email': 'newuser@test.com',
    'password': 'password123',
    'name': 'New Test User',
  };

  print('   ${jsonEncode(requestBody)}');

  try {
    final uri = Uri.parse('$baseUrl/auth/register');
    final response = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(requestBody),
        )
        .timeout(const Duration(seconds: 10));

    print('📊 Status Code: ${response.statusCode}');
    print('📄 Response Body: ${response.body}');

    if (response.statusCode == 201) {
      print('✅ PASS: Registration successful');
    } else if (response.statusCode == 500) {
      print('❌ FAIL: Internal Server Error');
      print('💡 TIP: Database might not be configured properly');
    } else if (response.statusCode == 502) {
      print('❌ FAIL: API is down (502 Bad Gateway)');
    } else {
      print('⚠️  WARNING: Unexpected status code');
    }
  } catch (e) {
    print('❌ ERROR: $e');
  }
}

Future<void> testGetBatches(String baseUrl, String? token) async {
  print('📡 Endpoint: GET $baseUrl/batches');

  try {
    final uri = Uri.parse('$baseUrl/batches');
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }

    final response = await http
        .get(
          uri,
          headers: headers,
        )
        .timeout(const Duration(seconds: 10));

    print('📊 Status Code: ${response.statusCode}');
    print('📄 Response Body: ${response.body}');

    if (response.statusCode == 200) {
      print('✅ PASS: Batches retrieved successfully');
    } else if (response.statusCode == 403 || response.statusCode == 401) {
      print('⚠️  INFO: Authentication required (expected)');
    } else if (response.statusCode == 502) {
      print('❌ FAIL: API is down (502 Bad Gateway)');
    } else {
      print('⚠️  WARNING: Unexpected status code');
    }
  } catch (e) {
    print('❌ ERROR: $e');
  }
}

Future<void> testGetSessions(String baseUrl, String? token) async {
  print('📡 Endpoint: GET $baseUrl/sessions');

  try {
    final uri = Uri.parse('$baseUrl/sessions');
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }

    final response = await http
        .get(
          uri,
          headers: headers,
        )
        .timeout(const Duration(seconds: 10));

    print('📊 Status Code: ${response.statusCode}');
    print('📄 Response Body: ${response.body}');

    if (response.statusCode == 200) {
      print('✅ PASS: Sessions retrieved successfully');
    } else if (response.statusCode == 403 || response.statusCode == 401) {
      print('⚠️  INFO: Authentication required (expected)');
    } else if (response.statusCode == 502) {
      print('❌ FAIL: API is down (502 Bad Gateway)');
    } else {
      print('⚠️  WARNING: Unexpected status code');
    }
  } catch (e) {
    print('❌ ERROR: $e');
  }
}
