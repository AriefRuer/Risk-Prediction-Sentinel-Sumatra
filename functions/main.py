import json
import os
import datetime

# The Cloud Functions for Firebase SDK
from firebase_functions import scheduler_fn
from firebase_admin import initialize_app, firestore

# Adam's imports
import requests
from oauthlib.oauth2 import BackendApplicationClient
from requests_oauthlib import OAuth2Session
from google import genai

# Initialize the Firebase Admin SDK
initialize_app()

TOKEN_URL = "https://identity.dataspace.copernicus.eu/auth/realms/CDSE/protocol/openid-connect/token"
STATS_URL = "https://sh.dataspace.copernicus.eu/api/v1/statistics"

def get_aceh_stats(lat, lng, client_id, client_secret):
    client = BackendApplicationClient(client_id=client_id)
    oauth = OAuth2Session(client=client)
    token = oauth.fetch_token(token_url=TOKEN_URL, client_secret=client_secret, include_client_id=True)
    
    script = """
    //VERSION=3
    function setup() {
      return {
        input: [{ bands: ["B02", "B04", "B08", "B11", "dataMask"] }],
        output: [
          { id: "stats", bands: 2 },
          { id: "dataMask", bands: 1 }
        ]
      };
    }
    function evaluatePixel(samples) {
      let ndvi = (samples.B08 - samples.B04) / (samples.B08 + samples.B04);
      let bsi = ((samples.B11 + samples.B04) - (samples.B08 + samples.B02)) / ((samples.B11 + samples.B04) + (samples.B08 + samples.B02));
      return {
        stats: [ndvi, bsi],
        dataMask: [samples.dataMask]
      };
    }
    """

    payload = {
        "input": {
            "bounds": { "bbox": [lng, lat, lng+0.005, lat+0.005] },
            "data": [{ "type": "sentinel-2-l2a", "dataFilter": { "maxCloudCoverage": 30 } }]
        },
        "aggregation": {
            "evalscript": script,
            "timeRange": { "from": "2025-12-01T00:00:00Z", "to": "2026-02-21T00:00:00Z" },
            "aggregationInterval": { "of": "P1D" }
        },
        "calculations": { "stats": { "statistics": { "default": { "percentiles": { "k": [50] } } } } }
    }

    response = oauth.post(STATS_URL, json=payload)
    res_json = response.json()

    if 'data' not in res_json:
        print("Satellite API Error:", res_json)
        return None
    return res_json

def analyze_risk_with_gemini(ndvi_val, bsi_val, api_key):
    client = genai.Client(api_key=api_key)

    prompt = f"""
    Role: Disaster Risk Scientist for Aceh, Indonesia.
    Input Data:
    - NDVI (Forest Density): {ndvi_val:.2f}
    - BSI (Soil Exposure): {bsi_val:.2f}

    Note: NDVI 0.85 is very healthy forest. BSI -0.27 is very low soil exposure.

    Task: Analyze the landslide/flood risk based on these values.
    Return ONLY a valid JSON object.
    Lower score means lower risk.
    Format: {{"score": [0-100], "advice": "[One short sentence]"}}
    """

    response = client.models.generate_content(
        model="gemini-2.0-flash",
        contents=prompt
    )
    return response.text

