# API Request Monitoring Guide

This guide explains how to monitor API requests when running your Flutter app on a physical device.

## 🎯 Overview

The app now includes comprehensive API request logging that displays:
- Request method, URL, headers, and body
- Response status code, headers, and body
- Request timing and duration
- Authentication status
- Error messages with detailed context

## 📋 Setup Instructions

### Option 1: Use the New Logging Service (Recommended)

The new `api_service_with_logging.dart` file includes built-in HTTP interceptors that automatically log all API requests.

**To enable it:**

1. **Replace imports** in your files that use `ApiService`:

   **Before:**
   ```dart
   import 'package:fish_detection_app/services/api_service.dart';
   ```

   **After:**
   ```dart
   import 'package:fish_detection_app/services/api_service_with_logging.dart';
   ```

2. **Files to update:**
   - `lib/Login_Page.dart`
   - `lib/Dashboard_Page.dart`
   - `lib/Session_Page.dart`
   - `lib/Batches_Page.dart`
   - `lib/User_Page.dart`
   - `lib/services/hybrid_session_service.dart`
   - Any other files that import `api_service.dart`

### Option 2: Keep Original Service (Manual Logging)

If you prefer to keep the original service, you can add manual logging by adding print statements before/after API calls.

## 🚀 Running the App with Logging

### 1. Connect Your Device

```bash
# Check if device is connected
flutter devices
```

You should see your device `JUC7N18730003222` in the list.

### 2. Run the App

```bash
flutter run -d JUC7N18730003222
```

### 3. View Logs in Real-Time

The console will display detailed logs for every API request:

```
╔════════════════════════════════════════════════════════════════
║ 🚀 API REQUEST
╠════════════════════════════════════════════════════════════════
║ Method: POST
║ URL: https://your-api.com/auth/login
║ Headers: {Content-Type: application/json, Accept: application/json}
║ Body:
{
  "email": "user@example.com",
  "password": "********"
}
╚════════════════════════════════════════════════════════════════

⏱️ Starting POST request to: /auth/login
✅ Request completed in 234ms

╔════════════════════════════════════════════════════════════════
║ 📥 API RESPONSE
╠════════════════════════════════════════════════════════════════
║ Status Code: 200
║ URL: https://your-api.com/auth/login
║ Headers: {content-type: application/json}
║ Response Body:
{
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "user": {
    "id": "123",
    "email": "user@example.com"
  }
}
╚════════════════════════════════════════════════════════════════
```

## 📱 Monitoring Methods

### Method 1: VS Code Terminal (Recommended)

When you run `flutter run -d JUC7N18730003222` from VS Code terminal, all logs appear directly in the terminal window.

**Advantages:**
- Real-time logging
- Easy to scroll and search
- Can copy/paste logs
- Color-coded output

### Method 2: Android Studio Logcat

If using Android Studio:

1. Open **Logcat** tab at the bottom
2. Select your device `JUC7N18730003222`
3. Filter by package name: `fish_detection_app`
4. All print statements will appear here

### Method 3: ADB Logcat (Command Line)

```bash
# View all logs from your app
adb -s JUC7N18730003222 logcat | grep -i "flutter"

# Or filter by specific tags
adb -s JUC7N18730003222 logcat | grep -E "API REQUEST|API RESPONSE"
```

### Method 4: Flutter DevTools

```bash
# Run the app first
flutter run -d JUC7N18730003222

# Then open DevTools (URL will be shown in console)
# Navigate to Logging tab to see all print statements
```

## 🔍 What You'll See

### Request Indicators

- 🚀 **API REQUEST** - Outgoing request details
- 📥 **API RESPONSE** - Incoming response details
- ⏱️ **Timing** - Request duration
- 🔐 **Auth Status** - Whether token is being used
- 🌐 **Base URL** - Which API endpoint is being used

### Status Indicators

- ✅ **Success** - Operation completed successfully
- ❌ **Error** - Operation failed
- ⚠️ **Warning** - Potential issue detected
- 🔄 **Sync** - Data synchronization in progress
- 💾 **Storage** - Local data operation

### Specific Operations

