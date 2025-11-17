import 'package:http/http.dart' as http;
import 'dart:convert';

/// Test script to verify login with default credentials
void main() async {
  print('🧪 Testing Login with Default Credentials\n');

  const String baseUrl = 'https://fincount-api-production.up.railway.app/api';

  // Test 1: Admin Login
  await testLogin(
    baseUrl,
    'admin@fincount.com',
    'admin123',
    'Admin Account',
  );

  print('\n---\n');

  // Test 2: Test User Login
  await testLogin(
    baseUrl,
    'user@fincount.com',
    'user123',
    'Test User Account',
  );

  print('\n✅ Login Testing Complete!');
}

Future<void> testLogin(
  String baseUrl,
  String email,
  String password,
  String accountName,
) async {
  print('📝 Testing: $accountName');
  print('   Email: $email');
  print('   Password: $password');

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
            'email': email,
            'password': password,
          }),
        )
        .timeout(const Duration(seconds: 10));

    print('   Status: ${response.statusCode}');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      print('   Response: ${jsonEncode(data)}');

      // Check if token exists
      if (data['token'] != null) {
        print('   ✅ Login successful!');
        print('   ✅ Token received: ${data['token'].substring(0, 20)}...');

        // Check user data
        if (data['user'] != null) {
          print(
              '   ✅ User data: ${data['user']['name']} (${data['user']['email']})');
        }
      } else {
        print('   ⚠️  Login succeeded but no token in response');
      }
    } else {
      print('   ❌ Login failed');
      print('   Response: ${response.body}');
    }
  } catch (e) {
    print('   ❌ Error: $e');
  }
}
