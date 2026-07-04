# Changsa

A simple Tinder-style iOS app for the Tibetan community, built with SwiftUI on top of the Changsa FastAPI backend.

## Requirements

- Xcode 16+ (iOS 17 deployment target)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- A Firebase project with **Auth** (Apple + Google providers), **Storage**, and later **Cloud Messaging**

## Setup

1. Download `GoogleService-Info.plist` from the Firebase console and place it at `Changsa/Resources/GoogleService-Info.plist` (gitignored).
2. Open that plist, copy `REVERSED_CLIENT_ID`, and paste it into `GOOGLE_REVERSED_CLIENT_ID` in `project.yml` (needed for Google sign-in's redirect).
3. Set the backend URL in `Changsa/Core/AppConfig.swift` (defaults to `http://localhost:8000` for development).
4. Generate and open the project:

   ```sh
   xcodegen generate
   open Changsa.xcodeproj
   ```

5. Select your development team in Signing & Capabilities (required for Sign in with Apple; Google sign-in works in the simulator without it).

## Architecture

- **SwiftUI + `@Observable`**, no third-party architecture libraries
- `Changsa/Core/` — API client (Firebase ID token as bearer auth), models, session state machine, Firebase Storage photo upload
- `Changsa/Features/` — one folder per screen: Auth, Onboarding, Feed (swipe deck), Matches, Profile
- Root routing: signed out → sign-in, signed in without profile → onboarding, otherwise the main tabs

## Status (v1)

Sign in (Apple/Google) → onboard (profile + photos) → swipe feed → matches list → profile editing, plus report/block. Chat and push notifications land when the backend adds their endpoints.
