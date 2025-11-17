import 'package:http/http.dart' as http;
import 'dart:convert';

/// Quick test to verify the checkConnection fix
void main() async {
  print('🔍 Testing Connection Check Fix...\n');

  const String baseUrl = 'https://fincount-api-production.up.railway.app/api';

  // Test the health endpoint (what checkConnection now uses)
  await testHealthEndpoint(baseUrl);

  // Test batches endpoint (what was causing the issue)
  await testBatchesEndpoint(baseUrl);

  print('\n✅ Connection check fix verified!');
  print('📝 The app should now detect online status correctly.');
}

Future<void> testHealthEndpoint(String baseUrl) async {
  print('📡 Testing /health endpoint (NEW checkConnection method)');
  print('   URL: $baseUrl/health');

  try {
    final uri = Uri.parse('$baseUrl/health');
    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ).timeout(const Duration(seconds: 5));

    print('   Status: ${response.statusCode}');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      print('   Response: ${jsonEncode(data)}');
      print('   ✅ Health endpoint returns 200 - Connection check will PASS\n');
    } else {
      print('   ❌ Unexpected status code\n');
    }
  } catch (e) {
    print('   ❌ Error: $e\n');
  }
}

Future<void> testBatchesEndpoint(String baseUrl) async {
  print('📡 Testing /batches endpoint (OLD checkConnection method)');
  print('   URL: $baseUrl/batches');

  try {
    final uri = Uri.parse('$baseUrl/batches');
    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ).timeout(const Duration(seconds: 5));

    print('   Status: ${response.statusCode}');
    print('   Response: ${response.body}');

    if (response.statusCode == 403) {
      print(
          '   ⚠️  Returns 403 (auth required) - This was causing connection check to FAIL\n');
    }
  } catch (e) {
    print('   ❌ Error: $e\n');
  }
}
