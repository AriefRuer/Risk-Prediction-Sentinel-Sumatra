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
import '../providers/theme_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'offline_toolkit_screen.dart';

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
enum ZoneDisplayMode { all, red, green }

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
  String _selectedLanguage = 'English';
  final List<String> _languages = ['English', 'Indonesian', 'Acehnese'];
  ZoneDisplayMode _zoneDisplayMode = ZoneDisplayMode.all;

  // Static mock hazard points for testing purposes
  static const List<LatLng> _mockHazardPoints = [
    LatLng(5.5550, 95.3167),
    LatLng(5.5450, 95.3267),
  ];

  // Static mock safe zones (high ground / evacuation centers)
  static const List<LatLng> _mockSafeZones = [
    LatLng(5.5200, 95.3150), // Inland elevated area to the South
    LatLng(5.5300, 95.3400), // Elevated area SE
  ];

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
      // HARDCODED DUMMY LOCATION for demonstration purposes
      // This coordinate (5.5560, 95.3175) is placed intentionally near
      // the first mock hazard point (5.5550, 95.3167) so the user
      // appears to be inside the Red Zone, triggering the navigation UI.
      setState(() {
        _userPosition = Position(
          longitude: 95.3175,
          latitude: 5.5560,
          timestamp: DateTime.now(),
          accuracy: 100.0,
          altitude: 0.0,
          altitudeAccuracy: 0.0,
          heading: 0.0,
          headingAccuracy: 0.0,
          speed: 0.0,
          speedAccuracy: 0.0,
        );
      });
    } catch (e) {
      debugPrint('Location error (using fallback): $e');
      // Show "Location Undetected" card instead of infinite spinner.
      if (mounted) setState(() => _locationPermissionDenied = true);
    }
  }

  bool _isUserInRedZone(AlertModel alert) {
    if (_userPosition == null || alert.riskLevel != 'Critical') return false;
    final userLat = _userPosition!.latitude;
    final userLng = _userPosition!.longitude;

    // Check if user is within 1 kilometer (1000 meters) of any active hazard point
    for (LatLng hazard in _mockHazardPoints) {
      double distanceInMeters = Geolocator.distanceBetween(
        userLat,
        userLng,
        hazard.latitude,
        hazard.longitude,
      );
      if (distanceInMeters <= 1000) {
        return true;
      }
    }
    return false;
  }

  bool _isUserInGreenZone() {
    if (_userPosition == null) return false;
    final userLat = _userPosition!.latitude;
    final userLng = _userPosition!.longitude;

    // Check if user is within 1 kilometer of a designated high-ground safe zone
    for (LatLng safeZone in _mockSafeZones) {
      double distanceInMeters = Geolocator.distanceBetween(
        userLat,
        userLng,
        safeZone.latitude,
        safeZone.longitude,
      );
      if (distanceInMeters <= 1000) {
        return true;
      }
    }
    return false;
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
          'http://10.0.2.2:5001/sentinel-sumatra-3c917/us-central1/test_sentinel_hub_check',
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
      'hazardPoints': [
        const GeoPoint(5.5550, 95.3167),
        const GeoPoint(5.5450, 95.3267),
      ],
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
        _ChatMessage(text: '...', isUser: false, isStreaming: true),
      );
      _chatLoading = true;
    });
    _scrollChatToBottom();

    final contextStr =
        'Risk Level: ${alert.riskLevel}. '
        'NDVI: ${alert.ndvi.toStringAsFixed(2)}, '
        'BSI: ${alert.bsi.toStringAsFixed(2)}, '
        'NDWI: ${alert.ndwi.toStringAsFixed(2)}, '
        'Moisture: ${alert.moisture.toStringAsFixed(2)}. '
        'AI Advice: ${alert.aiAdvice}';

    // Call Gemini REST API directly — no emulator or Cloud Function needed.
    final geminiApiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
    debugPrint(
      'DEBUG: Using Gemini key starting with: ${geminiApiKey.isEmpty ? "EMPTY" : geminiApiKey.substring(0, 12)}...',
    );
    if (geminiApiKey.isEmpty) {
      setState(() {
        _chatMessages[_chatMessages.length - 1] = _chatMessages.last.copyWith(
          text: 'GEMINI_API_KEY is missing from .env file.',
          isStreaming: false,
        );
        _chatLoading = false;
      });
      return;
    }

    try {
      final systemPrompt =
          'You are Sentinel AI, a disaster-resilience assistant for Aceh Jaya, Indonesia. '
          'You help residents understand flood and landslide risks, give safety advice, and explain satellite data. '
          'Current situation context: $contextStr '
          'Format your response strictly as regular text. Do NOT use markdown. '
          'Do NOT use bold text. Do NOT use any asterisks (*) or dashes (-). '
          'Use standard unicode dots (•) for listing items. Keep it to one short paragraph. '
          'Respond smoothly and naturally in $_selectedLanguage.';

      final response = await http
          .post(
            Uri.parse(
              'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$geminiApiKey',
            ),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {
                  'role': 'user',
                  'parts': [
                    {'text': '$systemPrompt\n\nUser: $message'},
                  ],
                },
              ],
              'generationConfig': {'maxOutputTokens': 2000},
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;

        String reply = 'No response received.';
        final candidates = data['candidates'] as List?;
        if (candidates != null && candidates.isNotEmpty) {
          final parts = candidates[0]['content']?['parts'] as List?;
          if (parts != null && parts.isNotEmpty) {
            reply = parts[0]['text'] as String? ?? reply;
            // Force remove all markdown asterisks just in case the AI hallucinates them
            reply = reply.replaceAll('**', '').replaceAll('*', '');
          }
        }
        if (mounted) {
          setState(() {
            _chatMessages[_chatMessages.length - 1] = _chatMessages.last
                .copyWith(text: reply.trim(), isStreaming: false);
            _chatLoading = false;
          });
          _scrollChatToBottom();
        }
      } else {
        throw Exception(
          'Gemini error ${response.statusCode}: ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('Chat error: $e');
      if (mounted) {
        setState(() {
          _chatMessages[_chatMessages.length - 1] = _chatMessages.last.copyWith(
            text: 'Error: ${e.toString().replaceAll('Exception: ', '')}',
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
            icon: Icon(
              Theme.of(context).brightness == Brightness.dark
                  ? Icons.light_mode
                  : Icons.dark_mode,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.amber
                  : null, // Default icon color for light mode
            ),
            tooltip: 'Toggle Theme',
            onPressed: () {
              ref.read(themeProvider.notifier).toggle();
            },
          ),
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
              heroTag: 'offline_fab',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => OfflineToolkitScreen(
                      userPosition: _userPosition,
                      safeZones: _mockSafeZones,
                      isRedZone: _isUserInRedZone(alert),
                    ),
                  ),
                );
              },
              backgroundColor: Colors.red[900],
              icon: const Icon(Icons.offline_bolt, color: Colors.white),
              label: const Text(
                'Offline SOS',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: MediaQuery.of(context).size.width - 32,
      height: 380,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D1B2A) : Colors.grey[50],
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF1A237E) : Colors.blue[200]!,
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.1),
            blurRadius: 20,
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1A237E) : Colors.blue[700],
              borderRadius: const BorderRadius.only(
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
                const SizedBox(width: 8),
                Container(
                  height: 24,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedLanguage,
                      dropdownColor: isDark
                          ? const Color(0xFF1A237E)
                          : Colors.blue[700],
                      icon: const Icon(
                        Icons.arrow_drop_down,
                        color: Colors.white70,
                        size: 16,
                      ),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                      items: _languages.map((String lang) {
                        return DropdownMenuItem<String>(
                          value: lang,
                          child: Text(lang),
                        );
                      }).toList(),
                      onChanged: (String? newValue) {
                        if (newValue != null) {
                          setState(() {
                            _selectedLanguage = newValue;
                          });
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Messages
          Expanded(
            child: _chatMessages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        '🤖 Ask me about flood risk,\nevacuation routes, or satellite data.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: isDark ? Colors.white54 : Colors.grey[600],
                          fontSize: 13,
                        ),
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
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: isDark ? const Color(0xFF1A237E) : Colors.blue[200]!,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatController,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontSize: 13,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Ask about flood risk or evacuation...',
                      hintStyle: TextStyle(
                        color: isDark ? Colors.white38 : Colors.grey[500],
                        fontSize: 12,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Align(
      alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.65,
        ),
        decoration: BoxDecoration(
          color: msg.isUser
              ? (isDark ? const Color(0xFF1A237E) : Colors.blue[600])
              : (isDark ? const Color(0xFF1B2631) : Colors.white),
          borderRadius: BorderRadius.circular(12),
          border: msg.isUser
              ? null
              : Border.all(color: isDark ? Colors.white12 : Colors.grey[300]!),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: Text(
                msg.text.isEmpty && msg.isStreaming ? '...' : msg.text,
                style: TextStyle(
                  color: msg.isUser
                      ? Colors.white
                      : (isDark ? Colors.greenAccent : Colors.teal[800]),
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
    final Set<Polyline> polylines = {};

    final Set<Circle> mapCircles = {};

    // 1. Draw Red Hazard Circles
    if (_zoneDisplayMode == ZoneDisplayMode.all ||
        _zoneDisplayMode == ZoneDisplayMode.red) {
      for (int i = 0; i < _mockHazardPoints.length; i++) {
        mapCircles.add(
          Circle(
            circleId: CircleId('hazard_$i'),
            center: _mockHazardPoints[i],
            radius: 1000.0, // 1 km danger radius around the coordinates
            fillColor: Colors.red.withValues(alpha: 0.3),
            strokeColor: Colors.red,
            strokeWidth: 3,
          ),
        );
      }
    }

    // 2. Draw Green Safe Zone Circles
    if (_zoneDisplayMode == ZoneDisplayMode.all ||
        _zoneDisplayMode == ZoneDisplayMode.green) {
      for (int i = 0; i < _mockSafeZones.length; i++) {
        mapCircles.add(
          Circle(
            circleId: CircleId('safezone_$i'),
            center: _mockSafeZones[i],
            radius: 1000.0, // 1 km safe radius
            fillColor: Colors.green.withValues(alpha: 0.3),
            strokeColor: Colors.greenAccent,
            strokeWidth: 3,
          ),
        );
      }
    }
    // 3. Draw Green Navigation Line to Nearest Safe Zone
    if (_userPosition != null &&
        (_zoneDisplayMode == ZoneDisplayMode.all ||
            _zoneDisplayMode == ZoneDisplayMode.green)) {
      LatLng nearestSafeZone = _mockSafeZones.first;
      double minDistance = double.infinity;

      for (LatLng safeZone in _mockSafeZones) {
        double dist = Geolocator.distanceBetween(
          _userPosition!.latitude,
          _userPosition!.longitude,
          safeZone.latitude,
          safeZone.longitude,
        );
        if (dist < minDistance) {
          minDistance = dist;
          nearestSafeZone = safeZone;
        }
      }

      polylines.add(
        Polyline(
          polylineId: const PolylineId('safe_route'),
          points: [
            LatLng(_userPosition!.latitude, _userPosition!.longitude),
            nearestSafeZone,
          ],
          color: Colors.greenAccent,
          width: 5,
          patterns: [
            PatternItem.dash(20),
            PatternItem.gap(10),
          ], // Dotted line effect
        ),
      );
    }

    return Column(
      children: [
        // Map (top half)
        Expanded(
          flex: 1,
          child: _isMapReady
              ? Stack(
                  children: [
                    GoogleMap(
                      initialCameraPosition: const CameraPosition(
                        target: LatLng(5.5500, 95.3167),
                        zoom: 13,
                      ),
                      circles: mapCircles,
                      polylines: polylines,
                      myLocationEnabled: true,
                      myLocationButtonEnabled: true,
                    ),
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Transform.scale(
                        scale: 0.85,
                        alignment: Alignment.topLeft,
                        child: SegmentedButton<ZoneDisplayMode>(
                          segments: const [
                            ButtonSegment(
                              value: ZoneDisplayMode.all,
                              label: Text(
                                'All Zones',
                                style: TextStyle(fontSize: 12),
                              ),
                              icon: Icon(Icons.map, size: 18),
                            ),
                            ButtonSegment(
                              value: ZoneDisplayMode.green,
                              label: Text(
                                'Safe',
                                style: TextStyle(fontSize: 12),
                              ),
                              icon: Icon(Icons.verified_user_rounded, size: 18),
                            ),
                            ButtonSegment(
                              value: ZoneDisplayMode.red,
                              label: Text(
                                'Danger',
                                style: TextStyle(fontSize: 12),
                              ),
                              icon: Icon(Icons.warning_amber_rounded, size: 18),
                            ),
                          ],
                          selected: {_zoneDisplayMode},
                          onSelectionChanged:
                              (Set<ZoneDisplayMode> newSelection) {
                                setState(() {
                                  _zoneDisplayMode = newSelection.first;
                                });
                              },
                          style: SegmentedButton.styleFrom(
                            backgroundColor: Theme.of(
                              context,
                            ).cardColor.withValues(alpha: 0.8),
                            selectedForegroundColor: Colors.white,
                            selectedBackgroundColor:
                                _zoneDisplayMode == ZoneDisplayMode.red
                                ? Colors.red[800]
                                : _zoneDisplayMode == ZoneDisplayMode.green
                                ? Colors.green[800]
                                : const Color(0xFF1A237E),
                          ),
                        ),
                      ),
                    ),
                  ],
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
                  _buildSafetyZoneCard(alert),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
                      color: isNormal
                          ? (isDark ? Colors.white : Colors.black87)
                          : Colors.redAccent,
                    ),
                  ),
                  Text(
                    'Updated: ${alert.predictedTime.toString().split('.')[0]}',
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Status: ${alert.statusMessage}',
                    style: TextStyle(
                      color: isDark ? Colors.grey : Colors.grey[600],
                    ),
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
  Widget _buildSafetyZoneCard(AlertModel alert) {
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

    final inRedZone = _isUserInRedZone(alert);
    final inGreenZone = _isUserInGreenZone();

    Color cardColor;
    IconData statusIcon;
    String statusTitle;
    String statusDesc;

    if (inRedZone) {
      cardColor = Colors.red[900]!;
      statusIcon = Icons.warning_amber_rounded;
      statusTitle = '⚠️ You Are in the Red Zone';
      statusDesc = 'Evacuate immediately! Move to higher ground now.';
    } else if (inGreenZone) {
      cardColor = Colors.green[800]!;
      statusIcon = Icons.verified_user_rounded;
      statusTitle = '✅ Optimal Safe Zone (High Ground)';
      statusDesc =
          'You are in a designated high-elevation area safely away from floods.';
    } else {
      cardColor = Colors.blueGrey[800]!;
      statusIcon = Icons.check_circle;
      statusTitle = '✅ You Are Outside the Danger Zone';
      statusDesc =
          'Your current location is not in an immediate red zone, but stay alert.';
    }

    return Card(
      color: cardColor,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Row(
              children: [
                Icon(statusIcon, color: Colors.white, size: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        statusTitle,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        statusDesc,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (inRedZone && _mockSafeZones.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _navigateToSafeZone,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.red[900],
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.navigation),
                  label: const Text(
                    'Navigate to Safe Zone',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _navigateToSafeZone() async {
    if (_userPosition == null || _mockSafeZones.isEmpty) return;

    // Find nearest safe zone
    LatLng nearestSafeZone = _mockSafeZones.first;
    double minDistance = double.infinity;

    for (LatLng safeZone in _mockSafeZones) {
      double dist = Geolocator.distanceBetween(
        _userPosition!.latitude,
        _userPosition!.longitude,
        safeZone.latitude,
        safeZone.longitude,
      );
      if (dist < minDistance) {
        minDistance = dist;
        nearestSafeZone = safeZone;
      }
    }

    final String googleMapsUrl =
        'https://www.google.com/maps/dir/?api=1&origin=${_userPosition!.latitude},${_userPosition!.longitude}&destination=${nearestSafeZone.latitude},${nearestSafeZone.longitude}&travelmode=driving';
    // Requires url_launcher
    final Uri url = Uri.parse(googleMapsUrl);
    try {
      // url_launcher requires the package import
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not launch maps: $e')));
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Satellite Analytics Cards
  // ---------------------------------------------------------------------------
  Widget _buildSatelliteCards(AlertModel alert) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            '📡 Satellite Intelligence',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: isDark ? Colors.white70 : Colors.black87,
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
                color: isDark ? const Color(0xFF1A237E) : Colors.blueAccent,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Tooltip(
      message: tooltip,
      child: Card(
        color: color.withValues(alpha: isDark ? 0.15 : 0.05),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: color.withValues(alpha: 0.5)),
        ),
        elevation: 0,
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
                        color: isDark ? Colors.white60 : Colors.black54,
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
                  color: isDark ? Colors.white : Colors.black87,
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
