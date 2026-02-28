# Sentinel Sumatra — Technical Documentation

This document serves as the technical companion to our main project overview, detailing the architecture, implementation, challenges, and future of Sentinel Sumatra in a structured format.

---

## 1. Technical Architecture

Sentinel Sumatra employs a modern, serverless, and highly decoupled architecture leveraging the full power of the Google Cloud and Firebase ecosystems.

| Layer | Technology | Purpose |
| :--- | :--- | :--- |
| **Frontend UI** | Flutter (Dart) | Delivers a consistent, high-performance, and visually rich cross-platform UI. |
| **State Mgt.** | Riverpod | Ensures robust, reactive UI updates whenever risk scores or telemetry change. |
| **Mapping** | Google Maps SDK | Interactive canvas for hazard polygons, safe zones, and evacuation polylines. |
| **Database** | Cloud Firestore | Central synchronization layer. Pushes risk metric updates to all clients instantly. |
| **Offline Cache** | Firestore Offline | Caches safe-zone coordinates & protocols to function during network failures. |
| **Compute** | Cloud Functions | Python backend for scheduled API polling, Gemini AI inference, and FCM triggers. |
| **Data Source** | Copernicus API | Supplies raw multispectral Sentinel-2 imagery indices (NDVI, NDWI, etc.). |
| **AI Inference** | Gemini 2.0 Flash | Translates mathematical indices into 0-100 hazard scores and powers the chatbot. |

---

## 2. Implementation Details

Building the predictive engine required careful orchestration between satellite data and AI inference.

| Feature Area | Implementation Approach |
| :--- | :--- |
| **AI Pipeline** | A scheduled Cloud Function pings the Copernicus Data Space Ecosystem (CDSE) for Aceh Jaya to calculate NDVI, NDWI, and BSI. Instead of rigid heuristics, these raw indices are fed to Gemini to computationally weigh moisture vs. ground vulnerability, outputting a unified Risk Score. |
| **Push Alerts** | When the AI transitions a risk score to "Critical", the Cloud Function triggers `firebase_admin.messaging` to emit a topic-wide push notification to all devices on the `disaster_alerts` topic. |
| **Figma UI** | To keep complex data accessible, we use custom `BackdropFilter` widgets with `ImageFilter.blur()`. The map is structurally constrained to the top 55% of the screen to prevent overlap and scroll bleed with the floating telemetry cards. |
| **Offline SOS** | When offline, the app cannot use Google Directions API. We apply a **1.35x winding factor multiplier** directly to the local Haversine straight-line distance to realistically estimate the curving road distance to the nearest cached Safe Zone. |

---

## 3. Challenges Faced

Integrating live satellite science into a consumer mobile app presented several unique hurdles.

| Challenge | Impact | Implemented Solution |
| :--- | :--- | :--- |
| **Data Translation** | Satellite API responses are raw floating-point numbers, meaningless to local residents trying to evacuate. | Leveraged Gemini AI to translate mathematical formulas into plain language directly on the device, paired with color-coded visual indicators. |
| **CORS Errors** | The Firebase Python SDK encountered `AttributeError` conflicts regarding `CorsOptions`, breaking the AI chatbot in emulation. | Bypassed unstable native wrappers by manually injecting standard CORS headers directly into the HTTP responses inside the Cloud Function. |
| **Map Scroll Bleed** | Figma-style floating glass cards caused the underlying Google Map to unintentionally zoom when sliding the panel. | Restructured the layout using `Positioned` to limit the active Map widget specifically to the top half of the screen, removing touch overlap. |

---

## 4. Future Roadmap

We view the current prototype as the foundational layer. Our roadmap for scaling Sentinel Sumatra focuses on hardware integration and expanded reach.

| Phase | Timeline | Primary Objectives |
| :--- | :--- | :--- |
| **Phase 1** | Next 3 Months | **Granular Geofencing:** Move from a single "Aceh Jaya" generic alert to dynamic sub-district polygon risk assessments.<br><br>**Mesh Networking:** Allow devices to securely daisy-chain hazard alerts peer-to-peer using Bluetooth/WiFi Direct when cell networks fail. |
| **Phase 2** | 6-12 Months | **Crowdsourced Validation:** Users upload photos of water levels. Processed by Gemini Multimodal to refine satellite predictions.<br><br>**Hardware Integration:** Integrate with physical river-basin IoT sensors to cross-reference satellite data with ground truth. |
| **Phase 3** | 1+ Years | **Pan-Indonesia Deployment:** Scale Cloud Functions to automatically spin up predictive zones for high-risk corridors across Indonesia.<br><br>**Gov Dashboard:** Enterprise web-portal for disaster agencies (BNPB) to track community evacuation progress and bottleneck anomalies in real-time. |
