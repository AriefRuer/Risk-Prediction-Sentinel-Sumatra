# Sentinel-Sumatra (KitaHack 26)

Sentinel-Sumatra is a prototype disaster-resilience application designed to provide real-time landslide and flood risk assessments using Copernicus Satellite Imagery (Sentinel-2) and Google's Gemini 2.0 Flash AI. 

This repository contains:
1.  **Frontend**: A cross-platform Flutter application with real-time Google Maps integration and a live AI diagnostic terminal.
2.  **Backend (Functions)**: A Python-based Firebase Cloud Function that fetches satellite imagery, calculates NDVI/BSI indices, queries Gemini for risk assessment, and securely pushes the results to Firestore.

---

## 🛠 Prerequisites

Before cloning and running this project, ensure you have the following installed on your machine:

1.  [Flutter SDK](https://docs.flutter.dev/get-started/install) (Version 3.19.0 or higher)
2.  [Python 3.10+](https://www.python.org/downloads/)
3.  [Firebase CLI](https://firebase.google.com/docs/cli) (`npm install -g firebase-tools`)
4.  A [Google Cloud/Firebase Project](https://console.firebase.google.com/)

---

## 🚀 Setup Instructions

Follow these steps exactly to run the Sentinel-Sumatra application locally.

### Step 1: Clone the Repository
```bash
git clone https://github.com/YOUR-USERNAME/sentinel-sumatra.git
cd sentinel-sumatra
```

### Step 2: Configure the Flutter App (Frontend)
Initialize the Flutter dependencies.
```bash
# Get Flutter packages
flutter pub get
```

You must link your own Firebase project to the Flutter app. 
*(Note: Ensure you have run `firebase login` first)*
```bash
# Configure Firebase for Flutter (Generates lib/firebase_options.dart)
flutterfire configure
```

### Step 3: Add Frontend API Keys
To render the Risk polygons, the Flutter app requires a Google Maps API Key.
1. In the **root** repository directory, create a new file named exactly `.env`.
2. Add the Google Maps key:
```ini
GOOGLE_MAPS_API_KEY="[YOUR_GOOGLE_MAPS_API_KEY_HERE]"
```

### Step 4: Configure the Python AI Backend
The AI logic runs inside a Python virtual environment to keep dependencies clean.
```bash
cd functions

# Create the virtual environment
python -m venv venv

# Activate the virtual environment
# On Windows:
venv\Scripts\activate
# On Mac/Linux:
source venv/bin/activate

# Install required AI and Satellite packages
pip install -r requirements.txt
```

### Step 5: Add Backend API Keys (Secrets)
The AI backend requires API keys to reach the satellites and Gemini. 
1. Inside the `functions/` folder, create a new file named exactly `.env`.
2. Add the groups' API KEYS: 
```ini
CDSE_CLIENT_ID="[YOUR_COPERNICUS_ID]"
CDSE_CLIENT_SECRET="[YOUR_COPERNICUS_SECRET]"
GEMINI_API_KEY="[YOUR_GEMINI_API_KEY]"
```
*(Note: `.env` is already added to `.gitignore`, so your keys are safe from being pushed to GitHub).*

---

## 🏃 Running the Application

### The Current Architecture (No Blaze Plan)
> [!WARNING]
> **Firebase Blaze Plan Limitation**
> Currently, the Google Cloud servers require a "Blaze" (Pay-as-you-go) billing account attached to deploy the Python Cloud Function to the internet. 
> 
> Because this project does not currently have a credit card attached, **the AI Python code cannot be deployed to Google's servers.**

To work around this limitation for local testing and Hackathon presentations, we run the Python backend locally on your laptop using the Firebase Emulator, while the Flutter app connects to the real Firestore Database on the internet.

### 1. Start the Local Python AI Engine
Open a terminal, activate your virtual environment, and run the emulator:
```bash
cd functions
venv\Scripts\activate

# Start the local simulated Google server
firebase emulators:start --only functions
```
Wait until you see `All emulators ready!`.

### 2. Start the Flutter Web App
Open a completely **separate terminal**, ensure you are in the root `sentinel_sumatra/` folder, and launch Chrome:
```bash
flutter run -d chrome
```

### 3. Trigger the AI 
Because we cannot rely on the blocked Google Cloud Scheduler, we added an HTTP endpoint to manually force the AI to run.
1. When your Flutter App opens in Chrome, click the **Puzzle Piece (Mock Alert)** icon in the top right corner.
2. The app will send an HTTP request to the local Firebase Emulator (`http://127.0.0.1:5001/...`), triggering the Python script.
3. The Python script reaches out locally to Copernicus and Gemini, and saves the new Risk Score to the live Cloud Database.
4. The Flutter UI listens to the live Cloud Database and updates instantly!

---

## 📋 Outstanding Tasks (Next Steps)

For the final production release, the following tasks must be completed:

- [ ] **Upgrade to Blaze Plan:** Attach a Google Cloud Billing account and set hard budget caps ($1.00) to allow deploying the `functions/main.py` code to production safely.
- [ ] **Deploy Cloud Function:** Run `firebase deploy --only functions` so the AI engine runs automatically every hour on Google servers without needing a laptop open.
- [ ] **Remove Local HTTP Trigger:** Delete the temporary `package:http` code from `lib/screens/skeleton_screen.dart` to prevent users from manually spanning the back-end AI.
- [ ] **UI Polish:** Add weather map overlays and dynamic styling to the Google Map polygon based on real-time flood data.
