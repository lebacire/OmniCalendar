# Google Calendar Integration Setup

Your Flutter calendar app now supports Google Calendar! Follow these steps to enable it:

## 1. Create a Google Cloud Project

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select an existing one
3. Enable these APIs:
   - Google Calendar API
   - Google Identity Service

## 2. Android Configuration

1. **Get your App's SHA-1 Fingerprint:**
   ```bash
   cd android
   ./gradlew signingReport
   ```
   Copy the SHA-1 value

2. **Create OAuth 2.0 Credentials:**
   - Go to Google Cloud Console > Credentials
   - Click "Create Credentials" > "OAuth 2.0 Client ID"
   - Select "Android" as the application type
   - Enter your app package name (in `AndroidManifest.xml`)
   - Enter the SHA-1 fingerprint from step 1
   - Download the configuration file

3. **Add to Android Project:**
   - Place the downloaded JSON file in `android/app/` directory
   - Update `android/build.gradle` with the Google Services plugin if needed

## 3. iOS Configuration

1. **Create OAuth 2.0 Credentials:**
   - Go to Google Cloud Console > Credentials
   - Click "Create Credentials" > "OAuth 2.0 Client ID"
   - Select "iOS" as the application type
   - Enter your app bundle ID (from `ios/Runner/Info.plist`)
   - iOS URL scheme will be provided - note this

2. **Update Info.plist:**
   - Open `ios/Runner/Info.plist`
   - Add the iOS URL scheme:
     ```xml
     <key>CFBundleURLTypes</key>
     <array>
       <dict>
         <key>CFBundleURLSchemes</key>
         <array>
           <string>com.googleusercontent.apps.YOUR_CLIENT_ID</string>
         </array>
       </dict>
     </array>
     ```

## 4. Web Configuration (Optional)

1. Create OAuth 2.0 Credentials for Web
2. Add your domain to authorized redirect URIs

## Features Implemented

✅ Google Sign-in button in the app bar  
✅ Automatic calendar event fetching  
✅ Display Google Calendar events on the calendar  
✅ Local event storage (can still add events manually)  
✅ Sign out functionality  

## How to Use

1. **Sign In:** Tap the "Sign In" button in the app bar
2. **Grant Permission:** Allow the app to access your Google Calendar
3. **View Events:** Google Calendar events will automatically appear on dates
4. **Add Local Events:** Use the + button to add local events

## Troubleshooting

**"Sign in failed" error:**
- Ensure SHA-1 fingerprint is correctly added to Google Cloud Console
- Check that package name matches your app's package name
- Verify all required APIs are enabled

**Events not loading:**
- Check internet connection
- Ensure Calendar API is enabled in Google Cloud Console
- Verify OAuth credentials are correctly configured

**iOS issues:**
- Make sure URL scheme is added to Info.plist
- Run `flutter clean` and rebuild
- Check that bundle ID matches Cloud Console configuration
