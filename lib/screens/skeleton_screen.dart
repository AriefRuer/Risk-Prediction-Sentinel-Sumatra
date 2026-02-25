import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import '../providers/alert_provider.dart';
import '../models/alert_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../main.dart' show flutterLocalNotificationsPlugin;
import '../utils/map_injector.dart'
    if (dart.library.html) '../utils/map_injector_web.dart';

// ---------------------------------------------------------------------------
// Chat message model
// ---------------------------------------------------------------------------
class _ChatMessage {
  final String text;
  final bool isUser;
  final bool isStreaming;
  _ChatMessage({
    required this.text,
    required this.isUser,
    this.isStreaming = false,
  });
  _ChatMessage copyWith({String? text, bool? isStreaming}) => _ChatMessage(
    text: text ?? this.text,
    isUser: isUser,
    isStreaming: isStreaming ?? this.isStreaming,
  );
}

// ---------------------------------------------------------------------------
// Main Screen
// ---------------------------------------------------------------------------
class SkeletonScreen extends ConsumerStatefulWidget {
  const SkeletonScreen({super.key});

  @override
  ConsumerState<SkeletonScreen> createState() => _SkeletonScreenState();
}

class _SkeletonScreenState extends ConsumerState<SkeletonScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  bool _isMapReady = false;
  String? _previousRiskLevel;
  StreamSubscription<AlertModel>? _alertSubscription;
  bool _chatOpen = false;
  bool _chatLoading = false;
  final List<_ChatMessage> _chatMessages = [];
  Position? _userPosition;
  bool _locationPermissionDenied = false;

  // FIX 2: Static polygon constants — only computed once.
  static const List<LatLng> _hazardZone = [
    LatLng(5.5450, 95.3100),
    LatLng(5.5450, 95.3350),
    LatLng(5.5650, 95.3350),
    LatLng(5.5650, 95.3100),
  ];
  static final Set<Polygon> _criticalPolygons = {
    Polygon(
      polygonId: const PolygonId('risk_area'),
      points: _hazardZone,
      fillColor: Colors.red.withValues(alpha: 0.3),
      strokeColor: Colors.red,
      strokeWidth: 2,
    ),
  };

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------
  @override
  void initState() {
    super.initState();
    _injectGoogleMapsApiKey();
    _startLocationTracking();

    // Subscribe to Firestore stream once for notification side-effects.
    _alertSubscription = FirebaseFirestore.instance
        .collection('alerts')
        .doc('aceh_jaya')
        .snapshots()
        .map((doc) => AlertModel.fromFirestore(doc))
        .listen((alert) {
          if (alert.riskLevel == 'Critical' &&
              _previousRiskLevel != 'Critical') {
            _triggerLocalPushNotification(alert.aiAdvice);
            _previousRiskLevel = null;
          } else {
            _previousRiskLevel = alert.riskLevel;
          }
        });
  }

  @override
  void dispose() {
    _alertSubscription?.cancel();
    _chatController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Location
  // ---------------------------------------------------------------------------
  Future<void> _startLocationTracking() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        if (mounted) setState(() => _locationPermissionDenied = true);
        return;
      }
      // 5-second timeout — if emulator GPS is not configured, fall back gracefully.
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 5));
      if (mounted) setState(() => _userPosition = pos);
    } catch (e) {
      debugPrint('Location error (using fallback): $e');
      // Show "Location Undetected" card instead of infinite spinner.
      if (mounted) setState(() => _locationPermissionDenied = true);
    }
  }

  bool _isUserInRedZone() {
    if (_userPosition == null) return false;
    final lat = _userPosition!.latitude;
    final lng = _userPosition!.longitude;
    // Simple bounding-box check against _hazardZone polygon
    return lat >= 5.5450 && lat <= 5.5650 && lng >= 95.3100 && lng <= 95.3350;
  }

  // ---------------------------------------------------------------------------
  // Notifications
  // ---------------------------------------------------------------------------
  void _triggerLocalPushNotification(String advice) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'critical_alerts_channel',
          'Critical Alerts',
          channelDescription: 'Emergency disaster warnings',
          importance: Importance.max,
          priority: Priority.high,
          ticker: 'ticker',
        );
    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
    );
    try {
      await flutterLocalNotificationsPlugin.show(
        id: 0,
        title: '🚨 EMERGENCY ALERT: Aceh Jaya',
        body: advice,
        notificationDetails: details,
        payload: 'item x',
      );
    } catch (e) {
      debugPrint("Failed to show local notification: $e");
    }
  }

  // ---------------------------------------------------------------------------
  // Map helpers
  // ---------------------------------------------------------------------------
  void _injectGoogleMapsApiKey() {
    final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'];
    if (kIsWeb && apiKey != null && apiKey.isNotEmpty) {
      injectWebMapsApiKeySafely(apiKey);
    }
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _isMapReady = true);
    });
  }

  // ---------------------------------------------------------------------------
  // Mock / test actions
  // ---------------------------------------------------------------------------
  Future<void> _sendMockAlert() async {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Triggering AI Pipeline...')),
      );
    }
    try {
      final response = await http.get(
        Uri.parse(
          'http://127.0.0.1:5001/sentinel-sumatra-3c917/us-central1/test_sentinel_hub_check',
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              response.statusCode == 200
                  ? 'AI Successfully Triggered!'
                  : 'Failed: ${response.statusCode}',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Emulator error: $e')));
      }
    }
  }

  void _sendCriticalAlert() {
    const String mockAdvice =
        'MOCK CRITICAL ALERT: Immediate evacuation required. Move to higher ground immediately.';
    _triggerLocalPushNotification(mockAdvice);
    FirebaseFirestore.instance.collection('alerts').doc('aceh_jaya').set({
      'riskLevel': 'Critical',
      'predictedTime': FieldValue.serverTimestamp(),
      'aiAdvice': mockAdvice,
      'statusMessage': 'Mock critical alert triggered manually for testing.',
    }, SetOptions(merge: true));
    _previousRiskLevel = null;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Critical Alert Triggered in Database!')),
    );
  }

  // ---------------------------------------------------------------------------
  // AI Chatbot (streaming via Server-Sent Events)
  // ---------------------------------------------------------------------------
  Future<void> _sendChatMessage(String message, AlertModel alert) async {
    if (message.trim().isEmpty) return;
    _chatController.clear();

    setState(() {
      _chatMessages.add(_ChatMessage(text: message, isUser: true));
      _chatMessages.add(
        _ChatMessage(text: '', isUser: false, isStreaming: true),
      );
      _chatLoading = true;
    });
    _scrollChatToBottom();

    final context =
        'Risk Level: ${alert.riskLevel}. '
        'NDVI: ${alert.ndvi.toStringAsFixed(2)}, '
        'BSI: ${alert.bsi.toStringAsFixed(2)}, '
        'NDWI: ${alert.ndwi.toStringAsFixed(2)}, '
        'Moisture: ${alert.moisture.toStringAsFixed(2)}. '
        'AI Advice: ${alert.aiAdvice}';

    try {
      // Use the HTTP Cloud Function URL (emulator or production)
      const String baseUrl =
          'http://127.0.0.1:5001/sentinel-sumatra-3c917/us-central1/chat_with_ai';

      final request = http.Request('POST', Uri.parse(baseUrl))
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode({'message': message, 'context': context});

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 30),
      );

      // Read streaming SSE tokens
      String accumulated = '';
      await for (final chunk in streamedResponse.stream.transform(
        utf8.decoder,
      )) {
        for (final line in chunk.split('\n')) {
          if (line.startsWith('data: ')) {
            final data = line.substring(6).trim();
            if (data == '[DONE]') break;
            try {
              final json = jsonDecode(data) as Map<String, dynamic>;
              final token = json['token'] as String? ?? '';
              accumulated += token;
              if (mounted) {
                setState(() {
                  _chatMessages[_chatMessages.length - 1] = _chatMessages.last
                      .copyWith(text: accumulated, isStreaming: true);
                });
                _scrollChatToBottom();
              }
            } catch (_) {}
          }
        }
      }

      // Mark streaming as done
      if (mounted) {
        setState(() {
          _chatMessages[_chatMessages.length - 1] = _chatMessages.last.copyWith(
            isStreaming: false,
          );
          _chatLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _chatMessages[_chatMessages.length - 1] = _chatMessages.last.copyWith(
            text:
                'Sorry, I couldn\'t connect to the AI. Make sure the emulator is running.',
            isStreaming: false,
          );
          _chatLoading = false;
        });
      }
    }
  }

  void _scrollChatToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final alertAsyncValue = ref.watch(alertStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sentinel Sumatra'),
        actions: [
          IconButton(
            icon: const Icon(Icons.send_time_extension),
            tooltip: 'Mock Alert',
            onPressed: _sendMockAlert,
          ),
        ],
      ),
      body: alertAsyncValue.when(
        data: (alert) => _buildBody(alert),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
      floatingActionButton:
          alertAsyncValue.whenData((alert) => alert).value != null
          ? _buildFabs(alertAsyncValue.value!)
          : const SizedBox.shrink(),
    );
  }

  Widget _buildFabs(AlertModel alert) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // --- AI Chatbot FAB ---
        if (_chatOpen) _buildChatPanel(alert),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FloatingActionButton.extended(
              heroTag: 'chat_fab',
              onPressed: () => setState(() => _chatOpen = !_chatOpen),
              backgroundColor: const Color(0xFF1A237E),
              icon: Icon(
                _chatOpen ? Icons.close : Icons.smart_toy_rounded,
                color: Colors.white,
              ),
              label: Text(
                _chatOpen ? 'Close' : 'AI Advisor',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            FloatingActionButton.extended(
              heroTag: 'alert_fab',
              onPressed: _sendCriticalAlert,
              backgroundColor: Colors.redAccent,
              icon: const Icon(Icons.warning, color: Colors.white),
              label: const Text(
                'Test Alert',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildChatPanel(AlertModel alert) {
    return Container(
      width: MediaQuery.of(context).size.width - 32,
      height: 380,
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1A237E), width: 1.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 20),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF1A237E),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.smart_toy_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Sentinel AI Advisor',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.greenAccent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                const Text(
                  'Live',
                  style: TextStyle(color: Colors.greenAccent, fontSize: 11),
                ),
              ],
            ),
          ),
          // Messages
          Expanded(
            child: _chatMessages.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Text(
                        '🤖 Ask me about flood risk,\nevacuation routes, or satellite data.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white54, fontSize: 13),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _chatScrollController,
                    padding: const EdgeInsets.all(8),
                    itemCount: _chatMessages.length,
                    itemBuilder: (ctx, i) => _buildChatBubble(_chatMessages[i]),
                  ),
          ),
          // Input
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFF1A237E))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatController,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: const InputDecoration(
                      hintText: 'Ask about flood risk or evacuation...',
                      hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                    ),
                    onSubmitted: (v) => _sendChatMessage(v, alert),
                  ),
                ),
                _chatLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.greenAccent,
                        ),
                      )
                    : IconButton(
                        icon: const Icon(
                          Icons.send_rounded,
                          color: Colors.greenAccent,
                          size: 20,
                        ),
                        onPressed: () =>
                            _sendChatMessage(_chatController.text, alert),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatBubble(_ChatMessage msg) {
    return Align(
      alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.65,
        ),
        decoration: BoxDecoration(
          color: msg.isUser ? const Color(0xFF1A237E) : const Color(0xFF1B2631),
          borderRadius: BorderRadius.circular(12),
          border: msg.isUser ? null : Border.all(color: Colors.white12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: Text(
                msg.text.isEmpty && msg.isStreaming ? '...' : msg.text,
                style: TextStyle(
                  color: msg.isUser ? Colors.white : Colors.greenAccent,
                  fontSize: 12,
                ),
              ),
            ),
            if (msg.isStreaming && msg.text.isNotEmpty) ...[
              const SizedBox(width: 4),
              const SizedBox(
                width: 8,
                height: 8,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: Colors.greenAccent,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Body
  // ---------------------------------------------------------------------------
  Widget _buildBody(AlertModel alert) {
    final Set<Polyline> polylines = {
      Polyline(
        polylineId: const PolylineId('safe_route'),
        points: alert.safeRoutePoints,
        color: Colors.blue,
        width: 5,
      ),
    };

    return Column(
      children: [
        // Map (top half)
        Expanded(
          flex: 1,
          child: _isMapReady
              ? GoogleMap(
                  initialCameraPosition: const CameraPosition(
                    target: LatLng(5.5500, 95.3167),
                    zoom: 13,
                  ),
                  polygons: alert.riskLevel == 'Critical'
                      ? _criticalPolygons
                      : {},
                  polylines: polylines,
                  myLocationEnabled: false,
                  myLocationButtonEnabled: false,
                )
              : const Center(child: CircularProgressIndicator()),
        ),
        // Analytics cards (bottom half)
        Expanded(
          flex: 1,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  _buildStatusCard(alert),
                  const SizedBox(height: 8),
                  _buildSafetyZoneCard(),
                  const SizedBox(height: 8),
                  _buildSatelliteCards(alert),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Status Card
  // ---------------------------------------------------------------------------
  Widget _buildStatusCard(AlertModel alert) {
    final isNormal = alert.riskLevel != 'Critical';
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Risk Level: ${alert.riskLevel}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: isNormal ? Colors.white : Colors.redAccent,
                    ),
                  ),
                  Text(
                    'Updated: ${alert.predictedTime.toString().split('.')[0]}',
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Status: ${alert.statusMessage}',
                    style: const TextStyle(color: Colors.grey),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                ],
              ),
            ),
            Column(
              children: [
                const Text(
                  'Network',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                CircleAvatar(
                  radius: 10,
                  backgroundColor: alert.isFromCache
                      ? Colors.red
                      : Colors.green,
                  child: Icon(
                    alert.isFromCache ? Icons.cloud_off : Icons.cloud_done,
                    size: 12,
                    color: Colors.white,
                  ),
                ),
                Text(
                  alert.isFromCache ? 'Cached' : 'Live',
                  style: const TextStyle(fontSize: 10),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Safety Zone Card
  // ---------------------------------------------------------------------------
  Widget _buildSafetyZoneCard() {
    if (_locationPermissionDenied) {
      return Card(
        color: Colors.grey[900],
        child: const ListTile(
          leading: Icon(Icons.location_off, color: Colors.grey),
          title: Text(
            '📍 Location Undetected',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            'To simulate GPS: open emulator Extended Controls (⋯) → Location → enter coordinates → Set Location.',
          ),
        ),
      );
    }
    if (_userPosition == null) {
      return Card(
        color: Colors.grey[900],
        child: const ListTile(
          leading: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          title: Text('Detecting Your Location...'),
        ),
      );
    }

    final inRedZone = _isUserInRedZone();
    return Card(
      color: inRedZone ? Colors.red[900] : Colors.green[900],
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            Icon(
              inRedZone ? Icons.warning_amber_rounded : Icons.check_circle,
              color: Colors.white,
              size: 36,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    inRedZone
                        ? '⚠️ You Are in the Red Zone'
                        : '✅ You Are in the Safe Zone',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    inRedZone
                        ? 'Evacuate immediately! Move to higher ground now.'
                        : 'Your current location is outside the hazard area.',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Satellite Analytics Cards
  // ---------------------------------------------------------------------------
  Widget _buildSatelliteCards(AlertModel alert) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            '📡 Satellite Intelligence',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: Colors.white70,
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: _analyticsCard(
                icon: '🌿',
                label: 'Forest Cover',
                value: _ndviLabel(alert.ndvi),
                color: _ndviColor(alert.ndvi),
                tooltip: 'NDVI: ${alert.ndvi.toStringAsFixed(3)}',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _analyticsCard(
                icon: '💧',
                label: 'Flood Risk',
                value: _ndwiLabel(alert.ndwi),
                color: _ndwiColor(alert.ndwi),
                tooltip: 'NDWI: ${alert.ndwi.toStringAsFixed(3)}',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _analyticsCard(
                icon: '🌡️',
                label: 'Ground Stability',
                value: _stabilityLabel(alert.bsi, alert.moisture),
                color: _stabilityColor(alert.bsi, alert.moisture),
                tooltip:
                    'BSI: ${alert.bsi.toStringAsFixed(3)} | Moisture: ${alert.moisture.toStringAsFixed(3)}',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _analyticsCard(
                icon: '🤖',
                label: 'AI Assessment',
                value: alert.aiAdvice.length > 60
                    ? '${alert.aiAdvice.substring(0, 57)}...'
                    : alert.aiAdvice,
                color: const Color(0xFF1A237E),
                tooltip: alert.aiAdvice,
                smallText: true,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _analyticsCard({
    required String icon,
    required String label,
    required String value,
    required Color color,
    required String tooltip,
    bool smallText = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: Card(
        color: color.withValues(alpha: 0.15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: color.withValues(alpha: 0.5)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(icon, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: smallText ? 10 : 13,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // NDVI helpers
  String _ndviLabel(double v) {
    if (v > 0.6) return 'Healthy 🟢';
    if (v > 0.3) return 'Moderate 🟡';
    return 'Degraded 🔴';
  }

  Color _ndviColor(double v) {
    if (v > 0.6) return Colors.green;
    if (v > 0.3) return Colors.yellow;
    return Colors.red;
  }

  // NDWI helpers
  String _ndwiLabel(double v) {
    if (v > 0.2) return 'Flooding Likely 🔴';
    if (v > 0.0) return 'Water Elevated 🟡';
    return 'Normal 🟢';
  }

  Color _ndwiColor(double v) {
    if (v > 0.2) return Colors.red;
    if (v > 0.0) return Colors.orange;
    return Colors.blue;
  }

  // Stability helpers (combined BSI + Moisture)
  String _stabilityLabel(double bsi, double moisture) {
    if (bsi > 0.1 || moisture > 0.2) return 'Unstable 🔴';
    if (bsi > 0.0 || moisture > 0.1) return 'Moderate 🟡';
    return 'Stable 🟢';
  }

  Color _stabilityColor(double bsi, double moisture) {
    if (bsi > 0.1 || moisture > 0.2) return Colors.red;
    if (bsi > 0.0 || moisture > 0.1) return Colors.orange;
    return Colors.green;
  }
}
