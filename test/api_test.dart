import 'dart:convert';
import 'package:http/http.dart' as http;

// Test script for Railway FastAPI endpoints
void main() async {
  print('🚀 Testing Fincount API on Railway...\n');

  const String baseUrl = 'https://fincount-api-production.up.railway.app/api';

  // Test 1: Health Check
  await testHealthCheck(baseUrl);

  // Test 2: Root endpoint
  await testRootEndpoint();

  // Test 3: Batches endpoint (without auth)
  await testBatchesEndpoint(baseUrl);

  // Test 4: Sessions endpoint (without auth)
  await testSessionsEndpoint(baseUrl);

  print('\n✅ API Testing Complete!');
}

Future<void> testHealthCheck(String baseUrl) async {
  print('📡 Test 1: Health Check Endpoint');
  print('   URL: $baseUrl/health');

  try {
    final response = await http.get(
      Uri.parse('$baseUrl/health'),
      headers: {'Content-Type': 'application/json'},
    ).timeout(const Duration(seconds: 10));

    print('   Status: ${response.statusCode}');
    print('   Response: ${response.body}');

    if (response.statusCode == 200) {
      print('   ✅ Health check passed!\n');
    } else {
      print('   ⚠️  Unexpected status code\n');
    }
  } catch (e) {
    print('   ❌ Error: $e\n');
  }
}

Future<void> testRootEndpoint() async {
  print('📡 Test 2: Root Endpoint');
  print('   URL: https://fincount-api-production.up.railway.app/');

  try {
    final response = await http.get(
      Uri.parse('https://fincount-api-production.up.railway.app/'),
      headers: {'Content-Type': 'application/json'},
    ).timeout(const Duration(seconds: 10));

    print('   Status: ${response.statusCode}');
    print('   Response: ${response.body}');

    if (response.statusCode == 200) {
      print('   ✅ Root endpoint accessible!\n');
    } else {
      print('   ⚠️  Unexpected status code\n');
    }
  } catch (e) {
    print('   ❌ Error: $e\n');
  }
}

Future<void> testBatchesEndpoint(String baseUrl) async {
  print('📡 Test 3: Batches Endpoint (GET)');
  print('   URL: $baseUrl/batches');

  try {
    final response = await http.get(
      Uri.parse('$baseUrl/batches'),
      headers: {'Content-Type': 'application/json'},
    ).timeout(const Duration(seconds: 10));

    print('   Status: ${response.statusCode}');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      print('   Response: ${jsonEncode(data)}');
      print('   ✅ Batches endpoint accessible!\n');
    } else if (response.statusCode == 401) {
      print('   ⚠️  Authentication required (expected)');
      print('   Response: ${response.body}\n');
    } else {
      print('   Response: ${response.body}\n');
    }
  } catch (e) {
    print('   ❌ Error: $e\n');
  }
}

Future<void> testSessionsEndpoint(String baseUrl) async {
  print('📡 Test 4: Sessions Endpoint (GET)');
  print('   URL: $baseUrl/sessions');

  try {
    final response = await http.get(
      Uri.parse('$baseUrl/sessions'),
      headers: {'Content-Type': 'application/json'},
    ).timeout(const Duration(seconds: 10));

    print('   Status: ${response.statusCode}');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      print('   Response: ${jsonEncode(data)}');
      print('   ✅ Sessions endpoint accessible!\n');
    } else if (response.statusCode == 401) {
      print('   ⚠️  Authentication required (expected)');
      print('   Response: ${response.body}\n');
    } else {
      print('   Response: ${response.body}\n');
    }
  } catch (e) {
    print('   ❌ Error: $e\n');
  }
}
