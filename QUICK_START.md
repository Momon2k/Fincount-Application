# Quick Start Guide - Connecting Flutter to Next.js API

## ⚡ Quick Setup (5 Minutes)

### 1. Install Flutter Dependencies ✅
```bash
flutter pub get
```
**Status**: Already completed!

### 2. Configure Your API URL

Edit `.env` file in your project root:

**For Android Emulator:**
```env
API_BASE_URL=http://10.0.2.2:3000/api
```

**For iOS Simulator:**
```env
API_BASE_URL=http://localhost:3000/api
```

**For Physical Device:**
```env
API_BASE_URL=http://YOUR_COMPUTER_IP:3000/api
```
(Find your IP: Run `ipconfig` on Windows or `ifconfig` on Mac/Linux)

### 3. Set Up Next.js Backend (Optional - if you don't have one yet)

```bash
# Create Next.js project
npx create-next-app@latest fish-detection-api
cd fish-detection-api

# Install dependencies
npm install jsonwebtoken bcryptjs multer cors

# Copy API examples from your Flutter project
# nextjs-api-examples/ → your Next.js app/api/ or pages/api/

# Start server
npm run dev
```

### 4. Test the Connection

Run your Flutter app:
```bash
flutter run
```

The app will automatically:
- ✅ Load environment variables from `.env`
- ✅ Connect to your Next.js API
- ✅ Work offline if API is unavailable
- ✅ Sync data when connection is restored

## 📱 What's Already Configured

Your Flutter app includes:

✅ **API Service** (`lib/services/api_service.dart`)
- All HTTP methods (GET, POST, PUT, DELETE)
- Authentication token management
- Error handling
- Timeout handling

✅ **Offline Support** (`lib/services/hybrid_session_service.dart`)
- Local storage with Hive
- Automatic sync when online
- Queue management

✅ **Environment Variables**
- `.env` file support
- Loaded on app startup
- Easy configuration switching

## 🔌 Available API Endpoints

Your app is ready to use these endpoints:

### Authentication
```dart
// Login
await ApiService.login(email, password);

// Register
await ApiService.register(email, password, name);

// Logout
await ApiService.logout();
```

### Sessions
```dart
// Create session
await ApiService.createSession(session);

// Get all sessions
await ApiService.getAllSessions();

// Get batch sessions
await ApiService.getBatchSessions(batchId);

// Update session
await ApiService.updateSession(sessionId, session);

// Delete session
await ApiService.deleteSession(sessionId);
```

### Batches
```dart
// Get all batches
await ApiService.getAllBatches();

// Create batch
await ApiService.createBatch(batchData);
```

### File Upload
```dart
// Upload image
await ApiService.uploadImage(imageFile, sessionId);
```

### Sync & Health
```dart
// Sync local data
await ApiService.syncLocalData(localSessions);

// Check connection
await ApiService.checkConnection();
```

## 🧪 Testing

### Test API Connection

Add this to any page to test:

```dart
import 'package:fish_detection_app/services/api_service.dart';

void testConnection() async {
  try {
    bool isConnected = await ApiService.checkConnection();
    print('API Status: ${isConnected ? "✅ Connected" : "❌ Disconnected"}');
  } catch (e) {
    print('Error: $e');
  }
}
```

### Test from Terminal

```bash
# Test health endpoint
curl http://localhost:3000/api/health

# Should return: {"status":"ok","timestamp":"..."}
```

## 🚨 Troubleshooting

### "Connection Refused" Error

**Android Emulator:**
- Use `http://10.0.2.2:3000/api` (NOT localhost)

**iOS Simulator:**
- Use `http://localhost:3000/api`

**Physical Device:**
- Use your computer's IP: `http://192.168.1.XXX:3000/api`
- Make sure device and computer are on same WiFi

### "Environment Variables Not Loading"

```bash
# Clean and rebuild
flutter clean
flutter pub get
flutter run
```

### "CORS Error"

Add CORS middleware to your Next.js API:
```javascript
// In your Next.js API route
export async function GET(request) {
  return new Response(JSON.stringify(data), {
    headers: {
      'Access-Control-Allow-Origin': '*',
      'Content-Type': 'application/json',
    },
  });
}
```

## 📚 Next Steps

1. **Read Full Documentation**: See `NEXTJS_API_SETUP.md` for complete setup
2. **Review API Examples**: Check `nextjs-api-examples/` folder
3. **Customize Endpoints**: Modify `lib/services/api_service.dart` as needed
4. **Add Features**: Use the existing service layer to add new API calls

## 🎯 Key Files

- `.env` - API configuration
- `lib/services/api_service.dart` - API client
- `lib/services/hybrid_session_service.dart` - Offline support
- `lib/main.dart` - App initialization
- `NEXTJS_API_SETUP.md` - Full documentation

## ✨ Features

- 🔐 **Authentication**: JWT token management
- 💾 **Offline First**: Works without internet
- 🔄 **Auto Sync**: Syncs when connection restored
- ⚡ **Fast**: Local storage with Hive
- 🛡️ **Secure**: Token-based authentication
- 📱 **Cross-Platform**: Android, iOS, Web

---

**Need Help?** Check `NEXTJS_API_SETUP.md` for detailed documentation.
