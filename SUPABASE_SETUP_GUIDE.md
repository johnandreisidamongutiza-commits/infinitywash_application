# Supabase Setup and Authentication Test

This Flutter app is currently connected to Supabase Authentication for the role-based login screens. The app does not read or write application tables yet. The startup screen is `RoleSelectionScreen`, where you can choose Customer, Staff, or Rider and then test an existing Supabase Auth account.

## 1. Get the project credentials

1. Open your Supabase project at [supabase.com/dashboard](https://supabase.com/dashboard).
2. Go to **Project Settings** -> **API**.
3. Copy the **Project URL**.
4. Copy the client-safe **Publishable key** or legacy **anon public key**.

Never use or put the `service_role` key in this Flutter app. A mobile app cannot keep a secret key private.

## 2. Add the credentials to this app

Open:

```text
lib/config/supabase_config.dart
```

Replace both placeholders with values from your Supabase project:

```dart
class SupabaseConfig {
   static const String supabaseUrl = 'https://your-project-id.supabase.co';
   static const String supabaseAnonKey = 'your-publishable-or-anon-key';
}
```

Do not add quotation marks inside the values and do not add spaces or line breaks. Keep this file out of public repositories if it contains project-specific configuration. The publishable/anon key is designed for client apps, but database access still depends on Row Level Security policies.

## 3. Check Supabase Authentication settings

In the Supabase dashboard:

1. Open **Authentication** -> **Providers**.
2. Make sure the **Email** provider is enabled.
3. Check whether **Confirm email** is enabled.

If confirmation is enabled, an account must verify its email before password login succeeds. For local testing only, you can disable confirmation temporarily or confirm the user manually from **Authentication** -> **Users**. Re-enable confirmation before using the app outside development.

## 4. Enable automatic customer profile creation

Run the complete SQL in [supabase_profiles_trigger.sql](supabase_profiles_trigger.sql) once in **Supabase Dashboard** -> **SQL Editor**.

This trigger runs when the Customer registration creates a new Auth user. It automatically creates the matching `profiles` row with:

- `id` and `supabase_user_id` linked to the Auth user ID;
- first name, last name, email, phone, address, and landmark;
- `role = customer`;
- `status = active`.

The app sends the phone number directly to Supabase Auth, and the trigger copies
that value into `profiles.phone`. The trigger only runs for registrations with
`role = customer`, so it does not change existing Staff, Rider, Admin, or
SuperAdmin profiles.

This step is required when email confirmation is enabled because the app does not receive an authenticated session until the email is confirmed. The database trigger creates the profile immediately instead of waiting for the first login.

## 5. Run the app

From the project folder, run:

```bash
flutter pub get
flutter run
```

`lib/main.dart` initializes Supabase and opens the role selection screen automatically.

## 6. Test an existing Auth user on each role

Because you already have users in Supabase:

1. Start the app.
2. Select **Customer** or select **Team Member**, then choose **Staff** or **Rider**.
3. Enter the email address and password for an existing user in **Authentication** -> **Users**.
4. Tap **Sign In**.
5. Repeat with the other roles if needed.

After a successful login, the app opens the selected role's dashboard. Before navigation, the app checks the user's row in `profiles`:

- `profiles.supabase_user_id` must match the authenticated Supabase user ID;
- `profiles.role` must match the selected role (`customer`, `staff`, or `rider`);
- `profiles.status` must be `active`.

If the profile is missing, inactive, or assigned to another role, the app signs out and refuses dashboard access. The Supabase session is shared by all roles.

The authenticated client must be allowed to read its own profile row. Enable Row Level Security on `profiles` and add a policy equivalent to:

```sql
alter table profiles enable row level security;

create policy "Users can read their own profile"
on profiles for select
to authenticated
using (supabase_user_id = auth.uid());
```

Staff and Rider login also reads the linked `employees` row. Enable Row Level
Security on `employees` and allow each authenticated employee to read the row
linked to their own profile:

```sql
alter table employees enable row level security;

create policy "Employees can read their own employee record"
on employees for select
to authenticated
using (
   exists (
      select 1
      from profiles
      where profiles.id = employees.profile_id
         and profiles.supabase_user_id = auth.uid()
   )
);
```

The authenticated user is available through `Supabase.instance.client.auth.currentUser`, including:

- the user email;
- the Supabase user ID;
- the account creation time;

Sign-out controls are available from the relevant dashboard screens. Sign out, then log in again to verify the session transition.

## 7. Test creating a new user (optional)

Tap **Don't have an account? Sign Up**, enter a new email and a password with at least six characters, then tap **Sign Up**.

If email confirmation is enabled, check the inbox and confirm the address before trying **Login**. If the email already exists, use the existing account in **Login** mode instead.

## 8. What this test does not cover yet

This test currently verifies only:

- Supabase initialization;
- email/password sign-up;
- email/password login;
- the current authenticated user;
- sign-out and auth-state changes.

It does not yet load customer, staff, rider, order, supply, or chat data from Supabase tables. Those features require tables, Row Level Security policies, and Flutter service methods to be connected to the relevant screens.

## Troubleshooting

### `Invalid API key` or initialization failure

- Confirm that the URL is the Project URL, not the dashboard URL.
- Confirm that the key is the publishable/anon key, not `service_role`.
- Check for extra spaces or missing characters in `lib/config/supabase_config.dart`.
- Confirm that the Supabase project is active and the device has internet access.

### `Invalid login credentials`

- Confirm the email and password match an existing user.
- Make sure you are testing against the same Supabase project whose credentials are in the app.
- If the account requires email confirmation, confirm it first.

### `Email not confirmed`

Confirm the user from the email link or from the Supabase dashboard. For development only, you can disable **Confirm email** in the Email provider settings.

### The app shows no user after login

Check the Flutter console for the exact error, then verify that `SupabaseConfig` contains values from the intended project. Also confirm that the authenticated user's `profiles` row has the correct `supabase_user_id`, lowercase `role`, and `active` status.

### A previous Auth user has no profile

The trigger only runs for newly created Auth users. Existing users created before
the trigger need a profile row added manually or through a one-time SQL backfill.

## Current app flow

The app already starts with:

```dart
home: const RoleSelectionScreen(),
```

Keep Supabase initialization in `main.dart` so every role login screen and dashboard can use `Supabase.instance.client`.

## Useful references

- [Supabase Flutter documentation](https://supabase.com/docs/reference/dart/introduction)
- [Supabase Auth documentation](https://supabase.com/docs/guides/auth)
- [Supabase Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security)
