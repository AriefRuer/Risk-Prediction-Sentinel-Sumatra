import json
import os
import datetime

# The Cloud Functions for Firebase SDK
from firebase_functions import scheduler_fn
from firebase_admin import initialize_app, firestore

# Adam's imports
# Initialize dotenv to fix the Firebase Emulator warning
from dotenv import load_dotenv
load_dotenv()

# Initialize the Firebase Admin SDK
initialize_app()

TOKEN_URL = "https://identity.dataspace.copernicus.eu/auth/realms/CDSE/protocol/openid-connect/token"
STATS_URL = "https://sh.dataspace.copernicus.eu/api/v1/statistics"

def get_aceh_stats(lat, lng, client_id, client_secret):
    from oauthlib.oauth2 import BackendApplicationClient
    from requests_oauthlib import OAuth2Session
    
    client = BackendApplicationClient(client_id=client_id)
    oauth = OAuth2Session(client=client)
    token = oauth.fetch_token(token_url=TOKEN_URL, client_secret=client_secret, include_client_id=True)
    
    # Evalscript computes 4 spectral indices from Sentinel-2 L2A bands:
    # B0: NDVI  - Vegetation health (higher = denser forest = lower landslide risk)
    # B1: BSI   - Bare Soil Index  (higher = more exposed soil = higher erosion risk)
    # B2: NDWI  - Water Index      (higher = more surface water = flood risk indicator)
    # B3: MOIST - Moisture Index   (higher = wetter soil = direct flood precursor)
    script = """
    //VERSION=3
    function setup() {
      return {
        input: [{ bands: ["B02", "B03", "B04", "B08", "B8A", "B11", "dataMask"] }],
        output: [
          { id: "stats", bands: 4 },
          { id: "dataMask", bands: 1 }
        ]
      };
    }
    function evaluatePixel(samples) {
      let ndvi  = (samples.B08 - samples.B04) / (samples.B08 + samples.B04);
      let bsi   = ((samples.B11 + samples.B04) - (samples.B08 + samples.B02)) / ((samples.B11 + samples.B04) + (samples.B08 + samples.B02));
      let ndwi  = (samples.B03 - samples.B08) / (samples.B03 + samples.B08);
      let moist = (samples.B8A - samples.B11) / (samples.B8A + samples.B11);
      return {
        stats: [ndvi, bsi, ndwi, moist],
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

def analyze_risk_with_gemini(ndvi_val, bsi_val, ndwi_val, moisture_val, api_key):
    from google import genai
    client = genai.Client(api_key=api_key)

    prompt = f"""
    Role: Disaster Risk Scientist for Aceh, Indonesia.
    Input Data (from Sentinel-2 satellite imagery):
    - NDVI  (Vegetation Health):  {ndvi_val:.3f}  [Range: -1 to 1, higher = denser forest]
    - BSI   (Bare Soil Index):    {bsi_val:.3f}   [Range: -1 to 1, higher = more exposed soil]
    - NDWI  (Surface Water):      {ndwi_val:.3f}  [Range: -1 to 1, higher = more standing water]
    - MOIST (Soil Moisture):      {moisture_val:.3f} [Range: -1 to 1, higher = wetter ground]

    Reference baselines for Aceh:
    - NDVI 0.85 = very healthy forest, 0.3 = sparse, <0 = barren/flooded
    - BSI -0.27 = low soil exposure, >0.1 = high erosion concern
    - NDWI >0 = open water present (flood indicator)
    - MOIST >0.2 = critically saturated soil

    Task: Assess combined landslide AND flood risk based on all 4 indices.
    Return ONLY a valid JSON object with no markdown.
    Format: {{"score": [0-100], "advice": "[One short sentence for residents]"}}
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
            
        median_ndvi     = valid_entry['outputs']['stats']['bands']['B0']['stats']['mean']
        median_bsi      = valid_entry['outputs']['stats']['bands']['B1']['stats']['mean']
        median_ndwi     = valid_entry['outputs']['stats']['bands']['B2']['stats']['mean']
        median_moisture = valid_entry['outputs']['stats']['bands']['B3']['stats']['mean']

        print(f"Stats Found -> NDVI: {median_ndvi:.3f} | BSI: {median_bsi:.3f} | NDWI: {median_ndwi:.3f} | MOIST: {median_moisture:.3f}")

        # Get AI Prediction with all 4 indices
        result_text = analyze_risk_with_gemini(median_ndvi, median_bsi, median_ndwi, median_moisture, gemini_api_key)
        
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
            
        # Dynamically place hazard locations based on risk severity
        hazard_points = []
        if risk_level == "Critical":
            # Simulate high-risk hotspots algorithmically
            # (In production, you'd calculate these directly from satellite pixel mapping)
            hazard_points = [
                firestore.GeoPoint(lat_aceh + 0.002, lng_aceh + 0.001),
                firestore.GeoPoint(lat_aceh - 0.001, lng_aceh - 0.003),
            ]
        elif risk_level == "Warning":
            hazard_points = [
                firestore.GeoPoint(lat_aceh, lng_aceh),
            ]
            
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
            "hazardPoints": hazard_points,
            "aiAdvice": ai_advice,
            "statusMessage": f"AI Sentinel Pipeline executed. Risk Score: {risk_score}",
            # Store raw satellite indices for the analytics dashboard
            "ndvi": round(median_ndvi, 4),
            "bsi":  round(median_bsi, 4),
            "ndwi": round(median_ndwi, 4),
            "moisture": round(median_moisture, 4),
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
                
                # If triggered less than 10 seconds ago, reject the request (HTTP 429)
                if time_diff.total_seconds() < 10:
                    time_left = 10 - int(time_diff.total_seconds())
                    return https_fn.Response(f"⏳ RATE LIMIT ACTIVE: Please wait {time_left} seconds to avoid Gemini API charges.", status=429)

        # If 5 minutes have passed, we run the AI logic
        class DummyEvent:
            headers = {}
        run_sentinel_hub_check(DummyEvent())
        return https_fn.Response("✅ SUCCESS: The Sentinel AI Pipeline has been manually triggered. Check your Flutter App!")
    except Exception as e:
        return https_fn.Response(f"❌ ERROR: {e}", status=500)

