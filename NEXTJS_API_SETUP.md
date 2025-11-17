# Next.js API Integration Setup Guide

This guide will help you connect your Flutter application to a Next.js backend API.

## Overview

Your Flutter app is already configured with:
- ✅ API service layer (`lib/services/api_service.dart`)
- ✅ Environment variable support (`.env` file)
- ✅ Offline-first architecture with local storage
- ✅ Authentication token management
- ✅ Automatic sync capabilities

## Prerequisites

- Node.js (v18 or higher)
- Flutter SDK (v3.0 or higher)
- A database (PostgreSQL, MySQL, or MongoDB recommended)

## Step 1: Set Up Your Next.js Backend

### 1.1 Create a New Next.js Project

```bash
npx create-next-app@latest fish-detection-api
cd fish-detection-api
```

When prompted, select:
- TypeScript: Yes (recommended) or No
- ESLint: Yes
- Tailwind CSS: Optional
- `src/` directory: Yes (recommended)
- App Router: Yes (recommended) or No (Pages Router)
- Import alias: Yes (@/*)

### 1.2 Install Required Dependencies

```bash
npm install jsonwebtoken bcryptjs multer cors
npm install -D @types/jsonwebtoken @types/bcryptjs @types/multer
```

For database (choose one):
```bash
# PostgreSQL with Prisma
npm install @prisma/client
npm install -D prisma

# Or MongoDB with Mongoose
npm install mongoose

# Or MySQL
npm install mysql2
```

### 1.3 Copy API Route Examples

Copy the API route files from the `nextjs-api-examples/` directory in your Flutter project to your Next.js project:

**For App Router (Next.js 13+):**
```
nextjs-api-examples/health.js → app/api/health/route.js
nextjs-api-examples/auth/login.js → app/api/auth/login/route.js
nextjs-api-examples/sessions/index.js → app/api/sessions/route.js
```

**For Pages Router (Next.js 12 and below):**
```
nextjs-api-examples/health.js → pages/api/health.js
nextjs-api-examples/auth/login.js → pages/api/auth/login.js
nextjs-api-examples/sessions/index.js → pages/api/sessions/index.js
```

### 1.4 Configure Environment Variables

Create a `.env.local` file in your Next.js project root:

```env
# JWT Secret (generate a strong random string)
JWT_SECRET=your-super-secret-jwt-key-change-this-in-production

# Database Connection
DATABASE_URL=postgresql://user:password@localhost:5432/fish_detection_db
# Or for MongoDB: mongodb://localhost:27017/fish_detection_db

# File Upload Directory
UPLOAD_DIR=./public/uploads

# CORS Settings (for development)
ALLOWED_ORIGINS=http://localhost:3000,http://localhost:8080

# App Settings
NODE_ENV=development
PORT=3000
```

### 1.5 Set Up Database Schema

**For PostgreSQL/MySQL (using Prisma):**

1. Initialize Prisma:
```bash
npx prisma init
```

2. Update `prisma/schema.prisma`:
```prisma
datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

generator client {
  provider = "prisma-client-js"
}

model User {
  id           Int       @id @default(autoincrement())
  email        String    @unique
  name         String
  passwordHash String    @map("password_hash")
  createdAt    DateTime  @default(now()) @map("created_at")
  sessions     Session[]
  batches      Batch[]

  @@map("users")
}

model Session {
  id        String   @id
  userId    Int      @map("user_id")
  batchId   String   @map("batch_id")
  species   String
  location  String
  notes     String?
  counts    Json
  timestamp DateTime
  imageUrl  String?  @map("image_url")
  createdAt DateTime @default(now()) @map("created_at")
  user      User     @relation(fields: [userId], references: [id])

  @@map("sessions")
}

model Batch {
  id          String   @id
  userId      Int      @map("user_id")
  species     String
  location    String
  notes       String?
  totalCounts Json     @map("total_counts")
  lastUpdate  DateTime @map("last_update")
  createdAt   DateTime @default(now()) @map("created_at")
  user        User     @relation(fields: [userId], references: [id])

  @@map("batches")
}
```

3. Run migrations:
```bash
npx prisma migrate dev --name init
npx prisma generate
```

### 1.6 Start Your Next.js Server

```bash
npm run dev
```

Your API should now be running at `http://localhost:3000`

## Step 2: Configure Your Flutter App

### 2.1 Update Environment Variables

Edit the `.env` file in your Flutter project root:

```env
# API Configuration
# For local development (Android Emulator)
API_BASE_URL=http://10.0.2.2:3000/api

# For local development (iOS Simulator)
# API_BASE_URL=http://localhost:3000/api

# For local development (Physical Device - use your computer's IP)
# API_BASE_URL=http://192.168.1.XXX:3000/api

# For production
# API_BASE_URL=https://your-nextjs-app.vercel.app/api

# Authentication
JWT_SECRET=your-jwt-secret-key

# App Settings
APP_ENV=development
```

**Important Notes:**
- **Android Emulator**: Use `10.0.2.2` instead of `localhost`
- **iOS Simulator**: Use `localhost` or `127.0.0.1`
- **Physical Device**: Use your computer's local IP address (find it with `ipconfig` on Windows or `ifconfig` on Mac/Linux)

### 2.2 Install Flutter Dependencies

Run the following command in your Flutter project directory:

```bash
flutter pub get
```

This will install all required packages including:
- `http` - For making API requests
- `flutter_dotenv` - For environment variable management
- `shared_preferences` - For storing authentication tokens
- And other dependencies

### 2.3 Verify the Setup

The Flutter app is already configured with:

1. **API Service** (`lib/services/api_service.dart`):
   - Handles all HTTP requests
   - Manages authentication tokens
   - Provides error handling
   - Supports offline mode

2. **Hybrid Session Service** (`lib/services/hybrid_session_service.dart`):
   - Offline-first architecture
   - Automatic sync when online
   - Local storage with Hive

3. **Environment Loading** (`lib/main.dart`):
   - Loads `.env` file on app startup
   - Makes API_BASE_URL available throughout the app

## Step 3: Test the Connection

### 3.1 Test API Health Check

You can test if your API is accessible from Flutter by adding this test to your app:

```dart
import 'package:fish_detection_app/services/api_service.dart';

// Test connection
void testApiConnection() async {
  try {
    bool isConnected = await ApiService.checkConnection();
    print('API Connection: ${isConnected ? "SUCCESS" : "FAILED"}');
  } catch (e) {
    print('API Connection Error: $e');
  }
}
```

### 3.2 Test from Command Line

Test your Next.js API endpoints:

```bash
# Health check
curl http://localhost:3000/api/health

# Register a user
curl -X POST http://localhost:3000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"password123","name":"Test User"}'

# Login
curl -X POST http://localhost:3000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"password123"}'
```

## Step 4: Run Your Flutter App

### 4.1 For Android

```bash
flutter run
```

### 4.2 For iOS

```bash
flutter run
```

### 4.3 For Web

```bash
flutter run -d chrome
```

## Available API Endpoints

Your Flutter app is configured to use these endpoints:

### Authentication
- `POST /api/auth/login` - User login
- `POST /api/auth/register` - User registration
- `POST /api/auth/logout` - User logout

### Sessions
- `GET /api/sessions` - Get all sessions
- `POST /api/sessions` - Create new session
- `GET /api/sessions/batch/:batchId` - Get sessions by batch
- `PUT /api/sessions/:sessionId` - Update session
- `DELETE /api/sessions/:sessionId` - Delete session

### Batches
- `GET /api/batches` - Get all batches
- `POST /api/batches` - Create new batch

### File Upload
- `POST /api/upload/image` - Upload session images

### Sync & Health
- `POST /api/sync` - Sync multiple sessions
- `GET /api/health` - Health check

## Troubleshooting

### Common Issues

1. **Connection Refused Error**
   - Make sure your Next.js server is running
   - Check if you're using the correct IP address
   - For Android emulator, use `10.0.2.2` instead of `localhost`

2. **CORS Errors**
   - Add CORS middleware to your Next.js API
   - Configure allowed origins in your Next.js app

3. **Authentication Errors**
   - Verify JWT_SECRET matches between Flutter and Next.js
   - Check if token is being saved correctly
   - Ensure Authorization header is being sent

4. **Environment Variables Not Loading**
   - Make sure `.env` is in the project root
   - Verify `.env` is listed in `pubspec.yaml` assets
   - Run `flutter clean` and `flutter pub get`

### Debug Mode

Enable debug logging in your Flutter app:

```dart
// In api_service.dart, add logging
print('Making request to: $uri');
print('Headers: $requestHeaders');
print('Response: ${response.body}');
```

## Production Deployment

### Deploy Next.js API

1. **Vercel (Recommended)**:
```bash
npm install -g vercel
vercel
```

2. **Other platforms**: Railway, Render, AWS, Google Cloud, etc.

### Update Flutter App for Production

1. Update `.env`:
```env
API_BASE_URL=https://your-nextjs-app.vercel.app/api
APP_ENV=production
```

2. Build your Flutter app:
```bash
# Android
flutter build apk --release

# iOS
flutter build ios --release

# Web
flutter build web --release
```

## Security Best Practices

1. **Never commit sensitive data**:
   - Add `.env` to `.gitignore`
   - Use different secrets for development and production

2. **Use HTTPS in production**:
   - Always use HTTPS for API endpoints in production
   - Enable SSL certificate validation

3. **Implement rate limiting**:
   - Add rate limiting to your Next.js API
   - Protect against brute force attacks

4. **Validate all inputs**:
   - Sanitize user inputs on both client and server
   - Use proper validation libraries

5. **Keep dependencies updated**:
   - Regularly update Flutter and Next.js dependencies
   - Monitor for security vulnerabilities

## Additional Resources

- [Next.js Documentation](https://nextjs.org/docs)
- [Flutter HTTP Package](https://pub.dev/packages/http)
- [Flutter Dotenv Package](https://pub.dev/packages/flutter_dotenv)
- [Prisma Documentation](https://www.prisma.io/docs)

## Support

If you encounter any issues:
1. Check the troubleshooting section above
2. Review the API examples in `nextjs-api-examples/`
3. Check your Next.js server logs
4. Enable debug logging in Flutter

---

**Last Updated**: October 30, 2025
