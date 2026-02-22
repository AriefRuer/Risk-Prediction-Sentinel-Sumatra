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

## 📋 Hackathon Task Distribution

To meet the hackathon deadline, the secret to winning is **Parallel Execution**. Each member has a clear "ownership zone."

### Member 1: AI Architect & Backend Lead 🧠
**The Goal:** Build the "Brain" of the project and the API that powers it.
- [x] **AI Prompt Engineering:** Create the system instructions for Gemini 1.5 Flash. Ensure it returns structured JSON (e.g., `{"risk_score": 85, "advice": "Move to Zone B"}`).
- [x] **Sentinel Hub / GEE Scripting:** Extract the forest canopy and soil moisture data for Aceh. *(Prototype Sentinel Hub OAuth implemented)*
- [x] **Cloud Logic:** Implement the "Decision Engine" on Cloud Run. This script takes satellite data -> sends it to Gemini -> returns a result.
- [x] **Hand-off:** Provides the API Endpoints or Firebase Cloud Functions to Member 3.

### Member 2: Flutter UI/UX Engineer 🎨
**The Goal:** Build a high-fidelity, polished mobile interface that looks like a finished product.
- [x] **The Map Shell:** Implement the Google Maps SDK. Set up the initial camera position on Aceh and create the logic to toggle different layers.
- [x] **Dashboard Components:** Create the "Risk Gauge," "Emergency Notification cards," and "Safety Checklists." *(Skeleton UI built; needs polish)*
- [x] **The "AI Advisor" Chat UI:** Build a clean, floating chat interface where users can ask Gemini for specific advice. *(Chat input wired; needs UI polish)*
- [ ] **Android View & UI Overhaul:** Port the web view successfully to a native Android build (`flutter run -d android`) and build out the final polished disaster-resilience dashboard.
- [ ] **Animations:** Add micro-interactions when the AI terminal types out new advice or the Risk Score flashes from "Low" to "Critical".
- [ ] **Hand-off:** Provides the Frontend UI Codebase to Member 3 for data integration.

### Member 3: Systems Integrator (The "Plumber") ⚙️
**The Goal:** Make the UI (Member 2) and the AI (Member 1) talk to each other in real-time.
- [x] **Firebase Setup (Database):** Configure Firestore (the database) and initialize the App.
- [ ] **Firebase Setup (Auth/FCM):** Configure User Authentication and Cloud Messaging (FCM) Push Notifications.
- [x] **Real-time Streams:** Write the code that "Listens" to the Firestore database so the UI updates instantly. *(Riverpod Streams implemented)*
- [ ] **Navigation & Logic:** Handle the transition between the splash screen, the main map, and the evacuation route views.
- [x] **Hand-off:** The Integrated App to Member 4 for final testing and demo.

### Member 4: Impact, Data & QA Lead 📊
**The Goal:** Ensure the project hits the "Impact" (60%) and "Innovation" (10%) scores.
- [ ] **SDG Documentation:** Write the "Problem Statement" and "SDG Alignment" (Section 1). Use real data from the Aceh floods to justify the tech.
- [ ] **User Validation (Section 2):** Conduct 3–5 "Speed Interviews" with peers to get feedback on the UI and document the iterations.
- [ ] **The Demo Video:** Script and record the walkthrough. Ensure the video clearly shows the AI Reasoning and the Google Tech integration.
- [ ] **Hand-off:** The Final Submission Package (GitHub Repo + Video + Slides).

---

### 🤝 Team Sync Strategy
- **Morning (15m):** Stand-up. "What prompt are you working on today?"
- **Mid-day (15m):** Code Merge. Member 3 pulls Member 1’s API and Member 2’s Widgets into the main branch.
- **Evening (30m):** Vibe Check. Member 4 tests the app and reports "hallucinations" or UI bugs for the team to fix.
