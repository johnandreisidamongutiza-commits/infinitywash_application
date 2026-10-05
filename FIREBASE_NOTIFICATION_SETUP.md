# Firebase Notification System Setup

## Push Notifications (FCM) — ACTIVE

The app sends real push notifications via Firebase Cloud Messaging. This is the
primary notification path; the Firestore announcement system below is a
separate, in-app-only feed.

### Architecture

```
DB event (order status / new job / new request)
  → Postgres trigger (pg_net, async)
    → send-push-notification Edge Function
      → FCM HTTP v1 API
        → device tray (foreground: in-app banner via PushNotificationService)
```

**Files:**
- Client: `lib/services/push_notification_service.dart` (permission, token
  registration into `fcm_tokens`, foreground banner, tap deep-link)
- Server: `supabase/functions/send-push-notification/index.ts` (FCM HTTP v1,
  service-account OAuth2, batching, auto-prune of dead tokens)
- Triggers: `supabase/migrations/20261006_push_auto_notify.sql` (+ rollback)
- Tokens table: `supabase/migrations/20261002_fcm_push_tokens.sql`

### What triggers a push

| Event | Audience | Message |
|---|---|---|
| Order status → `ready` | that customer | "Order ready! 🧺" |
| Order status → `out_for_delivery` | that customer | "On the way 🛵" |
| Order status → `completed` | that customer | "Completed ✅" |
| Order status → `rejected` | that customer | "Request declined" |
| `dispatch_jobs` INSERT | all active riders | "New job available! 📦" |
| `orders` INSERT (`mobile_app`, `pending_approval`) | all staff | "New service request 📋" |

### Deployment checklist (one-time)

1. **Apply the token table migration** (verify with
   `select count(*) from public.fcm_tokens;` — error means not applied):
   run `supabase/migrations/20261002_fcm_push_tokens.sql` in the SQL Editor.

2. **Apply the trigger migration:** run
   `supabase/migrations/20261006_push_auto_notify.sql` in the SQL Editor.

3. **Deploy the Edge Function** (CLI: `supabase functions deploy
   send-push-notification`, or paste the file into the dashboard's
   Edge Functions editor).

4. **Set the two Vault secrets** (SQL Editor — the triggers read these;
   without them pushes are silent no-ops):
   ```sql
   select vault.create_secret(
     'https://<PROJECT-REF>.supabase.co/functions/v1/send-push-notification',
     'push_function_url');

   select vault.create_secret(
     '<service_role key from Project Settings → API>',
     'push_service_role_key');
   ```

5. **Set the Firebase secret for the Edge Function** (CLI:
   `supabase secrets set FIREBASE_SERVICE_ACCOUNT_JSON='<json>'`; dashboard:
   Edge Functions → send-push-notification → Secrets). Create the key in
   Firebase Console → Project Settings → Service Accounts → Generate new
   private key.

6. **Test end to end:**
   - Sign in on a real device and accept the notification permission —
     verify a row appears: `select user_id, platform, updated_at from
     fcm_tokens order by updated_at desc limit 5;`
   - Change an order's status in SQL (`update orders set status='ready'
     where id='<id>';`) or through the staff app → tray notification
     should arrive within a few seconds.
   - Check Edge Function logs (dashboard → Edge Functions → Logs) if not.

### Manual push (any audience, anytime)

```bash
curl -X POST 'https://<PROJECT-REF>.supabase.co/functions/v1/send-push-notification' \
  -H "Authorization: Bearer <service_role key>" \
  -H 'Content-Type: application/json' \
  -d '{"title":"Announcement","body":"Shop closed tomorrow","audience":"all"}'
