# Ozone

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

## Backend Configuration

- **Firebase Project ID**: `ozone-fc7f`
- When launched without Firebase GoogleService files, the application automatically activates mock provider mode so developers can test UI, messaging, and call flows immediately out-of-the-box.
- To connect to the live Firebase project:
  - Place `google-services.json` in `android/app/`.
  - Place `GoogleService-Info.plist` in `ios/Runner/` and `macos/Runner/`.
