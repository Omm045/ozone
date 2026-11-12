# Ozone — project guide for Claude sessions

## What this is
Flutter app for **1:1 video/audio calling plus 1:1 text chat** on **iOS, Android, macOS**.
Bundle/package id: `com.ozone.app.ozone`.

- **Backend:** Firebase project `ozone-fc7f5`, **Spark (free) plan**. Firebase Auth (email/password + Google
  sign-in) and Firestore (users, chats, messages, call signaling). No Cloud Functions.
- **Calling:** `flutter_webrtc`, Firestore-based signaling (`calls/{id}` plus `callerCandidates` /
  `calleeCandidates` subcollections), adaptive quality controller (720p/1080p/1440p/4K tiers), audio-only mode.
- **Distribution:** GitHub Releases at github.com/Omm045/ozone (public repo). The in-app update checker
  (`lib/core/utils/update_checker.dart`) reads `releases/latest` and compares its tag to the app version.

## Hard constraints (apply unless the user explicitly changes them)
- **STUN-only peer-to-peer.** No TURN, no relay, no Cloud Functions, no new backend services. The ICE
  config must stay a single swappable list (`lib/core/webrtc/ice_config_provider.dart`).
- **Do not touch the back camera.** Its configuration and code paths are confirmed correct. Front-camera changes
  only. Note: in `camera_constraint_selector.dart`, the per-platform iOS/Android/macOS branches serve **both**
  cameras on real devices, so editing them changes back-camera behavior too.
- **No conference/group calling, and no screen sharing.**
- **Secrets:** never commit or print the contents of `lib/firebase_options.dart`, `android/app/google-services.json`,
  `ios/Runner/GoogleService-Info.plist`, or `macos/Runner/GoogleService-Info.plist`. They are gitignored and must stay that way.
  Regenerate them locally with `flutterfire configure`.
- **No history rewrites, force pushes, pushes, tags, or releases** without explicit instruction from the user.
- Commit only when asked.

## Verify, don't trust reports
A previous agent reported features nobody asked for and results nobody verified. Treat READMEs, release notes,
commit messages, code comments, and earlier summaries as **claims**. Before calling something done, verify it
against the actual code and git history, and cite `file:line` evidence. State plainly what you tested, how,
and what you did not test.

## Real-device testing is the standard
Camera, microphone, audio routing, and network/ICE behavior must be validated on **real devices** (Android phone,
iPhone, Mac). Simulators, emulators, unit tests, and widget tests do not prove call behavior. If something was
only checked in tests, say so explicitly and list the device steps the user needs to run.

## Commands
```bash
flutter pub get
flutter analyze
flutter test                                   # unit/widget tests in test/
flutter test integration_test/<file>.dart -d <device>

flutter devices
flutter run -d <android-device-id>             # Android phone
flutter run -d <iphone-device-id>              # iPhone (needs signing in Xcode)
flutter run -d macos                           # Mac

flutter build apk --release --split-per-abi    # Android (releases ship split APKs)
flutter build ios --release                    # iOS (ipa via Xcode archive / signing)
flutter build macos --release                  # macOS
```
iOS/macOS CocoaPods: `cd ios && pod install` / `cd macos && pod install` after changing plugins.

## Layout (lib/)
- `main.dart`: Firebase init (falls back to Mock services on failure), Provider setup, `RootGate` auth routing,
  and `IncomingCallOverlayManager` wrapping every route.
- `core/auth/`: `AuthService` (Firebase + Mock) and `OzoneAuthProvider` (ChangeNotifier).
- `core/database/chat_repository.dart`: `ChatRepository` (Firestore + Mock), covering chats, messages, hide-for-me,
  account data cleanup, and the incoming-call stream.
- `core/webrtc/`: `webrtc_call_manager.dart` (PeerConnection lifecycle + signaling), `adaptive_quality_controller.dart`,
  `camera_constraint_selector.dart`, `sdp_utils.dart`, `ice_config_provider.dart`, `quality_preferences.dart`.
- `core/utils/update_checker.dart`: GitHub release check.
- `features/`: `auth`, `chats` (chat list + connect dialog), `conversation`, `call` (call screen + incoming overlay), `settings`.
- `models/`, `design_system/`.

## Firestore data (as used in code)
- `users/{uid}`: uid, email (lowercased), displayName, isEmailVerified, createdAt (ISO string)
- `chats/{chatId}`: id, participantUids, participantEmails, lastMessageText, lastMessageTimestamp, updatedAt, hiddenFor.
  Direct chat id = sorted `uidA_uidB`. Invite chats use `invite_{uid}_{sanitizedEmail}` with `pending_invite` in participantUids.
- `chats/{chatId}/messages/{id}`: chatId, senderUid, senderEmail, text, timestamp, status, isDeleted
- `calls/{callId}`: callerUid/Email, calleeUid/Email, status, callType, failureReason, offer, answer, createdAt.
  Subcollections `callerCandidates` and `calleeCandidates` hold candidate, sdpMid, and sdpMLineIndex.
- Rules: `firestore.rules`. Deploying rules is an outward-facing action, so confirm with the user first.
