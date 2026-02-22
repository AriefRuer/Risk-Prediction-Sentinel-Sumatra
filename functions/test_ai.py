import os
import json

# Import the core logic functions we wrote in main.py
from main import get_aceh_stats, analyze_risk_with_gemini

print("=== SENTINEL-SUMATRA LOCAL AI TEST ===")

# 1. Manually load the variables from the .env file
env_vars = {}
try:
    with open('.env', 'r') as f:
        for line in f:
            if line.strip() and not line.startswith('#'):
                try:
                    key, value = line.strip().split('=', 1)
                    env_vars[key] = value
                except ValueError:
                    pass
except FileNotFoundError:
    print("❌ Error: .env file not found. Make sure you are running this from the 'functions' folder.")
    exit()

cdse_client_id = env_vars.get("CDSE_CLIENT_ID")
cdse_client_secret = env_vars.get("CDSE_CLIENT_SECRET")
gemini_api_key = env_vars.get("GEMINI_API_KEY")

if not gemini_api_key or gemini_api_key == "YOUR_GEMINI_KEY_HERE":
    print("❌ Error: You need to paste your real Gemini API Key into the .env file first!")
    exit()

# 2. Test Coordinates for Aceh Jaya
lat_aceh, lng_aceh = 4.72, 95.61

print("\n1. Connecting to Sentinel Hub (Copernicus CDSE)...")
raw_data = get_aceh_stats(lat_aceh, lng_aceh, cdse_client_id, cdse_client_secret)

if raw_data and 'data' in raw_data:
    valid_entry = None
    for entry in reversed(raw_data['data']):
        if 'outputs' in entry and 'stats' in entry['outputs']:
            if entry['outputs']['stats']['bands']['B0']['stats']['mean'] is not None:
                valid_entry = entry
                break

    if valid_entry:
        median_ndvi = valid_entry['outputs']['stats']['bands']['B0']['stats']['mean']
        median_bsi = valid_entry['outputs']['stats']['bands']['B1']['stats']['mean']

        print(f"✅ Success! Found recent satellite data:")
        print(f"   - NDVI (Vegetation): {median_ndvi:.2f}")
        print(f"   - BSI (Bare Soil): {median_bsi:.2f}")

        print("\n2. Sending data to Gemini 2.0 Flash AI for analysis...")
        result_text = analyze_risk_with_gemini(median_ndvi, median_bsi, gemini_api_key)
        
        print(f"✅ AI Response Received:\n")
        print(result_text)
        
    else:
        print("❌ Error: No clear satellite imagery found in this date range.")
else:
    print("❌ Error: Could not retrieve satellite data. Check your CDSE Secret.")