from firebase_functions import firestore_fn
from firebase_admin import messaging

@firestore_fn.on_document_updated(document="alerts/aceh_jaya")
def send_fcm_on_critical_alert(event: firestore_fn.Event[firestore_fn.Change[firestore_fn.DocumentSnapshot | None]]) -> None:
    """
    Listens for updates to the aceh_jaya alert document. 
    If the risk level changes from non-Critical to Critical, it blasts an FCM push notification.
    """
    if event.data is None or event.data.after is None:
        return
        
    before_data = event.data.before.to_dict() if event.data.before else {}
    after_data = event.data.after.to_dict() if event.data.after else {}
    
    before_risk = before_data.get('riskLevel', '')
    after_risk = after_data.get('riskLevel', '')
    
    if after_risk == 'Critical' and before_risk != 'Critical':
        print("🚨 Risk escalated to Critical! Sending FCM broadcast to disaster_alerts topic...")
        
        advice = after_data.get('aiAdvice', 'Immediate evacuation required. Move to higher ground.')
        
        # Max payload size is 4KB, so we truncate the advice just in case the AI rambles
        if len(advice) > 200:
            advice = advice[:197] + "..."
            
        message = messaging.Message(
            notification=messaging.Notification(
                title="EMERGENCY ALERT: Aceh Jaya",
                body=advice
            ),
            topic='disaster_alerts'
        )
        try:
            response = messaging.send(message)
            print(f'Successfully sent FCM message: {response}')
        except Exception as e:
            print(f'Error sending FCM message: {e}')


@https_fn.on_request()
def chat_with_ai(req: https_fn.Request) -> https_fn.Response:
    """
    Chatbot endpoint. Accepts POST { "message": "...", "context": "..." }
    Calls Gemini and returns the full reply as JSON: { "reply": "..." }
    """
    # Handle CORS manually (compatible with all firebase-functions versions)
    cors_headers = {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type",
    }

    if req.method == "OPTIONS":
        return https_fn.Response("", status=204, headers=cors_headers)

    try:
        body = req.get_json(silent=True) or {}
        user_message = body.get("message", "").strip()
        context = body.get("context", "")

        if not user_message:
            return https_fn.Response('{"error": "No message provided"}', status=400, headers=cors_headers, content_type="application/json")

        gemini_api_key = os.environ.get("GEMINI_API_KEY")
        if not gemini_api_key:
            return https_fn.Response('{"error": "AI service unavailable"}', status=503, headers=cors_headers, content_type="application/json")

        from google import genai
        client = genai.Client(api_key=gemini_api_key)

        system_prompt = f"""You are Sentinel AI, a disaster-resilience assistant for Aceh Jaya, Indonesia.
        You help residents understand flood and landslide risks, give safety advice, and explain satellite data.
        Current situation context: {context}
        Be concise (2-3 sentences max), compassionate, and practical. Respond in the same language as the user."""

        response = client.models.generate_content(
            model="gemini-2.0-flash",
            contents=[
                {"role": "user", "parts": [{"text": system_prompt + "\n\nUser: " + user_message}]}
            ]
        )

        reply = response.text or "I'm unable to provide a response right now."

        return https_fn.Response(
            json.dumps({"reply": reply}),
            status=200,
            headers=cors_headers,
            content_type="application/json",
        )

    except Exception as e:
        return https_fn.Response(f'{{"error": "{str(e)}"}}', status=500, headers=cors_headers, content_type="application/json")