```

---

## Overview

This document explains the Firebase-based notification system for Infinity Wash. Notifications are created from your admin website and delivered in real-time to the Flutter app.

## Architecture

```
Admin Website → Firebase Firestore → Flutter App (Real-time listeners)
```

- **Permanent Storage**: Supabase (for audit logs, user profiles)
- **Live Notifications**: Firebase Firestore (with TTL/cleanup)
- **Authentication**: Supabase Auth (primary identity)

## Firestore Collections

### 1. `notifications` Collection

This is where your admin website writes announcement/notification documents.

**Document Structure:**
```javascript
{
  "id": "auto-generated-doc-id",
  "title": "New Promotion!",
  "message": "Get 20% off on all laundry services this week!",
  "type": "announcement", // announcement, order_update, payment, delivery, alert
  "audience_roles": ["customer", "staff", "rider"], // Array of target roles
  "created_by": "admin_user_id",
  "created_at": Timestamp,
  "published_at": Timestamp,
  "expires_at": Timestamp (optional),
  "status": "published", // draft, published, archived
  "related_order_id": "order-123" (optional),
  "announcement_id": "announcement-456" (optional)
}
```

**Indexes Required:**
```
Collection: notifications
Fields:
- audience_roles (Array), status (Ascending), created_at (Descending)
```

### 2. `notification_reads` Collection

Tracks which users have read which notifications.

**Document ID Format:** `{user_id}_{notification_id}`

**Document Structure:**
```javascript
{
  "user_id": "supabase-user-id",
  "notification_id": "notification-doc-id",
  "read_at": Timestamp
}
```

## Firebase Setup Steps

### 1. Deploy Firestore Security Rules

```bash
cd /path/to/infinitywash_application
firebase deploy --only firestore:rules
```

### 2. Create Firestore Indexes

Go to Firebase Console → Firestore → Indexes → Create Index:

**Index 1:**
- Collection: `notifications`
- Fields:
  - `audience_roles` (Array)
  - `status` (Ascending)
  - `created_at` (Descending)

### 3. Set Up Custom Claims (Optional but Recommended)

To enable Firestore security rules to check user roles, you need to set custom claims on Firebase Auth users.

**Option A: Via Backend (Recommended)**

When a user logs in via Supabase, create a corresponding Firebase custom token with role claim:

```javascript
// In your admin website backend
const admin = require('firebase-admin');

// After Supabase authentication
const customToken = await admin.auth().createCustomToken(supabaseUserId, {
  role: userRole, // 'customer', 'staff', or 'rider'
  supabaseId: supabaseUserId
});

