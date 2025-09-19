# Next.js API Integration for Fish Detection App

This directory contains example Next.js API routes that your Flutter app can connect to. These examples show how to set up the backend endpoints that correspond to the API calls in your Flutter app.

## Setup Instructions

1. Create a new Next.js project or add these routes to your existing Next.js app:
```bash
npx create-next-app@latest fish-detection-api
cd fish-detection-api
```

2. Install required dependencies:
```bash
npm install jsonwebtoken bcryptjs multer cors
npm install -D @types/jsonwebtoken @types/bcryptjs @types/multer
```

3. Copy the API route files from this directory to your Next.js `pages/api/` or `app/api/` directory (depending on your Next.js version).

4. Set up your environment variables in `.env.local`:
```
JWT_SECRET=your-super-secret-jwt-key
DATABASE_URL=your-database-connection-string
UPLOAD_DIR=./public/uploads
```

## API Endpoints

### Authentication
- `POST /api/auth/login` - User login
- `POST /api/auth/register` - User registration
- `POST /api/auth/logout` - User logout

### Sessions
- `GET /api/sessions` - Get all sessions for authenticated user
- `POST /api/sessions` - Create a new session
- `GET /api/sessions/batch/[batchId]` - Get sessions for a specific batch
- `PUT /api/sessions/[sessionId]` - Update a session
- `DELETE /api/sessions/[sessionId]` - Delete a session

### Batches
- `GET /api/batches` - Get all batches for authenticated user
- `POST /api/batches` - Create a new batch

### File Upload
- `POST /api/upload/image` - Upload session images

### Sync & Health
- `POST /api/sync` - Sync multiple sessions at once
- `GET /api/health` - Health check endpoint

## Database Schema

You'll need to set up tables for:

### Users
```sql
CREATE TABLE users (
  id SERIAL PRIMARY KEY,
  email VARCHAR(255) UNIQUE NOT NULL,
  name VARCHAR(255) NOT NULL,
  password_hash VARCHAR(255) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### Sessions
```sql
CREATE TABLE sessions (
  id VARCHAR(255) PRIMARY KEY,
  user_id INTEGER REFERENCES users(id),
  batch_id VARCHAR(255) NOT NULL,
  species VARCHAR(255) NOT NULL,
  location VARCHAR(255) NOT NULL,
  notes TEXT,
  counts JSONB NOT NULL,
  timestamp TIMESTAMP NOT NULL,
  image_url VARCHAR(500),
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

### Batches
```sql
CREATE TABLE batches (
  id VARCHAR(255) PRIMARY KEY,
  user_id INTEGER REFERENCES users(id),
  species VARCHAR(255) NOT NULL,
  location VARCHAR(255) NOT NULL,
  notes TEXT,
  total_counts JSONB NOT NULL,
  last_update TIMESTAMP NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

## Flutter Integration

Your Flutter app is already configured to work with these endpoints. Make sure to:

1. Update the `API_BASE_URL` in your `.env` file to point to your Next.js server
2. Use the `HybridSessionService` for offline-first functionality
3. Add the `SyncStatusWidget` to your UI to show connection status

## Testing

You can test the API endpoints using tools like Postman or curl:

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
