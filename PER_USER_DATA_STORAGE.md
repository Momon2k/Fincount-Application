# Per-User Data Storage Implementation

## Overview

This document explains the implementation of per-user data storage in the Fincount Application. Each user now has their own isolated data storage, ensuring that users only see their own fingerling counts and session history.

## Problem Solved

**Before**: All users shared the same data storage. When a new user registered, they could see the old user's fingerling counts because the app was saving data in one global location.

**After**: Each user has their own private data storage. When users log in, they only see their own data. New users start with an empty box (0 fingerlings).

## Architecture

### Storage Structure

```
Hive Boxes (Local Database):
   sessions_user123/          ← User 1's data
      SessionModel objects
   sessions_user456/          ← User 2's data
      SessionModel objects
   sessions_user789/          ← User 3's data
      SessionModel objects

SharedPreferences Keys:
   sessions_user123          ← User 1's session list
   batches_user123           ← User 1's batch info
   synced_sessions_user123   ← User 1's sync status
   
   sessions_user456          ← User 2's session list
   batches_user456           ← User 2's batch info
   synced_sessions_user456   ← User 2's sync status
```

## Key Components

### 1. UserSessionManager Service (`lib/services/user_session_manager.dart`)

Central service that manages user-specific storage:

- **`initializeUserSession(userId)`** - Opens user-specific Hive box when user logs in
- **`clearUserSession()`** - Closes user box when user logs out
- **`getCurrentUserBox()`** - Returns the current user's Hive box
- **`getUserKey(baseKey)`** - Generates user-specific keys for SharedPreferences
- **`initializeFromStoredSession()`** - Restores user session on app restart

### 2. Updated Services

#### SessionService
- Uses `UserSessionManager.getUserKey()` for all SharedPreferences operations
- Storage keys are now user-specific: `sessions_${userId}`, `batches_${userId}`

#### HybridSessionService
- Sync tracking is now per-user
- Each user has their own sync status: `synced_sessions_${userId}`

### 3. Updated UI Components

All pages that display or save session data now use user-specific storage:

- **Dashboard_Page** - `UserSessionManager.getCurrentUserBox()`
- **History_Page** - `UserSessionManager.getCurrentUserBox()`
- **Batches_Page** - `UserSessionManager.getCurrentUserBox()`
- **Camera_Page** - `UserSessionManager.getCurrentUserBox()`

## User Flow

### Login Flow
1. User enters credentials
2. API authenticates and returns `user_id`
3. `AuthService.saveUserData()` saves user info to SharedPreferences
4. **`UserSessionManager.initializeUserSession(userId)`** opens user's Hive box
5. User navigates to Dashboard with their own data

### Registration Flow
1. User completes registration form
2. API creates account and returns `user_id`
3. `AuthService.saveUserData()` saves user info
4. **`UserSessionManager.initializeUserSession(userId)`** creates new empty Hive box
5. New user starts with 0 fingerlings

### Logout Flow
1. User clicks logout button
2. **`UserSessionManager.clearUserSession()`** closes current user's Hive box
3. `AuthService.clearToken()` clears auth token and user data
4. User navigates back to login screen

### App Restart Flow
1. App starts
2. **`UserSessionManager.initializeFromStoredSession()`** checks for stored `user_id`
3. If found, opens that user's Hive box
4. If token is valid, user goes directly to Dashboard
5. If not found, user goes to Login screen

## Code Examples

### Saving Data (Before vs After)

**Before (Global Storage):**
```dart
final sessionsBox = Hive.box<SessionModel>('sessions'); // ❌ Global box
await sessionsBox.add(sessionModel);
```

**After (User-Specific Storage):**
```dart
final sessionsBox = UserSessionManager.getCurrentUserBox(); // ✅ User's box
await sessionsBox.add(sessionModel);
```

### Reading Data (Before vs After)

**Before (Global Storage):**
```dart
valueListenable: Hive.box<SessionModel>('sessions').listenable(), // ❌ Everyone sees same data
```

**After (User-Specific Storage):**
```dart
valueListenable: UserSessionManager.getCurrentUserBox().listenable(), // ✅ Each user sees only their data
```

### SharedPreferences Keys (Before vs After)

**Before (Global Keys):**
```dart
prefs.setStringList('sessions', sessions);  // ❌ Shared by all users
prefs.setString('batches', batches);        // ❌ Shared by all users
```

**After (User-Specific Keys):**
```dart
final key = UserSessionManager.getUserKey('sessions');  // 'sessions_user123'
prefs.setStringList(key, sessions);  // ✅ User-specific

final key2 = UserSessionManager.getUserKey('batches');  // 'batches_user123'
prefs.setString(key2, batches);      // ✅ User-specific
```

## Data Isolation Benefits

✅ **Privacy** - Users cannot see other users' data
✅ **Accuracy** - Each user's statistics are correct and isolated
✅ **Clean State** - New users start with empty data
✅ **No Conflicts** - Multiple users can use the app without data mixing
✅ **Offline Support** - Each user's data is cached locally per user

## Testing Checklist

To verify per-user data storage is working:

1. **Register User A**
   - Should see 0 fingerlings
   - Create some sessions
   - Note the count

2. **Logout and Register User B**
   - Should see 0 fingerlings (not User A's count)
   - Create different sessions
   - Note the count

3. **Logout and Login as User A**
   - Should see User A's original fingerling count
   - Should NOT see User B's data

4. **Logout and Login as User B**
   - Should see User B's fingerling count
   - Should NOT see User A's data

5. **App Restart Test**
   - Close and restart the app
   - Should automatically log in as last user
   - Should see that user's data only

## Technical Notes

- The `user_id` from the API is used as the storage identifier
- User IDs are stored in SharedPreferences as `'user_id'`
- Hive box names follow the pattern: `sessions_${userId}`
- SharedPreferences keys follow the pattern: `${baseKey}_${userId}`
- The implementation is backward compatible - old data is not automatically migrated

## Files Modified

1. `lib/services/user_session_manager.dart` - **NEW** Central user session management
2. `lib/services/session_service.dart` - User-specific keys
3. `lib/services/hybrid_session_service.dart` - User-specific sync tracking
4. `lib/Dashboard_Page.dart` - User-specific Hive box
5. `lib/History_Page.dart` - User-specific Hive box
6. `lib/Batches_Page.dart` - User-specific Hive box
7. `lib/Camera_Page.dart` - User-specific Hive box
8. `lib/Login_Page.dart` - Initialize user session on login
9. `lib/Register_Page.dart` - Initialize user session on registration
10. `lib/User_Page.dart` - Clear user session on logout
11. `lib/main.dart` - Restore user session on app start

## Troubleshooting

**Issue**: User sees another user's data
- **Check**: Ensure `UserSessionManager.initializeUserSession()` is called after login
- **Check**: Verify `user_id` is being saved correctly

**Issue**: User data disappears after logout
- **Expected**: This is correct behavior. Data is stored locally per device.
- **Solution**: For cloud persistence, ensure API sync is working

**Issue**: New user sees old data
- **Check**: Ensure `UserSessionManager.clearUserSession()` is called on logout
- **Check**: Verify new `user_id` is different from previous user

## Future Enhancements

- Data migration tool for existing users
- Admin panel to view all users' storage
- Backup/restore functionality per user
- Cloud sync status indicator per user
