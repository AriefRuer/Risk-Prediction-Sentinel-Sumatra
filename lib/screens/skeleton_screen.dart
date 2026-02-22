import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:html' as html;
import '../providers/alert_provider.dart';
import '../models/alert_model.dart';

class SkeletonScreen extends ConsumerStatefulWidget {
  const SkeletonScreen({super.key});

  @override
  ConsumerState<SkeletonScreen> createState() => _SkeletonScreenState();
}

class _SkeletonScreenState extends ConsumerState<SkeletonScreen> {
  final TextEditingController _chatController = TextEditingController();
  bool _isMapReady = false;

  @override
  void initState() {
    super.initState();
    _injectGoogleMapsApiKey();
  }

  void _injectGoogleMapsApiKey() {
    final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'];
    if (apiKey == null ||
        apiKey.isEmpty ||
        apiKey == "PASTE_YOUR_API_KEY_HERE") {
      debugPrint("Warning: No Google Maps API Key found in .env");
      setState(() => _isMapReady = true); // Allow to render gray box
      return;
    }

    final script = html.ScriptElement()
      ..src = 'https://maps.googleapis.com/maps/api/js?key=$apiKey'
      ..type = 'text/javascript';

    script.onLoad.listen((_) {
      if (mounted) {
        setState(() => _isMapReady = true);
      }
    });

    html.document.head?.append(script);
  }

  void _sendMockAlert() {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Triggering AI Pipeline...')),
      );
    }

    try {
      final request = html.HttpRequest();
      request.open(
        'GET',
        'http://127.0.0.1:5001/sentinel-sumatra-3c917/us-central1/test_sentinel_hub_check',
      );

      request.onLoad.listen((event) {
        if (mounted) {
          if (request.status == 200) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('AI Successfully Triggered! Database syncing...'),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('AI Trigger Failed: ${request.status}')),
            );
          }
        }
      });

      request.onError.listen((event) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to connect to Emulator. Is it running?'),
            ),
          );
        }
      });

      request.send();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to trigger AI: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final alertAsyncValue = ref.watch(alertStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Systems Check'),
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
    );
  }

  Widget _buildBody(AlertModel alert) {
    final List<LatLng> hazardZone = const [
      LatLng(5.5450, 95.3100),
      LatLng(5.5450, 95.3350),
      LatLng(5.5650, 95.3350),
      LatLng(5.5650, 95.3100),
    ];

    final Set<Polygon> polygons = {
      Polygon(
        polygonId: const PolygonId('risk_area'),
        points: hazardZone,
        fillColor: Colors.red.withValues(alpha: 0.3),
        strokeColor: Colors.red,
        strokeWidth: 2,
      ),
    };

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
        Expanded(
          flex: 1,
          child: _isMapReady
              ? GoogleMap(
                  initialCameraPosition: const CameraPosition(
                    target: LatLng(5.5500, 95.3167),
                    zoom: 13,
                  ),
                  polygons: alert.riskLevel == 'Critical' ? polygons : {},
                  polylines: polylines,
                )
              : const Center(child: CircularProgressIndicator()),
        ),
        Expanded(
          flex: 1,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildStatusCard(alert),
                const SizedBox(height: 8),
                Expanded(child: _buildAITerminal(alert)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusCard(AlertModel alert) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Risk Level: ${alert.riskLevel}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: alert.riskLevel == 'Critical'
                        ? Colors.redAccent
                        : Colors.white,
                  ),
                ),
                Text(
                  'Predicted: ${alert.predictedTime.toString().split('.')[0]}',
                ),
                const SizedBox(height: 4),
                Text(
                  'Status: ${alert.statusMessage}',
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
            Column(
              children: [
                const Text(
                  'Connectivity',
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
                  alert.isFromCache ? 'Cached Data' : 'Live Sync',
                  style: const TextStyle(fontSize: 10),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAITerminal(AlertModel alert) {
    return Card(
      color: Colors.black87,
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'AI Terminal',
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
            ),
            const Divider(color: Colors.grey),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  '> ${alert.aiAdvice}',
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
            const Divider(color: Colors.grey),
            Row(
              children: [
                const Text(
                  '>',
                  style: TextStyle(
                    color: Colors.greenAccent,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _chatController,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'monospace',
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Enter query for AI framework...',
                      hintStyle: TextStyle(color: Colors.white30),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    onSubmitted: (_) => _submitChat(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.greenAccent),
                  onPressed: _submitChat,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _submitChat() {
    if (_chatController.text.isNotEmpty) {
      ref.read(firebaseServiceProvider).sendChatMessage(_chatController.text);
      _chatController.clear();
    }
  }
}
