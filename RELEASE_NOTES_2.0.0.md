# Ozone v2.0.0

Ozone is a 1:1 video/audio calling and chat app for Android, macOS and iOS.
This release focuses on making calls start, connect and end reliably.

## What's fixed

- **iPhone: video calls no longer crash when they start.** v1.5.0 could close
  on an iPhone as soon as a video call began.
- **Accepting an incoming call works again.** In v1.5.0, tapping Accept could
  close the incoming-call screen without joining the call.
- **The call screen closes when the other person hangs up.** It used to stay
  on "Connecting…".
- **A chat you deleted "for me" comes back when the other person sends a new
  message**, so their messages are no longer hidden from you.
- **Sharper Mac camera.** The Mac now sends 1920×1080 at 30 fps (it was
  sending 640×480).
- **The call timer starts when the call actually connects**, not a second or
  so early, and never runs for a call that didn't connect.
- **The camera and microphone turn off after a call fails** (declined, not
  answered, or couldn't connect), instead of staying on behind the error
  screen.
- **Sign-in and sign-up keep what you typed** after an error (wrong password,
  invalid email, weak password) instead of clearing the form.
- **Sign-out cleanup:** fixed an error that could occur after signing out.

## Removed

- The **Group Conference** banner and **Join Room** dialog, and the
  **Screen Share** button. These were not working features (Screen Share only
  started a normal video call). Ozone is 1:1 calling only. The unused Android
  screen-capture permission was removed too.

## Known limitations

- **Direct peer-to-peer only.** Calls connect directly between devices, with
  no relay server. They work best on the same Wi-Fi or on ordinary home
  networks, and can fail on restrictive networks (some corporate, school or
  mobile carrier networks).
- **The iPhone front camera currently sends 640×480.** Video from an iPhone
  looks softer than video from a Mac.
- **Short freezes were observed** on Mac ↔ iPhone video calls (brief pauses
  of about a quarter second, a few times per minute), even on a good network.
- **Android was tested on emulators only**, not on real Android phones.
- **Not yet tested:** long calls (15+ minutes), network drops during a call,
  slow or congested networks, and several other failure scenarios.

## Install

- **Android:** download the APK that matches your phone. Most modern phones
  use **arm64-v8a** (`app-arm64-v8a-release.apk`). Use `armeabi-v7a` for older
  32-bit phones and `x86_64` for emulators. You may need to allow installing
  apps from your browser or file manager.
- **macOS:** download `ozone-macos-2.0.0.zip` and unzip it. The app isn't
  notarized, so the first time you open it, **right-click (or Control-click)
  the app and choose Open**, then confirm.
- **iOS:** download `ozone-ios-2.0.0-unsigned.ipa` and install it with
  **AltStore** or **Sideloadly** using your own Apple ID, then trust your
  developer certificate in Settings → General → VPN & Device Management.
  Allow **Local Network**, Camera and Microphone when Ozone asks. With a free
  Apple ID the app expires after **7 days** (re-install or refresh it) and you
  can have at most **3** sideloaded apps. Google Sign-In may not work in a
  sideloaded copy; email sign-in does. Building from source with Flutter and
  Xcode is still possible.

Existing installs on 1.x will see an update prompt for 2.0.0 at launch.
