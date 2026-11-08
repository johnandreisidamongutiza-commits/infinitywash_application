# In-App Update System Guide (GitHub Releases)

This document explains how your in-app APK update system works and how to manage releases.

---

## 1. Initial Setup (One-time)

### A. Host your `version.json` file
1. A sample file [`version.json`](./version.json) has been created in your project root.
2. Push this file to your GitHub repository (e.g. on the `main` branch).
3. Obtain the raw URL for the file:
   `https://raw.githubusercontent.com/<YOUR_GITHUB_USERNAME>/<YOUR_REPO_NAME>/main/version.json`
4. Open [`lib/config/update_config.dart`](./lib/config/update_config.dart) and paste your raw URL into `versionJsonUrl`.

### B. Create your Release Keystore (Run once)
To allow existing users to update without an "App not installed / Signature mismatch" error, every release APK must be signed with the exact same keystore.

1. Open PowerShell / Command Prompt and run:
   ```bash
   keytool -genkey -v -keystore android/app/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```
2. Copy `android/key.properties.example` to `android/key.properties`:
   ```properties
   storePassword=YOUR_STORE_PASSWORD
   keyPassword=YOUR_KEY_PASSWORD
   keyAlias=upload
   storeFile=upload-keystore.jks
   ```
3. Keep `upload-keystore.jks` and `key.properties` safe! They are already ignored in `android/.gitignore` so they will never be uploaded to GitHub.

---

## 2. Release Workflow for Every Future Update

Whenever you want to release an update to your users:

### Step 1: Bump version and build number in `pubspec.yaml`
```yaml
# Increment the build number (+X) by at least 1 every release!
version: 1.0.1+2
```

### Step 2: Build the signed release APK
```bash
flutter build apk --release
```
Your release APK will be generated at:
`build/app/outputs/flutter-apk/app-release.apk`

### Step 3: Create GitHub Release
1. Go to your GitHub repository -> **Releases** -> **Draft a new release**.
2. **Tag**: `v1.0.1` (matching your new version).
3. **Title**: `Infinity Wash v1.0.1`.
4. Attach `app-release.apk` to the release.
5. Click **Publish release**.
6. Copy the direct download link of the uploaded `.apk` file (e.g. `https://github.com/<owner>/<repo>/releases/download/v1.0.1/app-release.apk`).

### Step 4: Update `version.json` on GitHub
Update the fields in your hosted `version.json`:
```json
{
  "latestVersion": "1.0.1",
  "latestBuildNumber": 2,
  "minSupportedBuildNumber": 1,
  "apkUrl": "https://github.com/<owner>/<repo>/releases/download/v1.0.1/app-release.apk",
  "releaseNotes": [
    "Added new feature X",
    "Fixed delivery location bug"
  ],
  "forceUpdate": false
}
```
* **Optional Update**: Set `"forceUpdate": false` and keep `minSupportedBuildNumber` lower than `latestBuildNumber`. Users will see an update dialog with **"Update Now"** and **"Later"**.
* **Forced Update**: Set `"forceUpdate": true` OR set `minSupportedBuildNumber` equal to `latestBuildNumber`. The app will block usage and back buttons until the user updates.

---

## 3. How the In-App Update Operates

```
[App Opened / SplashScreen]
          │
          ▼
   Check version.json
          │
          ├── No new version or offline? ──► Continue to app silently
          │
          └── New version found?
                    │
                    ▼
          Display Update Dialog
          (Notes, Current vs Latest, Force/Optional)
                    │
                    ▼ [User taps Update]
          Check "Install Unknown Apps" permission
                    │
                    ├── If denied ──► Shows explanation modal & opens Settings
                    │
                    └── If granted ──► Downloads APK (0% - 100% progress bar)
                                            │
                                            ▼
                                  Opens Android Package Installer
                                            │
                                            ▼
                                  User taps "Install"
```

