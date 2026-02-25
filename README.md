# Sentinel Sumatra 🛰️

A real-time flood and landslide risk monitoring app for Aceh Jaya, Indonesia. Built with Flutter + Firebase + Copernicus Sentinel-2 satellite imagery + Gemini AI.

---

## Features

- 🗺️ **Live Risk Map** — Google Maps with hazard zone polygon and safe evacuation route overlay
- 📡 **Satellite Analytics** — NDVI, BSI, NDWI, and Soil Moisture indices from Copernicus Sentinel-2
- 🤖 **Streaming AI Chatbot** — Ask Sentinel AI about flood risk and evacuation; replies stream word-by-word via Gemini 2.0 Flash
- 📍 **Safety Zone Card** — GPS-based detection of whether you are in the Red Zone or Safe Zone
- 🔔 **Push Notifications** — Local and FCM notifications when risk escalates to Critical
- 🔄 **Offline Persistence** — Firestore offline caching keeps the app functional without internet

---

## Prerequisites

### 1. System Tools
| Tool | Version | Notes |
|------|---------|-------|
| Flutter SDK | ≥ 3.11.0 | [Install guide](https://docs.flutter.dev/get-started/install) |
| Dart SDK | included with Flutter | |
| Android Studio | Latest stable | Required for the Android emulator |
| Java JDK | 17 | Set `JAVA_HOME` to JDK 17 |
| Python | 3.11+ | For the Cloud Functions backend |
| Firebase CLI | Latest | `npm install -g firebase-tools` |
| Node.js | ≥ 18 | Required by Firebase CLI |

### 2. Android Emulator (Required)

This app **must run on the Android Emulator** — it does NOT run on a physical device without additional Google Maps and Firebase setup.

**Create the emulator in Android Studio:**
1. Open **Android Studio → Device Manager → Add Device**
2. Choose **Pixel 7** (or any phone with Google Play support)
3. Select system image: **API 35, x86_64, Google APIs**
4. Click **Finish** — the emulator will appear in Device Manager
5. Start the emulator before running `flutter run`

> ⚠️ You must use a **Google APIs** image (not plain AOSP) for Google Maps to work.

### 3. Simulating GPS in the Emulator

Since your laptop may not have a GPS chip, you must set a simulated location:

1. Start the emulator
2. Click **`⋯`** (Extended Controls) in the emulator side toolbar
3. Go to the **Location** tab
4. Enter coordinates:
   - **Latitude:** `5.5500`
   - **Longitude:** `95.3167`
5. Click **Set Location**

The app will then show whether you are in the Safe Zone or Red Zone.

---

## Flutter Dependencies

All dependencies are in `pubspec.yaml` and installed automatically with `flutter pub get`.

| Package | Purpose |
|---------|---------|
| `flutter_riverpod` | State management |
| `cloud_firestore` | Real-time database + offline persistence |
| `firebase_core` | Firebase initialization |
| `firebase_messaging` | FCM push notifications |
| `google_maps_flutter` | Interactive map with polygon/polyline overlays |
| `flutter_local_notifications` | Local on-device notifications |
| `geolocator` | GPS location for safety zone detection |
| `flutter_dotenv` | Load API keys from `.env` file |
| `http` | HTTP requests to Cloud Functions |
| `intl` | Date/time formatting |

---

## Environment Setup

### 1. Create the `.env` file

Create `sentinel_sumatra/.env` (it is gitignored):

```
GOOGLE_MAPS_API_KEY=your_google_maps_api_key_here
```

### 2. Firebase Configuration

Ensure the following files exist (provided by Firebase Console setup):
- `sentinel_sumatra/android/app/google-services.json`
- `sentinel_sumatra/lib/firebase_options.dart`

### 3. Cloud Functions Environment (`.env` in `/functions`)

Create `sentinel_sumatra/functions/.env`:

```
CDSE_CLIENT_ID=your_copernicus_client_id
CDSE_CLIENT_SECRET=your_copernicus_client_secret
GEMINI_API_KEY=your_google_gemini_api_key
```

Get these from:
- **Copernicus credentials:** [dataspace.copernicus.eu](https://dataspace.copernicus.eu) → OAuth → Create client
- **Gemini API key:** [aistudio.google.com](https://aistudio.google.com)

---

## Running the App

### Step 1 — Install Flutter dependencies
```bash
cd sentinel_sumatra
flutter pub get
```

### Step 2 — Start the Firebase Emulator (required for AI chatbot)
```bash
cd sentinel_sumatra/functions
pip install -r requirements.txt       # first time only
cd ..
firebase emulators:start
```

The emulator UI will open at `http://127.0.0.1:4000`. You should see the Functions emulator running.

### Step 3 — Start the Android Emulator

Open Android Studio → Device Manager → Start your emulator. Wait until it fully boots.

### Step 4 — Run the Flutter app
```bash
cd sentinel_sumatra
flutter run
```

Flutter will automatically detect the running Android emulator and deploy the app.

---

## Testing the Features

### Trigger the AI Pipeline (Satellite Data → Gemini Risk Score)

With the Firebase emulator running, open your browser and go to:
```
http://127.0.0.1:5001/sentinel-sumatra-3c917/us-central1/test_sentinel_hub_check
```

Or tap the **satellite icon** in the app's top-right AppBar. The app will update its risk level, satellite analytics, and AI advice within a few seconds.

### Test Critical Alert Notification

Tap the **"Test Alert"** button (red FAB, bottom right). A push notification will appear and the risk level on the map will turn Critical with the red polygon.

### Test the AI Chatbot

Tap the **"AI Advisor"** button (dark blue FAB). Type a question such as:
- *"Is it safe to stay at home?"*
- *"What does NDWI mean?"*
- *"How do I evacuate?"*

The reply streams word-by-word (make sure the Firebase emulator is running for this to work).

---

## Project Structure

```
sentinel_sumatra/
├── lib/
│   ├── main.dart                  # App entry point, Firebase + notification init
│   ├── models/
│   │   └── alert_model.dart       # AlertModel with satellite indices
│   ├── providers/
│   │   └── alert_provider.dart    # Riverpod providers for Firestore stream
│   ├── screens/
│   │   └── skeleton_screen.dart   # Main screen: map, analytics, chatbot
│   └── services/
│       └── firebase_service.dart  # Firestore stream + FCM subscription
├── functions/
│   ├── main.py                    # Cloud Functions: scheduler, chatbot, FCM trigger
│   ├── requirements.txt           # Python dependencies
│   └── .env                      # Secrets (gitignored)
├── android/
│   └── app/
│       ├── build.gradle.kts       # compileSdk 36, desugaring, JVM 17
│       └── src/main/
│           └── AndroidManifest.xml
└── .env                           # Google Maps API key (gitignored)
```

---

## Known Emulator Limitations

| Warning in logs | Cause | Impact |
|----------------|-------|--------|
| `Skipped N frames` | JIT compiler warming up on first launch | Resolves after ~30s, not a bug |
| `Cannot enable MyLocation layer` | Location permission check on emulator | Safe to ignore — `myLocationEnabled` is disabled in code |
| `E/GoogleApiManager: SecurityException` | Google Play Services not fully configured on emulator | Google Maps still loads map tiles correctly |
| `UnknownHostException: firestore.googleapis.com` | Emulator network latency | Firestore retries automatically; uses cached data in the meantime |