// Send customToken to client
// Client uses it to sign in to Firebase
```

**Option B: Simpler Approach (Current Implementation)**

The current Flutter implementation doesn't require Firebase custom claims because:
- Users authenticate with Supabase (not Firebase Auth)
- Notifications are filtered by role in the Notification Service
- Read states use Supabase user IDs

However, Firestore rules currently reference `request.auth.token.role`, which won't work without custom claims.

**Recommended Fix**: Update firestore.rules to allow reads based on document data only:

```javascript
match /notifications/{notificationId} {
  allow read: if isAuthenticated() 
              && resource.data.status == 'published';
}
```

Then filter by role in the app (already implemented in NotificationService).

## Admin Website Integration

### Creating Notifications from Your Website

**Basic Notification:**
```javascript
await db.collection('notifications').add({
  title: 'System Maintenance',
  message: 'The system will be down for maintenance on Sunday.',
  type: 'announcement',
  audience_roles: ['customer', 'staff', 'rider'], // All users
  created_by: currentAdminUserId,
  created_at: firebase.firestore.FieldValue.serverTimestamp(),
  published_at: firebase.firestore.FieldValue.serverTimestamp(),
  status: 'published'
});
```

**Order Update Notification:**
```javascript
await db.collection('notifications').add({
  title: 'Order Ready for Pickup',
  message: `Order #${orderId} is ready for pickup!`,
  type: 'order_update',
  audience_roles: ['customer'],
  related_order_id: orderId,
  created_by: 'system',
  created_at: firebase.firestore.FieldValue.serverTimestamp(),
  published_at: firebase.firestore.FieldValue.serverTimestamp(),
  status: 'published'
});
```

**Targeted Announcement:**
```javascript
await db.collection('notifications').add({
  title: 'Staff Training Session',
  message: 'Mandatory training session on Saturday at 9 AM.',
  type: 'announcement',
  audience_roles: ['staff'], // Only staff
  created_by: currentAdminUserId,
  created_at: firebase.firestore.FieldValue.serverTimestamp(),
  published_at: firebase.firestore.FieldValue.serverTimestamp(),
  expires_at: firebase.firestore.Timestamp.fromDate(expiryDate),
  status: 'published'
});
```

## Flutter App Implementation

The Flutter app automatically:

1. ✅ Fetches notifications on screen load
2. ✅ Filters by user role (customer/staff/rider)
3. ✅ Shows only published notifications
4. ✅ Excludes expired notifications
5. ✅ Tracks read/unread state per user
6. ✅ Displays unread badge count
7. ✅ Supports pull-to-refresh
8. ✅ Marks notifications as read on tap
9. ✅ Supports "Mark All as Read"

## Testing

### 1. Create a Test Notification

From Firebase Console or your admin website:

```javascript
db.collection('notifications').add({
  title: 'Test Notification',
  message: 'This is a test message to verify the notification system.',
  type: 'announcement',
  audience_roles: ['customer', 'staff', 'rider'],
  created_by: 'admin',
  created_at: firebase.firestore.FieldValue.serverTimestamp(),
  published_at: firebase.firestore.FieldValue.serverTimestamp(),
  status: 'published'
});
```

### 2. Verify in App

1. Open the Flutter app
2. Log in as a customer, staff, or rider
3. Navigate to Notifications screen
4. You should see the test notification
5. Tap it to mark as read

## Notification Types

| Type | Icon | Use Case |
|------|------|----------|
| `announcement` | Campaign | General announcements, promotions |
| `order_update` | Shopping Bag | Order status changes |
| `delivery` | Delivery Dining | Delivery assignments, updates |
| `payment` | Payments | Payment confirmations |
| `alert` | Warning | Important alerts, low stock |
| `completed` | Check Circle | Order completed confirmations |

## Cleanup Strategy

### Automatic Expiration

Set `expires_at` field on notifications:

```javascript
expires_at: firebase.firestore.Timestamp.fromDate(
  new Date(Date.now() + 7 * 24 * 60 * 60 * 1000) // 7 days
)
```

Expired notifications are automatically filtered out in the app.

### Manual Cleanup (Recommended)

Create a Cloud Function to delete old notifications:

```javascript
exports.cleanupOldNotifications = functions.pubsub
  .schedule('every 24 hours')
  .onRun(async (context) => {
    const cutoff = admin.firestore.Timestamp.fromDate(
      new Date(Date.now() - 30 * 24 * 60 * 60 * 1000) // 30 days
    );
    
    const snapshot = await admin.firestore()
      .collection('notifications')
      .where('created_at', '<', cutoff)
      .get();
    
    const batch = admin.firestore().batch();
    snapshot.docs.forEach(doc => batch.delete(doc.ref));
    await batch.commit();
  });
```

## Troubleshooting

### Notifications Not Appearing

1. **Check Firebase Console**: Verify notifications exist in Firestore
2. **Check Status**: Ensure `status` is `'published'`
3. **Check Role**: Verify `audience_roles` includes user's role
4. **Check Expiration**: Ensure notification hasn't expired
5. **Check Logs**: Look for errors in Flutter console

### Permission Denied Errors

1. **Verify Firestore Rules**: Check rules are deployed
2. **Check Authentication**: User must be logged in via Supabase
3. **Update Rules**: Use the simplified rules mentioned above

### Read State Not Persisting

1. **Check User ID**: Ensure Supabase user ID is correct
2. **Check Firestore**: Verify `notification_reads` documents are created
3. **Check Permissions**: Ensure create permission is granted

## Future Enhancements

- [ ] Real-time listeners (replace periodic fetches with StreamBuilder)
- [ ] Push notifications (FCM integration)
- [ ] In-app notification bell with badge
- [ ] Notification preferences (mute certain types)
- [ ] Rich notifications (images, actions)
- [ ] Scheduled notifications

## Support

For issues or questions, contact the development team.
