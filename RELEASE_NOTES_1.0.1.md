# Ozone v1.0.1 Release Notes

Welcome to Ozone v1.0.1! This release brings major improvements to peer-to-peer video and audio fidelity, hardware-accelerated streaming, an all-new in-app Settings experience, update notifications, and permanent account deletion.

---

## What's New in v1.0.1

### 🎥 Higher Fidelity Video & Crystal-Clear Audio
* **Native High-FPS Video**: Ozone automatically queries your device camera sensor at call start and streams at your camera's maximum native frame rate (up to 60fps at 1080p).
* **Hardware-Accelerated Codecs**: Outgoing and incoming calls negotiate hardware-accelerated VP9 and Baseline H.264 video encoding, minimizing CPU load and power consumption across Apple Silicon (VideoToolbox) and Android (MediaCodec).
* **Retuned Bitrate Ladder**: Dynamic bandwidth management now scales up to 5.5 Mbps for 1080p, 10 Mbps for 1440p, and 20 Mbps for 4K when connection bandwidth allows.
* **Studio-Quality Voice (Opus 64 kbps)**: Audio streams are tuned to 64 kbps constant bitrate with in-band forward error correction for resilient voice calls. Built-in MacBook microphone capture has been tuned to prevent voice signal crushing.
* **Pure Direct P2P**: 100% direct peer-to-peer WebRTC via STUN with zero relay servers or third-party intermediaries.

---

### ⚙️ New Settings Panel
* **Account Info & Security**: Easily view your signed-in email and sign out securely.
* **Call Quality Preferences**: Choose your default call-start quality directly from the new Settings menu (**Auto (Adaptive)**, **720p**, **1080p**, **1440p**, or **4K**). Your selection persists across app launches.
* **In-App Update Checker**: Tap **Check for Updates** to instantly verify if a new release is available on GitHub and download update packages directly.

---

### 🗑️ Permanent Account Deletion
* Full compliance with privacy standards: delete your account directly inside Settings.
* Safely removes your credentials and profile while preserving 1-on-1 chat history for your contacts.
* Two-step safety dialog requires typing `"DELETE"` before confirmation to prevent accidental loss.

---

### 🛡️ Security & Clean Architecture
* **Rotated Credentials**: Fresh, secure Firebase credentials provisioned with Git leak protections enforced.
* **Streamlined Core Calling**: Focused exclusively on lightning-fast 1-on-1 direct peer-to-peer calls.

---

## Platform Availability & Installation Notice

* **Android**: Download and install the release APK matching your device architecture below (`app-arm64-v8a-release.apk` for modern devices).
* **macOS**: Download `ozone-macos-1.0.1.zip`, extract `ozone.app`, and move it to your `/Applications` folder.
  > **Gatekeeper Notice**: Because this build is not notarized through a paid Apple Developer subscription, macOS Gatekeeper will show a verification prompt on first launch. To open, **right-click `ozone.app` $\rightarrow$ Open $\rightarrow$ click Open** in the dialog (only required once per Mac). For more details, see the [macOS Gatekeeper section in README.md](README.md#macos-gatekeeper--distribution-notice).
* **iOS**: Sideloaded `.ipa` distribution is not offered for public release due to Apple Developer provisioning rules. iOS users should clone the repository and build from source via Xcode or Flutter (`flutter run -d <your-iphone>`).

---

## Assets Included in This Release
* `app-arm64-v8a-release.apk` (Android 64-bit ARM)
* `app-armeabi-v7a-release.apk` (Android 32-bit ARM)
* `app-x86_64-release.apk` (Android x86_64 emulator / devices)
* `ozone-macos-1.0.1.zip` (macOS Apple Silicon & Universal)
