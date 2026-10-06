# Drokpo

A simple Tinder-style iOS app for the Tibetan community, built with SwiftUI on top of the Drokpo FastAPI backend.

## Requirements

- Xcode 16+ (iOS 17 deployment target)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- The `drokpo-backend` Firebase project with **Auth** (Apple + Google providers), **Firestore**, and **Storage**

## Setup

1. Download `GoogleService-Info.plist` for the Drokpo iOS app from the Firebase console (or `firebase apps:sdkconfig IOS --project drokpo-backend`) and place it at `Drokpo/Resources/GoogleService-Info.plist` (gitignored).
2. Open that plist, copy `REVERSED_CLIENT_ID`, and paste it into `GOOGLE_REVERSED_CLIENT_ID` in `project.yml` (needed for Google sign-in's redirect).
3. The backend URL is set in `Drokpo/Core/AppConfig.swift` (`https://drokpo-backend.web.app`, whose `/api/**` rewrites to the drokpo-api Cloud Run service).
4. Generate and open the project:

   ```sh
   xcodegen generate
   open Drokpo.xcodeproj
   ```

5. Select your development team in Signing & Capabilities (required for Sign in with Apple; Google sign-in works in the simulator without it).

## Architecture

- **SwiftUI + `@Observable`**, no third-party architecture libraries
- `Drokpo/Core/` — API client (Firebase ID token as bearer auth), models, session state machine, Firebase Storage photo upload
- `Drokpo/Features/` — one folder per screen: Auth, Onboarding, Feed (swipe deck), Likes, Chats, Profile
- Chat is real-time: the match list and open threads use Firestore snapshot listeners directly (permitted by the backend's security rules); match membership, unmatching, read receipts, and everything else go through the REST API
- Root routing: signed out → sign-in, signed in without profile → onboarding, otherwise the main tabs

## Status

Sign in (Apple/Google) → onboard (profile incl. optional Instagram handle + photos) → swipe feed → likes given/received → real-time chat with matches → profile editing with settings (sign out, delete account), plus report/block.
