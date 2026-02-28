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

---
---

# Sentinel Sumatra — Project Overview

## 🌍 The Problem

In regions like **Aceh Jaya, Indonesia**, communities live under the constant threat of sudden floods and landslides triggered by torrential rain and deforestation. The challenge is clear:

- **Early warning systems are reactive, not proactive.** Most alerts arrive *after* disaster has already begun.
- **Data is too complex.** Satellite imagery and spectral indices are meaningless to everyday residents.
- **Connectivity fails when it matters most.** When disaster strikes, cellular networks go down — cutting people off from life-saving guidance.

There is a critical need for a **localized, intelligent, and offline-capable** disaster resilience platform that puts advanced satellite science directly into the hands of at-risk communities.

---

## 💡 Our Solution

**Sentinel Sumatra** is a mobile-first disaster resilience platform that shifts the paradigm from *reacting to disasters* to *predicting and preparing for them*. By combining real-time Copernicus Sentinel-2 satellite imagery with Google Gemini AI, the app delivers localized, human-readable risk assessments — before disaster strikes.

---

## ✨ Core Features

### 🗺️ Live Interactive Risk Map
A real-time Google Maps interface visualizes danger zones (Red Zones) and designated safe evacuation areas (Green Zones) as intuitive overlays. Users instantly see whether their current location is safe or at risk.

### 📡 Satellite Intelligence Dashboard
Complex satellite spectral data — vegetation health (NDVI), surface water levels (NDWI), soil erosion (BSI), and ground moisture — is translated into plain-language risk indicators like *"Deforested (High Slide Risk) 🔴"* and *"Dry Surface 🟢"*, with raw index values displayed for full transparency.

### 📍 GPS Safety Tracking
The app monitors the user's GPS position in real time. If you enter a critical hazard zone, it immediately alerts you and renders a navigation polyline to the nearest safe zone. A **"Navigate to Safe Zone"** button redirects to Google Maps for turn-by-turn directions.

### 🤖 Sentinel AI Advisor
A streaming conversational chatbot powered by Google Gemini. Users can ask questions in **English, Indonesian, or Acehnese** and receive compassionate, practical survival guidance grounded in the latest satellite data — delivered word-by-word in real time.

### 🆘 Offline SOS Toolkit
When connectivity fails, the Offline SOS Toolkit provides:
1. **Basic Survival Protocols** — Cached safe-zone locations and step-by-step survival guides accessible without internet.
2. **SMS Emergency Broadcast** — A one-tap button that drafts an SOS text message to the national emergency number with the user's exact raw GPS coordinates, using SMS (which works even when mobile data is down).
3. **SOS Beacon** — Activates the device's flashlight as an emergency strobe, helping rescue teams locate the user in low-visibility conditions.

---

## 🔧 Google Technology Integration

Sentinel Sumatra is built entirely on the Google ecosystem, leveraging multiple Google technologies to deliver a reliable, intelligent, and scalable solution.

### 🧠 Google Gemini 2.0 Flash — Artificial Intelligence

**The Problem:** Raw satellite indices like NDVI = 0.482 or BSI = 0.073 are scientifically precise but meaningless to the average resident trying to decide whether to evacuate.

**How We Use It:**

- **Backend Risk Analysis Pipeline:**
  A Firebase Cloud Function runs on a scheduled interval, automatically fetching the latest satellite imagery from the Copernicus Sentinel-2 constellation. The raw spectral data (vegetation, moisture, erosion, and water indices) is sent directly to Gemini, which acts as an automated *Disaster Risk Scientist*. Gemini analyzes the combination of all four indices and returns a consolidated **0–100 hazard score** along with plain-language emergency advice. This score determines whether the community risk level is **Safe**, **Warning**, or **Critical**.

- **Frontend AI Advisor Chatbot:**
  Gemini also powers the in-app conversational AI. Users can type questions and receive streaming, context-aware responses based on the live environment data. The chatbot supports **multilingual interaction** (English, Indonesian, and local Acehnese dialect), ensuring accessibility for local communities.

### 🗺️ Google Maps Platform — Maps SDK for Flutter

**The Problem:** People need to instantly understand *where* is safe and *where* is dangerous, without reading data tables or coordinates.

**How We Use It:**

We render the entire primary interface on Google Maps. Hazard zones are drawn as red **Polygons** and **Circles**, while high-ground safe evacuation zones are highlighted in green. When a user is detected inside a danger zone, the app dynamically draws a **Polyline** representing the shortest escape route to the nearest safe zone. A redirect to Google Maps provides full turn-by-turn navigation.

### ☁️ Firebase — Cloud Backend Infrastructure

**The Problem:** Real-time data streaming, push notifications, and offline reliability are technically difficult to build from scratch — especially under disaster conditions where uptime is non-negotiable.

**How We Use It:**

| Firebase Service | Role in the System |
|------------------|-------------------|
| **Cloud Firestore** | The real-time data backbone. When the AI pipeline updates the risk score, Firestore instantly streams the new data to every connected device — no manual refresh needed. Firestore's **Offline Persistence** also caches the latest safe-zone coordinates locally, enabling the Offline SOS Toolkit to function even when all network connectivity is lost. |
| **Cloud Functions (Python)** | Handles all server-side processing securely in the cloud. Manages the scheduled satellite data polling, hosts the Gemini AI inference pipeline, runs the chatbot endpoint, and keeps all API keys completely hidden from the user's device. |
| **Cloud Messaging (FCM)** | When the AI escalates a risk level to **"Critical"**, the Cloud Function triggers FCM to broadcast high-priority push notifications to all registered devices — ensuring residents are alerted instantly, even if the app is in the background. |

### 📱 Flutter — Cross-Platform Frontend

The entire mobile application is built with **Flutter**, Google's cross-platform UI toolkit. A single codebase targets Android (and can be extended to iOS and web), enabling rapid iteration and consistent behavior across devices.

---

## 🌱 Alignment with UN Sustainable Development Goals

Sentinel Sumatra directly addresses two of the United Nations' Sustainable Development Goals.

### SDG 11 — Sustainable Cities and Communities

> **Target 11.B:** Substantially increase the number of cities and human settlements adopting and implementing integrated policies and plans towards inclusion, resource efficiency, mitigation and adaptation to climate change, and resilience to disasters.

**Our Impact:** Sentinel Sumatra democratizes access to satellite-based early warning data that was previously only available to government agencies and research institutions. By providing localized, AI-driven evacuation guidance directly on a mobile device — with full offline functionality — the platform ensures that even the most marginalized and infrastructure-poor communities have a reliable lifeline during crisis events.

### SDG 15 — Life on Land

> **Target 15.3:** By 2030, combat desertification, restore degraded land and soil, including land affected by desertification, drought, and floods.

**Our Impact:** Beyond disaster response, the platform continuously monitors critical environmental health indicators — specifically the **Normalized Difference Vegetation Index (NDVI)** for deforestation tracking and the **Bare Soil Index (BSI)** for erosion detection. These are the very root causes of severe flooding and landslides. By making this data visible and understandable to local communities, the app raises awareness of habitat destruction and can inform grassroots conservation efforts — helping people understand that **protecting their forests is the first step in preventing natural disasters**.

---

## 📄 License

This project was built for [KitaHack 2026](https://kitahack.gdgcloud.com/).
