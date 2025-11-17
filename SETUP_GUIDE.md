# Complete Setup Guide: Integrating FastAPI with Flutter

This guide will walk you through setting up and connecting your FastAPI backend with the Fincount Flutter application.

## 📋 Prerequisites

- Python 3.8 or higher
- Flutter SDK installed
- A code editor (VS Code recommended)
- Basic knowledge of terminal/command line

---

## 🚀 Part 1: Setting Up FastAPI Backend

### Step 1: Navigate to the FastAPI Example Directory

```bash
cd fastapi-example
```

### Step 2: Create a Virtual Environment (Recommended)

**Windows:**
```bash
python -m venv venv
venv\Scripts\activate
```

**Mac/Linux:**
```bash
python3 -m venv venv
source venv/bin/activate
```

### Step 3: Install Dependencies

```bash
pip install -r requirements.txt
```

This will install:
- FastAPI
- Uvicorn (ASGI server)
- SQLAlchemy (Database ORM)
- Python-Jose (JWT tokens)
- Passlib (Password hashing)
- And other required packages

### Step 4: Start the FastAPI Server

```bash
python main.py
```

You should see output like:
```
✅ Database initialized successfully
🚀 Server is running at http://localhost:8000
📚 API Documentation at http://localhost:8000/docs
INFO:     Uvicorn running on http://0.0.0.0:8000
```

### Step 5: Test the API

Open your browser and visit:
- **API Docs**: http://localhost:8000/docs
- **Health Check**: http://localhost:8000/api/health

You should see the interactive Swagger UI documentation!

---

## 📱 Part 2: Configuring Flutter App

### Step 1: Find Your Computer's IP Address

You need your local IP address so your phone/emulator can connect to the FastAPI server.

**Windows:**
```bash
ipconfig
```
Look for "IPv4 Address" under your active network adapter (e.g., `192.168.1.9`)

**Mac:**
```bash
ifconfig | grep "inet "
```

**Linux:**
```bash
hostname -I
```

### Step 2: Update Flutter Environment File

Open the `.env` file in the root of your Flutter project and update it:

```env
# For Physical Device or Network Testing
API_BASE_URL=http://192.168.1.9:8000/api

# For Android Emulator
# API_BASE_URL=http://10.0.2.2:8000/api

# For iOS Simulator
# API_BASE_URL=http://localhost:8000/api
```

**Replace `192.168.1.9` with YOUR computer's IP address!**

### Step 3: Update API Config (Optional)

If you want to hardcode the URL, update `lib/config/api_config.dart`:

```dart
class ApiConfig {
  static const String baseUrl = 'http://192.168.1.9:8000/api'; // Change port to 8000
  // ... rest of the configuration
}
```

### Step 4: Run Flutter App

```bash
flutter pub get
flutter run
```

---

## 🧪 Part 3: Testing the Integration

### Test 1: Health Check

1. Open your Flutter app
2. The app should automatically check the connection
3. If successful, you'll see the login screen

### Test 2: Register a New User

1. In the Flutter app, go to the registration screen
2. Enter:
   - Email: `test@example.com`
   - Password: `test123`
   - Name: `Test User`
3. Click Register
4. You should be logged in and see a JWT token stored

### Test 3: Create a Batch

1. Navigate to the Batches page
2. Create a new batch
3. The batch should be saved to the FastAPI backend

### Test 4: Create a Session

1. Select a batch
2. Create a counting session
3. The session should be saved and visible in the History

---

## 🔧 Troubleshooting

### Problem: "Connection Refused" or "Network Error"

**Solutions:**
1. Make sure FastAPI server is running (`python main.py`)
2. Check that you're using the correct IP address
3. Ensure your phone and computer are on the same WiFi network
4. Check firewall settings - allow port 8000

**Windows Firewall:**
```bash
netsh advfirewall firewall add rule name="FastAPI" dir=in action=allow protocol=TCP localport=8000
```

### Problem: "CORS Error"

**Solution:**
The CORS middleware is already configured in `main.py`. If you still see errors, restart the FastAPI server.

### Problem: "Module Not Found" Error

**Solution:**
Make sure you're in the virtual environment and all dependencies are installed:
```bash
pip install -r requirements.txt
```

### Problem: Android Emulator Can't Connect

**Solution:**
Use the special IP address for Android emulator:
```env
API_BASE_URL=http://10.0.2.2:8000/api
```

