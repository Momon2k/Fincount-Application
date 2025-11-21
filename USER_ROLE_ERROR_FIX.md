# User Role Error Fix Guide

## Error Analysis

**Error Message**: `User has no attribute role` + Foreign Key Violation

**Root Causes**:
1. User doesn't exist in backend database
2. User exists but missing required 'role' field
3. Registration failed silently

## Quick Fix Steps

### Step 1: Check Current User Status

1. **Open User_Page.dart** and check what user data is showing
2. **Log out** from the app
3. **Register a NEW account** (don't use the old one)

### Step 2: Backend User Creation Issue

The backend needs to ensure users are created with a 'role' field:

```javascript
// Backend: api/auth/register.js (or similar)
// Ensure user creation includes role field:
const newUser = await User.create({
  email: req.body.email,
  name: req.body.name,
  password: hashedPassword,
  role: 'user', // ✅ ADD THIS LINE
  createdAt: new Date(),
  updatedAt: new Date()
});
```

### Step 3: Database Migration (If Backend Already Deployed)

If you have existing users without a 'role' field, run this SQL:

```sql
-- Add role column if it doesn't exist
ALTER TABLE users 
ADD COLUMN IF NOT EXISTS role VARCHAR(50) DEFAULT 'user';

-- Update existing users with missing role
UPDATE users 
SET role = 'user' 
WHERE role IS NULL;

-- Make role NOT NULL
ALTER TABLE users 
ALTER COLUMN role SET NOT NULL;
```

---

## Detailed Troubleshooting

### Problem 1: User Not in Database

**Symptoms**:
- Foreign key constraint error
- user_id not found in users table

**Solution**:
1. Check registration flow:
   ```dart
   // In Register_Page.dart, add debug logging:
   print('Registration response: $response');
   ```

2. Verify backend creates user properly:
   ```javascript
   // Backend registration endpoint
   console.log('User created:', newUser);
   ```

### Problem 2: Missing Role Field

**Symptoms**:
- "User has no attribute role"
- AttributeError in backend

**Solution**:

Update backend registration to always set role:

```javascript
// api/auth/register.js
exports.register = async (req, res) => {
  try {
    const { email, name, password } = req.body;
    
    // Create user with role field
    const user = await User.create({
      email,
      name,
      password: await bcrypt.hash(password, 10),
      role: 'user', // ✅ REQUIRED
      createdAt: new Date(),
      updatedAt: new Date()
    });
    
    res.json({
      success: true,
      user: {
        id: user.id,
        email: user.email,
        name: user.name,
        role: user.role // ✅ Include in response
      }
    });
  } catch (error) {
    console.error('Registration error:', error);
    res.status(500).json({ error: error.message });
  }
};
```

### Problem 3: Session Creation Before User Sync

**Symptoms**:
- Local session created before user exists on backend
- Foreign key violation during sync

**Solution**:

Ensure user is synced before session creation:

```dart
// In Camera_Page.dart or wherever sessions are created:
Future<void> saveSession() async {
  try {
    // ✅ Verify user exists
    final userPrefs = await SharedPreferences.getInstance();
    final userId = userPrefs.getString('user_id');
    
    if (userId == null) {
      throw Exception('User not logged in');
    }
    
    // ✅ Check if user exists on backend before saving session
    final apiService = APIService();
    final userExists = await apiService.checkUserExists(userId);
    
    if (!userExists) {
      throw Exception('User not found on server. Please log in again.');
    }
    
    // Now safe to create session
    final session = Session(
      userId: userId,
      // ... other fields
    );
    
    await sessionService.saveSession(session);
  } catch (e) {
    print('Session save error: $e');
    // Show error to user
  }
}
```

---

## Testing Steps

### Test 1: Fresh Registration
```
1. Completely uninstall app
2. Clear app data
3. Reinstall
4. Register NEW account
5. Try creating session
```

### Test 2: Check Backend Database
```sql
-- Verify user exists with role
SELECT id, email, name, role, created_at 
FROM users 
WHERE id = 'YOUR_USER_ID';

-- Check if role column exists
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'users' AND column_name = 'role';
```

### Test 3: Backend Logs
```javascript
// Add logging in session creation endpoint:
console.log('Creating batch for user:', user_id);
console.log('User data:', user);
console.log('User role:', user.role);
```

---

## Prevention Tips

### 1. Add User Validation in App

```dart
// lib/services/auth_service.dart
Future<bool> validateUser(String userId) async {
  try {
    final response = await apiService.get('/users/$userId');
    
    if (response.data['role'] == null) {
      throw Exception('User missing role field');
    }
    
    return true;
  } catch (e) {
    print('User validation failed: $e');
    return false;
  }
}
```

### 2. Backend User Model Validation

```javascript
// models/User.js
const UserSchema = new Schema({
  email: { type: String, required: true, unique: true },
  name: { type: String, required: true },
  password: { type: String, required: true },
  role: { 
    type: String, 
    required: true,  // ✅ Make required
    default: 'user'  // ✅ Set default
  },
  createdAt: { type: Date, default: Date.now },
  updatedAt: Date
});
```

### 3. Frontend Registration Validation

```dart
// After successful registration:
final user = User.fromJson(response.data['user']);

if (user.role == null) {
  throw Exception('Registration incomplete - missing role');
}

// Save user to SharedPreferences
await prefs.setString('user_id', user.id);
await prefs.setString('user_role', user.role!);
```

---

## Emergency Fix (If Nothing Works)

If you're stuck and need immediate fix:

### Option A: Reset Database
```sql
-- ⚠️ WARNING: This deletes all data!
DROP TABLE IF EXISTS batches CASCADE;
DROP TABLE IF EXISTS sessions CASCADE;
DROP TABLE IF EXISTS users CASCADE;

-- Recreate tables with proper schema
-- (Use your migration files)
```

### Option B: Manual User Fix
```sql
-- Add role to specific user
UPDATE users 
SET role = 'user' 
WHERE id = 'fa1c3896-50a9-41b8-a573-a4c9dc1266bf';
```

### Option C: Clear App and Re-register
1. Uninstall app completely
2. Clear backend database (if test environment)
3. Reinstall app
4. Register new account
5. Test session creation

---

## Summary

**The core issue**: Backend expects users to have a 'role' field, but your user record is missing it.

**Quick fixes**:
1. ✅ Add 'role' field to backend user creation
2. ✅ Update existing users with default role
3. ✅ Re-register with new account

**Best practice**: Always validate user data includes all required fields before saving sessions.

Need help with any specific step? Let me know! 🚀
