# Sync Message Persistence Fix

## Problem
The "Session saved locally. Will sync when online" message would persist even after reconnecting to the internet and auto-sync completing successfully.

## Root Causes Identified

1. **SnackBar Not Being Cleared**: When showing new sync notifications, the old SnackBar was not being dismissed, causing it to remain visible alongside or instead of the new notification.

2. **Missing Manual Sync Trigger**: While auto-sync worked on connectivity changes, there was no sync check when navigating to the Dashboard, meaning unsynced data could remain until the next connectivity change.

3. **SnackBars Persisting After Logout**: SnackBars were not being cleared when logging out, causing old "offline" messages to appear on the Login page after logout.

## Solutions Implemented

### 1. Clear Existing SnackBars Before Showing New Ones
**File**: `lib/Camera_Page.dart`

Added `clearSnackBars()` before showing any session save notifications:

```dart
ScaffoldMessenger.of(context)
  ..clearSnackBars() // Clear any existing snackbars
  ..showSnackBar(/* new snackbar */);
```

This ensures that:
- Old "offline" messages are dismissed before showing "synced" messages
- No conflicting messages appear simultaneously
- Users always see the most current status

### 2. Added Manual Sync Check Method
**File**: `lib/services/connectivity_service.dart`

Added `checkAndSync()` method that can be called to manually trigger a sync check:

```dart
Future<void> checkAndSync() async {
  final isOnline = await this.isOnline();
  
  if (isOnline) {
    print('Manual sync check - device is online, triggering sync...');
    await _performAutoSync();
  } else {
    print('Manual sync check - device is offline, skipping sync');
  }
}
```

### 3. Dashboard Auto-Sync on Load
**File**: `lib/Dashboard_Page.dart`

Added automatic sync check when Dashboard loads:

```dart
@override
void initState() {
  super.initState();
  _selectedIndex = widget.initialIndex;
  _loadStatistics();
  _checkAndSyncPendingData(); // NEW: Check for pending data
}

void _checkAndSyncPendingData() async {
  try {
    final connectivityService = ConnectivityService();
    if (connectivityService.isInitialized) {
      await connectivityService.checkAndSync();
    }
  } catch (e) {
    print('Error checking sync status: $e');
  }
}
```

This ensures that:
- When users navigate to Dashboard while online, any pending offline data syncs immediately
- Users don't have to wait for a connectivity change to trigger sync
- Provides immediate feedback when opening the app after being offline

### 4. Clear SnackBars on Logout
**Files**: `lib/User_Page.dart`, `lib/Camera_Page.dart`

Added `clearSnackBars()` before logging out:

```dart
// In User_Page.dart logout handler
TextButton(
  onPressed: () async {
    Navigator.of(context).pop();
    
    // Clear any persistent SnackBars
    ScaffoldMessenger.of(context).clearSnackBars();
    
    // Clear user-specific storage
    await UserSessionManager.clearUserSession();
    // ... rest of logout logic
  },
  // ...
)
```

Similarly in `Camera_Page.dart` re-login prompt:

```dart
// Clear any persistent SnackBars
if (mounted) {
  ScaffoldMessenger.of(context).clearSnackBars();
}
```

This ensures that:
- No old sync messages appear on the Login page after logout
- Clean slate for new login session
- Better user experience without confusing leftover messages

## How It Works Now

### Scenario 1: Save Session While Offline
1. User saves a session without internet
2. Shows: "Session saved locally. Will sync when online" (orange SnackBar)
3. User navigates to Dashboard
4. Dashboard checks for pending data and attempts sync

### Scenario 2: Reconnect to Internet
1. ConnectivityService detects offline → online transition
2. Auto-sync triggers (checks for unsynced sessions)
3. If unsynced data exists, syncs it to API
4. **Old SnackBar is cleared**
5. Shows: "Synced X session(s) successfully" (green SnackBar)

### Scenario 3: Open Dashboard While Online
1. User opens Dashboard
2. Dashboard calls `checkAndSync()`
3. If pending offline data exists, syncs immediately
4. Shows sync completion notification
5. Old offline messages are cleared

### Scenario 4: Logout After Offline Session
1. User saves session while offline (sees "Will sync when online" message)
2. User logs out from Profile page
3. **Old SnackBar is cleared automatically**
4. Login page appears without any persistent messages
5. Clean state for next user

## Benefits

✅ **No More Persistent Messages**: Old "offline" messages are always cleared before showing new status

✅ **Immediate Sync on Dashboard Load**: Users don't have to wait for connectivity changes

✅ **Clear User Feedback**: Users always see the current sync status without confusion

✅ **Automatic Background Sync**: Works seamlessly without user intervention

✅ **Clean Logout**: No persistent messages after logout

## Testing Checklist

- [ ] Save session while offline → See "Will sync when online" message
- [ ] Reconnect to internet → Old message clears, new "Synced successfully" appears
- [ ] Navigate to Dashboard while online with pending data → Auto-sync triggers
- [ ] Save session while online → See immediate "synced to cloud" message
- [ ] Open app after being offline → Pending data syncs when Dashboard loads
- [ ] **Save session offline then logout → No message persists on Login page**
- [ ] **Logout from any page → All SnackBars are cleared**

## Technical Notes

- ConnectivityService is initialized after login in `Login_Page.dart`
- ConnectivityService is also initialized on app start if user has stored session in `main.dart`
- Sync notifications use the global `navigatorKey` for showing SnackBars from service layer
- All SnackBars use `clearSnackBars()` to prevent message overlap