@scheduler_fn.on_schedule(schedule="every 1 hours", timezone="Asia/Jakarta")
def run_sentinel_hub_check(event: scheduler_fn.ScheduledEvent) -> None:
    # 1. Fetch API Keys and Secrets from Environment Variables
    # (These will be configured via Firebase before deployment)
    cdse_client_id = os.environ.get("CDSE_CLIENT_ID")
    cdse_client_secret = os.environ.get("CDSE_CLIENT_SECRET")
    gemini_api_key = os.environ.get("GEMINI_API_KEY")

    if not all([cdse_client_id, cdse_client_secret, gemini_api_key]):
        print("Error: Missing required secrets. Please ensure GEMINI_API_KEY is deployed.")
        return

    try:
        lat_aceh, lng_aceh = 4.72, 95.61
        print("Connecting to Sentinel-2 Satellite...")
        
        raw_data = get_aceh_stats(lat_aceh, lng_aceh, cdse_client_id, cdse_client_secret)
        
        if not raw_data:
            print("Could not retrieve satellite data.")
            return

        valid_entry = None
        for entry in reversed(raw_data['data']):
            if 'outputs' in entry and 'stats' in entry['outputs']:
                if entry['outputs']['stats']['bands']['B0']['stats']['mean'] is not None:
                    valid_entry = entry
                    break

        if not valid_entry:
            print("No clear imagery found in this date range.")
            return
            
        median_ndvi = valid_entry['outputs']['stats']['bands']['B0']['stats']['mean']
        median_bsi = valid_entry['outputs']['stats']['bands']['B1']['stats']['mean']

        print(f"Stats Found -> NDVI: {median_ndvi:.2f} | BSI: {median_bsi:.2f}")

        # Get AI Prediction
        result_text = analyze_risk_with_gemini(median_ndvi, median_bsi, gemini_api_key)
        
        # Clean up the markdown block if it exists
        clean_json_str = result_text.replace("```json", "").replace("```", "").strip()
        
        try:
            ai_data = json.loads(clean_json_str)
            risk_score = int(ai_data.get("score", 0))
            ai_advice = ai_data.get("advice", "No advice provided.")
            
            # Determine risk level based on the Gemini score
            if risk_score >= 75:
                risk_level = "Critical"
            elif risk_score >= 40:
                risk_level = "Warning"
            else:
                risk_level = "Safe"
                
        except (json.JSONDecodeError, ValueError):
            risk_level = "Unknown"
            risk_score = 0
            ai_advice = clean_json_str # Fallback to raw text if JSON parsing fails
            
        # Hardcoded safe routing points for the prototype
        safe_points = [
            firestore.GeoPoint(5.5500, 95.3167),
            firestore.GeoPoint(5.5550, 95.3200),
            firestore.GeoPoint(5.5600, 95.3267),
        ]

        # Write the new data entirely directly to Firestore
        db = firestore.client()
        doc_ref = db.collection("alerts").document("aceh_jaya")
        
        doc_ref.set({
            "riskLevel": risk_level,
            "predictedTime": firestore.SERVER_TIMESTAMP,
            "safeRoutePoints": safe_points,
            "aiAdvice": ai_advice,
            "statusMessage": f"AI Sentinel Pipeline Executed successfully with Risk Score {risk_score}",
        }, merge=True)

        print(f"Successfully updated aceh_jaya alert at {datetime.datetime.now()}")

    except Exception as e:
        print(f"System Error: {e}")

from firebase_functions import https_fn

@https_fn.on_request()
def test_sentinel_hub_check(req: https_fn.Request) -> https_fn.Response:
    """
    HTTP trigger explicitly for testing the AI logic locally without waiting for the cron job.
    Run the emulator, then literally just click the URL it gives you to trigger the pipeline!
    """
    try:
        # SECURITY RATE LIMITING: Prevent Gemini API from being spammed
        db = firestore.client()
        doc_ref = db.collection("alerts").document("aceh_jaya")
        doc = doc_ref.get()
        
        if doc.exists:
            data = doc.to_dict()
            last_time = data.get("predictedTime")
            
            if last_time is not None:
                # Calculate time since last triggered
                now = datetime.datetime.now(datetime.timezone.utc)
                time_diff = now - last_time
                
                # If triggered less than 5 minutes ago, reject the request (HTTP 429)
                if time_diff.total_seconds() < 300:
                    time_left = 300 - int(time_diff.total_seconds())
                    return https_fn.Response(f"⏳ RATE LIMIT ACTIVE: Please wait {time_left} seconds to avoid Gemini API charges.", status=429)

        # If 5 minutes have passed, we run the AI logic
        class DummyEvent:
            headers = {}
        run_sentinel_hub_check(DummyEvent())
        return https_fn.Response("✅ SUCCESS: The Sentinel AI Pipeline has been manually triggered. Check your Flutter App!")
    except Exception as e:
        return https_fn.Response(f"❌ ERROR: {e}", status=500)
