# Type Casting Fix - Dispatch Jobs

## Problem
The app was throwing this error:
```
type '_Map<dynamic, dynamic>' is not a subtype of type 'Map<String, dynamic>'
```

This happened when loading dispatch jobs for riders because Supabase returns `_Map<dynamic, dynamic>` but the code expected `Map<String, dynamic>`.

## Root Causes

### 1. Supabase Response Type Mismatch
**Location**: `lib/services/rider_service.dart`
- Supabase queries return `_Map<dynamic, dynamic>` 
- Code was trying to directly cast to `Map<String, dynamic>`
- This fails at runtime

### 2. Hive Cache Type Mismatch  
**Location**: `lib/services/cache/job_cache_service.dart`
- Cached data also contained `Map<dynamic, dynamic>`
- When reading from cache, same type error occurred
- Old cached data persisted even after fixing Supabase calls

## Solutions Implemented

### Fix 1: Type Conversion in rider_service.dart ✅
**Changed from:**
```dart
final jobs = (response as List)
    .map((json) => DispatchJob.fromJson(json as Map<String, dynamic>))
    .toList();
```

**Changed to:**
```dart
final jobs = (response as List)
    .map((json) => DispatchJob.fromJson(Map<String, dynamic>.from(json as Map)))
    .toList();
```

This uses `Map<String, dynamic>.from()` to properly convert the map type.

### Fix 2: Type Conversion in job_cache_service.dart ✅
**Changed from:**
```dart
final jobsList = List<Map<String, dynamic>>.from(cachedData['jobs']);
final jobs = jobsList.map((json) => DispatchJob.fromJson(json)).toList();
```

**Changed to:**
```dart
final jobsList = (cachedData['jobs'] as List).map((item) {
  return Map<String, dynamic>.from(item as Map);
}).toList();

final jobs = jobsList.map((json) => DispatchJob.fromJson(json)).toList();
```

Added try-catch to clear corrupted cache if parsing fails.

### Fix 3: Cache Versioning System ✅
**Added cache version tracking:**
- `_cacheVersion = 2` - Incremented version number
- Auto-clears old incompatible caches on app start
- Prevents old cached data from causing issues
- Future-proof for data structure changes

**New features:**
```dart
static const int _cacheVersion = 2;

static Future<void> _checkAndClearOldCache() async {
  final storedVersion = _box!.get('cache_version');
  
  if (storedVersion == null || storedVersion != _cacheVersion) {
    await _box!.clear();
    await _box!.put('cache_version', _cacheVersion);
  }
}
```

## Files Modified

1. ✅ `lib/services/rider_service.dart`
   - Fixed all `DispatchJob.fromJson()` calls (5 locations)
   - Used `Map<String, dynamic>.from(json as Map)`

2. ✅ `lib/services/cache/job_cache_service.dart`  
   - Fixed `getCachedJobs()` method
   - Added cache versioning system
   - Added try-catch for corrupted cache
   - Auto-clears incompatible cache versions

## Testing Checklist

- [ ] App launches without errors
- [ ] Rider can see dispatch jobs on home screen
- [ ] Jobs list shows customer names
- [ ] Route screen displays customer names
- [ ] No type casting errors in console
- [ ] Cache works properly after restart

## Next Steps

1. **Run the app** - Should now load without type errors
2. **Verify cache cleared** - Look for log: "Cache cleared and updated to v2"
3. **Create test order** - Ensure new dispatch jobs appear
4. **Check customer names** - Verify names display in rider app

## Prevention

To prevent similar issues in the future:

1. **Always use type conversion** when parsing from Supabase:
   ```dart
   Map<String, dynamic>.from(json as Map)
   ```

2. **Use cache versioning** when changing data structures

3. **Add try-catch** around parsing code to handle corrupted data gracefully