### Problem: iOS Simulator Can't Connect

**Solution:**
Use localhost for iOS simulator:
```env
API_BASE_URL=http://localhost:8000/api
```

### Problem: Port 8000 Already in Use

**Solution:**

**Windows:**
```bash
netstat -ano | findstr :8000
taskkill /PID <PID_NUMBER> /F
```

**Mac/Linux:**
```bash
lsof -ti:8000 | xargs kill -9
```

Or change the port in `main.py`:
```python
uvicorn.run("main:app", host="0.0.0.0", port=8001, reload=True)
```

---

## 📊 Viewing the Database

The FastAPI backend uses SQLite by default. The database file is `fincount.db`.

### Option 1: DB Browser for SQLite
1. Download: https://sqlitebrowser.org/
2. Open `fincount.db`
3. View tables: users, batches, sessions

### Option 2: Command Line
```bash
sqlite3 fincount.db
.tables
SELECT * FROM users;
.exit
```

---

## 🔐 Security Considerations

### For Development:
- ✅ Current setup is fine
- ✅ CORS allows all origins
- ✅ Using SQLite database

### For Production:
- ⚠️ Change `SECRET_KEY` in `auth.py`
- ⚠️ Restrict CORS to specific origins
- ⚠️ Use PostgreSQL or MySQL instead of SQLite
- ⚠️ Enable HTTPS
- ⚠️ Add rate limiting
- ⚠️ Use environment variables for secrets
- ⚠️ Add proper logging and monitoring

---

## 📝 API Endpoints Reference

### Authentication
```
POST /api/auth/register
POST /api/auth/login
POST /api/auth/logout
```

### Batches
```
GET    /api/batches
POST   /api/batches
GET    /api/batches/{id}
PUT    /api/batches/{id}
DELETE /api/batches/{id}
```

### Sessions
```
GET    /api/sessions
POST   /api/sessions
GET    /api/sessions/batch/{batch_id}
PUT    /api/sessions/{id}
DELETE /api/sessions/{id}
```

### Health
```
GET /api/health
```

---

## 🎯 Next Steps

### Immediate:
1. ✅ Test all CRUD operations
2. ✅ Verify data persistence
3. ✅ Test authentication flow

### Short-term:
1. 🔄 Add image upload functionality
2. 🔄 Implement data sync endpoint
3. 🔄 Add user profile management
4. 🔄 Add pagination for large datasets

### Long-term:
1. 🔄 Deploy to cloud (Heroku, AWS, GCP)
2. 🔄 Set up production database
3. 🔄 Add monitoring and logging
4. 🔄 Implement backup strategy

---

## 📚 Additional Resources

- **FastAPI Documentation**: https://fastapi.tiangolo.com/
- **Flutter HTTP Package**: https://pub.dev/packages/http
- **SQLAlchemy Docs**: https://docs.sqlalchemy.org/
- **JWT.io**: https://jwt.io/

---

## 🆘 Getting Help

### Check Logs:
- **FastAPI**: Look at the terminal where you ran `python main.py`
- **Flutter**: Check the debug console in VS Code or Android Studio

### Test with cURL:
```bash
# Health check
curl http://localhost:8000/api/health

# Register
curl -X POST http://localhost:8000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"test123","name":"Test User"}'

# Login
curl -X POST http://localhost:8000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"test123"}'
```

### Interactive API Testing:
Visit http://localhost:8000/docs and test endpoints directly in the browser!

---

## ✅ Checklist

Before you start:
- [ ] Python 3.8+ installed
- [ ] Flutter SDK installed
- [ ] FastAPI dependencies installed
- [ ] Know your computer's IP address

Backend setup:
- [ ] FastAPI server running
- [ ] Can access http://localhost:8000/docs
- [ ] Health check returns "healthy"

Flutter setup:
- [ ] Updated `.env` with correct IP
- [ ] Flutter app runs without errors
- [ ] Can see login screen

Integration test:
- [ ] Successfully registered a user
- [ ] Successfully logged in
- [ ] Created a batch
- [ ] Created a session
- [ ] Data persists after app restart

---

**Congratulations! 🎉**

Your FastAPI backend is now integrated with your Flutter application. You have a fully functional REST API with authentication, database persistence, and automatic documentation!

Happy coding! 🚀
