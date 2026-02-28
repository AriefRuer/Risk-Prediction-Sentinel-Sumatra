# Sentinel Sumatra — Technical Documentation

This document serves as the technical companion to our main project overview, detailing the architecture, implementation, challenges, and future of Sentinel Sumatra in a structured format.

**What is Sentinel Sumatra?**
It is a proactive disaster resilience platform that uses Copernicus Sentinel-2 satellite imagery to monitor flood and landslide risks (like deforestation and soil moisture) in real time. Google Gemini AI translates this raw data into a localized risk score and powers an interactive, multilingual chat assistant. Built on Flutter and Firebase, it provides affected communities with live risk maps, automated push alerts, and an offline SOS toolkit, ensuring they receive critical emergency guidance even when cellular networks fail.

---

## 1. Technical Architecture

Sentinel Sumatra employs a modern, serverless, and highly decoupled architecture leveraging the full power of the Google Cloud and Firebase ecosystems. This structure ensures the mobile app remains lightweight and responsive on the user's device, while handling intensive, real-time AI calculations securely in the cloud. By completely decoupling the frontend mapping layer from the backend AI pipeline, we guarantee scalability and ease of maintenance.

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

Building the predictive engine required careful orchestration between raw satellite telemetry, AI inference, and mobile UI rendering. This section breaks down the specific technical techniques we used to bridge the gap between complex earth observation data and an intuitive, Figma-inspired mobile user experience. We prioritized offline resiliency and transparent AI logic across the entire stack.

| Feature Area | Implementation Approach |
| :--- | :--- |
| **AI Pipeline** | A scheduled Cloud Function pings the Copernicus Data Space Ecosystem (CDSE) for Aceh Jaya to calculate NDVI, NDWI, and BSI. Instead of rigid heuristics, these raw indices are fed to Gemini to computationally weigh moisture vs. ground vulnerability, outputting a unified Risk Score. |
| **Push Alerts** | When the AI transitions a risk score to "Critical", the Cloud Function triggers `firebase_admin.messaging` to emit a topic-wide push notification to all devices on the `disaster_alerts` topic. |
| **Figma UI** | To keep complex data accessible, we use custom `BackdropFilter` widgets with `ImageFilter.blur()`. The map is structurally constrained to the top 55% of the screen to prevent overlap and scroll bleed with the floating telemetry cards. |
| **Offline SOS** | When offline, the app cannot use Google Directions API. We apply a **1.35x winding factor multiplier** directly to the local Haversine straight-line distance to realistically estimate the curving road distance to the nearest cached Safe Zone. |

---

## 3. Challenges Faced

Integrating live satellite science into a consumer mobile app presented several unique hurdles. From handling unpredictable open-source API responses to refining the map's interactive UX, here is how we diagnosed and solved the most critical technical roadblocks during our prototyping phase.

| Challenge | Impact | Implemented Solution |
| :--- | :--- | :--- |
| **Data Translation** | Satellite API responses are raw floating-point numbers, meaningless to local residents trying to evacuate. | Leveraged Gemini AI to translate mathematical formulas into plain language directly on the device, paired with color-coded visual indicators. |
| **CORS Errors** | The Firebase Python SDK encountered `AttributeError` conflicts regarding `CorsOptions`, breaking the AI chatbot in emulation. | Bypassed unstable native wrappers by manually injecting standard CORS headers directly into the HTTP responses inside the Cloud Function. |
| **Map Scroll Bleed** | Figma-style floating glass cards caused the underlying Google Map to unintentionally zoom when sliding the panel. | Restructured the layout using `Positioned` to limit the active Map widget specifically to the top half of the screen, removing touch overlap. |

---

## 4. Future Roadmap

We view the current prototype as merely the foundational layer. To evolve Sentinel Sumatra from a local proof-of-concept into a robust national resilience infrastructure, we have mapped out a multi-phase rollout. This roadmap heavily focuses on expanding our geo-spatial processing capabilities, integrating physical hardware, and establishing peer-to-peer network reliability.

| Phase | Timeline | Primary Objectives |
| :--- | :--- | :--- |
| **Phase 1** | Next 3 Months | **Granular Geofencing:** Move from a single "Aceh Jaya" generic alert to dynamic sub-district polygon risk assessments.<br><br>**Mesh Networking:** Allow devices to securely daisy-chain hazard alerts peer-to-peer using Bluetooth/WiFi Direct when cell networks fail. |
| **Phase 2** | 6-12 Months | **Crowdsourced Validation:** Users upload photos of water levels. Processed by Gemini Multimodal to refine satellite predictions.<br><br>**Hardware Integration:** Integrate with physical river-basin IoT sensors to cross-reference satellite data with ground truth. |
| **Phase 3** | 1+ Years | **Global Dynamic Deployment:** Shift from hardcoded regional tracking (e.g. Aceh Jaya) to a fully dynamic architecture where the app passes the user's localized GPS coordinates to the cloud backend, instantly generating a custom Copernicus satellite bounding box for any location on Earth (e.g. tracking floods in Malaysia).<br><br>**Gov Dashboard:** Enterprise web-portal for disaster agencies to track community evacuation progress and bottleneck anomalies in real-time. |