- 🔑 **Login** - Authentication attempt
- 📝 **Register** - User registration
- 🚪 **Logout** - User logout
- 📊 **Session** - Session operations
- 📦 **Batch** - Batch operations
- 👤 **User** - User profile operations
- 📸 **Upload** - Image upload operations
- 🏥 **Health** - API health check

## 🐛 Debugging Tips

### 1. Check API Base URL

Look for this log at app startup:
```
🌐 Using API Base URL: https://your-api.com
```

If you see the wrong URL, check your `.env` file.

### 2. Verify Authentication

Look for these logs:
```
🔐 Using authentication token
```
or
```
⚠️ No authentication token found
```

### 3. Monitor Request Timing

Slow requests will show high millisecond values:
```
✅ Request completed in 5234ms  // This is slow (5+ seconds)
```

### 4. Check for Connection Issues

Look for these error patterns:
```
❌ No internet connection: SocketException...
❌ HTTP error occurred: ...
❌ Request failed: ...
```

## 📊 Common Scenarios

### Scenario 1: Login Not Working

**What to check in logs:**
1. Is the request being sent? (Look for 🚀 API REQUEST)
2. What's the response status? (Look for status code)
3. Is the URL correct? (Check the URL in request)
4. What's the error message? (Check response body)

### Scenario 2: Data Not Syncing

**What to check in logs:**
1. Look for 🔄 Syncing messages
2. Check if requests are reaching the server
3. Verify authentication token is present
4. Check response status codes

### Scenario 3: Images Not Uploading

**What to check in logs:**
1. Look for 📸 Uploading image messages
2. Check 📤 Sending multipart request
3. Verify 📥 Upload response status
4. Check for file path errors

## 🔧 Advanced Monitoring

### Filter Specific Requests

In your terminal, you can filter logs:

```bash
# Only show login requests
flutter run -d JUC7N18730003222 | grep "login"

# Only show errors
flutter run -d JUC7N18730003222 | grep "❌"

# Only show successful operations
flutter run -d JUC7N18730003222 | grep "✅"
```

### Save Logs to File

```bash
# Save all logs to a file
flutter run -d JUC7N18730003222 > app_logs.txt 2>&1

# Then view the file
cat app_logs.txt
```

### Monitor Network Traffic

For even more detailed monitoring, use:

1. **Charles Proxy** - HTTP/HTTPS proxy for monitoring
2. **Wireshark** - Network packet analyzer
3. **Android Studio Network Profiler** - Built-in network monitoring

## 🎨 Customizing Logs

To add more logging to specific operations, edit `api_service_with_logging.dart`:

```dart
// Add custom log before an operation
print('🔍 Custom debug info: $someVariable');

// Add custom log after an operation
print('📈 Operation result: $result');
```

## 📝 Best Practices

1. **Always check logs** when testing new features
2. **Monitor during first run** on a new device
3. **Check logs after app updates** to verify API compatibility
4. **Save logs** when reporting bugs
5. **Filter logs** to focus on specific issues
6. **Use emojis** to quickly identify log types

## 🚨 Troubleshooting

### Logs Not Appearing?

1. **Check if app is in debug mode:**
   ```bash
   flutter run -d JUC7N18730003222 --debug
   ```

2. **Verify device connection:**
   ```bash
   flutter devices
   ```

3. **Clear and rebuild:**
   ```bash
   flutter clean
   flutter pub get
   flutter run -d JUC7N18730003222
   ```

### Too Many Logs?

If logs are overwhelming, you can:

1. Comment out specific print statements in `api_service_with_logging.dart`
2. Use grep to filter in terminal
3. Adjust log levels in your IDE

## 📞 Support

If you encounter issues:

1. Check the logs for error messages
2. Verify your `.env` configuration
3. Ensure your API server is running
4. Check network connectivity
5. Review the API endpoint documentation

## 🎯 Quick Reference

| Symbol | Meaning |
|--------|---------|
| 🚀 | API Request |
| 📥 | API Response |
| ✅ | Success |
| ❌ | Error |
| ⚠️ | Warning |
| 🔐 | Authentication |
| 🌐 | Network/URL |
| ⏱️ | Timing |
| 🔄 | Sync |
| 💾 | Storage |
| 📊 | Session |
| 📦 | Batch |
| 👤 | User |
| 📸 | Upload |
| 🏥 | Health Check |

---

**Happy Debugging! 🎉**
