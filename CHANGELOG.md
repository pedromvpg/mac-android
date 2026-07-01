# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0-beta] - 2026-06-30

### Added
- `mac-android push` — copy files and folders from Mac to Android (`/sdcard/Download` by default)
- `mac-android pull` — copy files from Android to Mac
- `mac-android ls` — list files on the Android device
- `mac-android devices` — list connected devices
- `mac-android setup` — install `adb` via Homebrew
- `ANDROID_SERIAL` support for multi-device setups
- GUI app (`mac-android.app`) with drag-and-drop push, file explorer, and transfer log
- Universal binary (Apple Silicon + Intel)
- Hardened Runtime enabled for notarization readiness

### Security
- Remote paths passed to `adb shell` are now shell-escaped (single-quote wrapping) to prevent injection of metacharacters from user-supplied or device-side filenames
- Transfer success/failure now determined by `adb` exit code rather than output string matching
