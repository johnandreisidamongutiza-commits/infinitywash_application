# Implementation Plan - Infinity Wash Login Flow

Create a complete front-end login flow for the Infinity Wash app, featuring three roles (Customer, Staff, Rider) distributed across two main account types.

## User Review Required

> [!IMPORTANT]
> The design uses a specific mascot and logo. I will use placeholders for these images. You will need to add your actual image assets to the `assets/` folder and update the `pubspec.yaml` accordingly.

> [!NOTE]
> I will implement the navigation and UI logic (state for role selection), but the "Sign In" button will only print to the console for now as backend integration is not requested.

## Proposed Changes

### Core Configuration

#### [MODIFY] [pubspec.yaml](file:///C:/Users/johna/infinitywash/pubspec.yaml)
- Add `google_fonts` for typography (optional, but recommended for the clean look).
- Register the `assets/` folder.

#### [NEW] [app_theme.dart](file:///C:/Users/johna/infinitywash/lib/theme/app_theme.dart)
- Define the color palette (Infinity Blue, Soft Gray, etc.).
- Configure `ThemeData` with custom button and text styles.

---

### UI Components

#### [NEW] [role_card.dart](file:///C:/Users/johna/infinitywash/lib/widgets/role_card.dart)
- Reusable card component for "Customer", "Team Member", "Staff", and "Rider" selections.

#### [NEW] [custom_text_field.dart](file:///C:/Users/johna/infinitywash/lib/widgets/custom_text_field.dart)
- Styled input fields for Email and Password as seen in the third design.

---

### Screens

#### [NEW] [role_selection_screen.dart](file:///C:/Users/johna/infinitywash/lib/screens/role_selection_screen.dart)
- **Image 1:** Initial choice between "Customer" and "Team Member".

#### [NEW] [team_member_selection_screen.dart](file:///C:/Users/johna/infinitywash/lib/screens/team_member_selection_screen.dart)
- **Image 2:** Secondary choice for "Staff" or "Rider" with a "Continue" button.

#### [NEW] [login_screen.dart](file:///C:/Users/johna/infinitywash/lib/screens/login_screen.dart)
- **Image 3:** Final login form. The UI will adapt its title based on the selected role (e.g., "Staff Login").

---

### Main Integration

#### [MODIFY] [main.dart](file:///C:/Users/johna/infinitywash/lib/main.dart)
- Replace boilerplate with the `MaterialApp` pointing to `RoleSelectionScreen`.

## Verification Plan

### Automated Tests
- I will verify the screen transitions using `flutter test` (if requested later).

### Manual Verification
1. Open the app -> Verify **Role Selection** screen matches Design 1.
2. Tap "Team Member" -> Verify navigation to **Team Member Selection** (Design 2).
3. Select "Staff" and tap "Continue" -> Verify navigation to **Login Screen** (Design 3) showing "Staff Login".
4. Select "Rider" and tap "Continue" -> Verify navigation to **Login Screen** showing "Rider Login".
5. Tap "Customer" on the first screen -> Verify navigation to **Login Screen** showing "Customer Login".
