# Ozone

[![License: AGPL v3](https://img.shields.io/badge/License-AGPL_v3-blue.svg)](./LICENSE)

Ozone is a focused, high-performance cross-platform audio/video calling and 1:1 messaging application built in Flutter and Dart, targeting **iOS**, **macOS**, and **Android** from a single codebase.

The centerpiece feature is an **adaptive-quality video calling engine** powered by WebRTC, starting at **1080p @ 30fps baseline** and stepping up to **1440p** and **4K** on sustained bandwidth headroom.

---

## Product Scope

1. **Email-Based Authentication**:
   - Sign up and sign in with email and password.
   - Email verification enforcement with resend capability.
   - Built-in session persistence via Firebase Auth (`ozone-fc7f`).
   - No phone auth, social logins, or access codes.

2. **Connect by Email**:
   - Direct connection initiated by entering a peer's email address.
   - Automatic lookup in Firestore `/users`.
   - Creates a direct 1:1 chat thread if registered, or a pending invite thread if the email is not yet registered.
   - No group chats, contact sync, or social discovery feeds.

3. **1:1 Text Chat**:
   - Plain 1:1 messaging backed by Firestore subcollections (`/chats/{chatId}/messages/{messageId}`).
   - Delivery and read receipts (`sending -> sent -> delivered -> read`).
   - Real-time message streaming via `StreamBuilder`.

4. **Adaptive Audio/Video Calling (Centerpiece)**:
   - **1080p Baseline**: Calls always initiate at 1080p (1920x1080), targeting a minimum 30fps baseline.
   - **Continuous WebRTC Stats**: Continuously monitors bandwidth, round-trip time (RTT), and packet loss via `RTCPeerConnection.getStats()`.
   - **Anti-Flapping Step-Up**: Steps resolution up toward 4K (`1080p -> 1440p -> 4K`) **only on 3 consecutive good samples** with sustained bandwidth headroom, avoiding flapping on single network spikes.
   - **Smooth Degradation**: Steps down immediately on degradation (`4K -> 1440p -> 1080p -> 720p`), never freezing or dropping the call.
   - **Dynamic Camera Constraints**: Camera capture constraints are matched to the negotiated send resolution (never captures 4K to downscale when running at 1080p).
   - **On-Screen Quality HUD**: Live indicator displaying current resolution tag (`4K`, `1440p`, `1080p`, `720p`), framerate (fps), RTT latency (ms), and signal strength bars.

---

## Known Limitation (v1: STUN-Only P2P)

### The Trade-off
Version 1 relies on **STUN + direct peer-to-peer connectivity only**, using 5 redundant Google public STUN servers:
- `stun:stun.l.google.com:19302`
- `stun:stun1.l.google.com:19302`
- `stun:stun2.l.google.com:19302`
- `stun:stun3.l.google.com:19302`
- `stun:stun4.l.google.com:19302`

Calls will succeed across normal home and mobile networks. However, calls will **fail to connect** between users located behind symmetric NATs or restrictive corporate firewalls.

### User Feedback on Timeout
When a direct P2P connection cannot be negotiated within a 15-second timeout, the app does not spin indefinitely. It transitions cleanly to a failure state and informs the user:
> *"Couldn't connect — this may be due to one of your networks."*

### How to Add TURN Later (Extensibility)
The architecture does **not** hardcode this limitation. The ICE server configuration is centralized in:
[`lib/core/webrtc/ice_config_provider.dart`](lib/core/webrtc/ice_config_provider.dart)

To add TURN relay support (such as Cloudflare Calls, Twilio, or Coturn), pass your TURN credentials into `turnServers` in `IceServerConfig`:
```dart
const configWithTurn = IceServerConfig(
  stunUrls: IceServerConfig.defaultStunUrls,
  turnServers: [
    {
      'urls': [
        'turn:turn.cloudflare.com:3478?transport=udp',
        'turn:turn.cloudflare.com:443?transport=tcp',
      ],
      'username': '<TURN_USERNAME>',
      'credential': '<TURN_CREDENTIAL>',
    },
  ],
);
```
No calling logic, signaling code, or UI components need to change.

---

## Project Structure

```
ozone/
├── android/                   # Android native project & manifest
├── ios/                       # iOS native project & Info.plist
├── macos/                     # macOS native project, Info.plist & entitlements
├── lib/
│   ├── core/
│   │   ├── auth/              # AuthService (Firebase & Mock), OzoneAuthProvider
│   │   ├── database/          # FirestoreChatRepository, MockChatRepository
│   │   └── webrtc/            # WebRtcCallManager, AdaptiveQualityController,
│   │                          # IceConfigProvider, CameraConstraintSelector
│   ├── design_system/         # OzoneTheme, QualityIndicatorWidget
│   ├── features/
│   │   ├── auth/              # AuthScreen, EmailVerificationScreen
│   │   ├── chats/             # ChatListScreen, ConnectByEmailDialog
│   │   ├── conversation/      # ConversationScreen (Chat + Call trigger)
│   │   └── call/              # CallScreen (Remote/Local video, controls, HUD)
│   ├── models/                # UserModel, ChatMessage, ChatModel, CallSession
│   └── main.dart              # App entry point, MultiProvider & RootGate
└── test/
    ├── adaptive_quality_test.dart # Quality state machine & anti-flapping tests
    ├── auth_test.dart             # Auth transitions & verification tests
    ├── chat_repository_test.dart  # Connect-by-email & thread creation tests
    ├── message_test.dart          # 1:1 message send & delivery receipts tests
    ├── ice_config_test.dart       # STUN list & TURN extensibility tests
    └── widget_test.dart           # UI smoke & auth gate test
```

---

## Platform Setup & Permissions

### iOS (`ios/Runner/Info.plist`)
Camera and microphone usage descriptions configured:
- `NSCameraUsageDescription`: *"Ozone requires camera access for HD and 4K video calling."*
- `NSMicrophoneUsageDescription`: *"Ozone requires microphone access for audio and video calls."*

### macOS (`macos/Runner/Info.plist` & `.entitlements`)
- Usage descriptions configured in `Info.plist`.
- App Sandbox entitlements enabled in `DebugProfile.entitlements` and `Release.entitlements`:
  - `com.apple.security.network.client`
  - `com.apple.security.network.server`
  - `com.apple.security.device.camera`
  - `com.apple.security.device.audio-input`

### Android (`android/app/src/main/AndroidManifest.xml`)
- Permissions requested:
  - `android.permission.CAMERA`
  - `android.permission.RECORD_AUDIO`
  - `android.permission.INTERNET`
  - `android.permission.ACCESS_NETWORK_STATE`
  - `android.permission.MODIFY_AUDIO_SETTINGS`
  - `android.permission.BLUETOOTH`
- Features declared: `android.hardware.camera` and `android.hardware.camera.autofocus`.
- Minimum SDK: Android 21+.

---

## Running the Project

### 1. Run Unit & Widget Tests
```bash
flutter test
```
All 19 tests run in isolated environments without needing live Firebase or WebRTC media hardware.

### 2. Run on macOS
```bash
flutter run -d macos
```

### 3. Run on iOS Simulator or Device
```bash
flutter run -d ios
```

### 4. Run on Android Emulator or Device
```bash
flutter run -d android
```

---

## Local Setup (Post-Clone)

Because Firebase credentials and configuration files are excluded from version control to prevent secret leaks, freshly cloned repositories do not include them.

After cloning, generate your local configuration:

```bash
# 1. Install FlutterFire CLI if you haven't already:
dart pub global activate flutterfire_cli

# 2. Run configure to generate local files:
flutterfire configure --project=ozone-fc7f5
```

This generates the following files locally:
- `android/app/google-services.json`
- `ios/Runner/GoogleService-Info.plist`
- `macos/Runner/GoogleService-Info.plist`
- `lib/firebase_options.dart`

> [!IMPORTANT]
> **Git History & Secret Rotation Notice**:
> Adding files to `.gitignore` prevents future leaks going forward, but does **not** erase them from past Git commits. Old leaked credentials remain accessible in the repository's commit history unless the history is rewritten using tools like `git filter-repo` or `BFG Repo-Cleaner`. Rewriting Git history is destructive and requires force-pushing, which breaks existing clones. Any exposed API keys must be rotated immediately in Google Cloud Console / Firebase Console.

---

## Install on iPhone

Ozone is not on the App Store. Each release includes an **unsigned** iPhone app
(`ozone-ios-<version>-unsigned.ipa`) that you sign and install yourself with
your own Apple ID.

1. Download `ozone-ios-<version>-unsigned.ipa` from the
   [latest release](https://github.com/Omm045/ozone/releases/latest).
2. Install it with **AltStore** or **Sideloadly** using your own Apple ID:
   - **Sideloadly** (on a Mac or PC): connect the iPhone, drag the `.ipa` into
     Sideloadly, enter your Apple ID and click **Start**.
   - **AltStore**: in AltStore on the iPhone, tap **My Apps → +** and pick the
     `.ipa`.
3. On the iPhone, open **Settings → General → VPN & Device Management** and
   trust your developer certificate (first install only). On recent iOS
   versions you may also need to turn on **Developer Mode**.
4. Open Ozone and allow **Local Network**, **Camera** and **Microphone** when
   asked. Calls need Local Network access to connect directly to devices on
   your Wi-Fi; if you tapped Don't Allow, enable it in
   **Settings → Privacy & Security → Local Network**.

Limits of free Apple IDs:

- The app **expires after 7 days** and must be re-installed or refreshed
  (AltStore can refresh it automatically over Wi-Fi).
- A free Apple ID can have at most **3 sideloaded apps** active at a time.
- Sideloading usually changes the bundle identifier (for example
  `com.ozone.app.ozone.<TEAM_ID>`). Email sign-in still works; **Google
  Sign-In may not work** in a sideloaded copy.

Building from source remains an option: install Flutter and Xcode, add your
own Firebase configuration (`lib/firebase_options.dart` and
`ios/Runner/GoogleService-Info.plist`, generated with `flutterfire configure`),
then run `flutter run --release` with an iPhone connected.

---

## macOS Gatekeeper & Distribution Notice

When running or installing an app bundle distributed outside the Mac App Store, macOS Gatekeeper may display a warning: *"Ozone can't be opened because Apple cannot check it for malicious software"* or *"developer cannot be verified"*.

This is standard macOS security behavior for apps built with a free (non-paid) Apple Developer account. There is no code-level fix for an unnotarized binary.

### Options:

1. **For Local / Personal / Ad-Hoc Testing (Free)**:
   - Do not double-click `ozone.app`.
   - **Right-click (or Control-click) `ozone.app` → select "Open" → click "Open"** in the security confirmation dialog.
   - This is a **one-time action per machine**; macOS remembers the exception for future launches.

2. **For Official Public Distribution (Requires Paid Apple Developer Program - $99/yr)**:
   - Requires an active Apple Developer Program membership.
   - The release pipeline must sign the bundle with a Developer ID Application certificate and submit the artifact to Apple's Notary Service:
     ```bash
     # 1. Code sign with Developer ID Application certificate:
     codesign --deep --force --options runtime --sign "Developer ID Application: Your Name (TEAM_ID)" build/macos/Build/Products/Release/ozone.app

     # 2. Create notarization archive:
     ditto -c -k --keepParent build/macos/Build/Products/Release/ozone.app build/ozone-macos.zip

     # 3. Submit for notarization:
     xcrun notarytool submit build/ozone-macos.zip --keychain-profile "AC_PASSWORD" --wait

     # 4. Staple ticket to the app:
     xcrun stapler staple build/macos/Build/Products/Release/ozone.app
     ```
   - Do not attempt notarization commands without an active paid Apple Developer account.

---

## Backend Configuration

- **Firebase Project ID**: `ozone-fc7f5`
- The application connects to `ozone-fc7f5` when `firebase_options.dart` and platform GoogleService files are present.
- If launched in an environment without configured Firebase credentials, the application can activate mock provider mode for offline UI and pipeline development.

---

## License

This project is licensed under the GNU Affero General Public License v3.0 or later (AGPL-3.0-or-later) - see the [LICENSE](./LICENSE) file for details.

