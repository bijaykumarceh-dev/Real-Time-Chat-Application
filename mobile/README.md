# Gather Flutter Android App

This directory contains the native Flutter Android client for the Gather
real-time chat application.

## Features

- Register and sign in through the Gather Express API.
- Connect to Socket.IO using the returned JWT handshake token.
- Show online users and the 50 most recent persisted messages.
- Send and receive real-time room messages.
- Show two-second typing indicators.
- Show read receipts on sent messages.
- Configure the server URL in the sign-in screen.
- Keep the active JWT in app memory for the current app process.

The current session design does not persist login after Android app restart.
It avoids an unnecessary native secure-storage/JNI dependency for this debug
APK.

## Run

Requirements:

- Flutter 3.47 or later
- Dart 3.13 or later
- Android SDK with accepted Android licenses

From this directory:

```sh
flutter pub get
flutter analyze
flutter test
flutter run
```

For a debug APK:

```sh
flutter build apk --debug
```

The output is written to:

```text
build/app/outputs/flutter-apk/app-debug.apk
```

## Server configuration

The app defaults to the Render URL:

```text
https://real-time-chat-application-r34x.onrender.com
```

When the Render backend is deployed and ready, use that URL in the sign-in
screen's server configuration dialog. For a local backend, use the workstation
LAN IP instead of `localhost`, for example:

```text
http://192.168.1.20:3001
```

HTTP server URLs are limited to development in the app. Production server URLs
should use HTTPS.

## Socket.IO events

The app uses the same server contract as the React client:

- `join` / `message:history`
- `users:update`
- `message:send` / `message:new`
- `typing:start` / `typing:stop` / `typing:update`
- `messages:read`
