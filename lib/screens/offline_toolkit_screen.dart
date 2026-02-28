import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class OfflineToolkitScreen extends StatefulWidget {
  final Position? userPosition;
  final List<LatLng> safeZones;
  final bool isRedZone;

  const OfflineToolkitScreen({
    super.key,
    required this.userPosition,
    required this.safeZones,
    required this.isRedZone,
  });

  @override
  State<OfflineToolkitScreen> createState() => _OfflineToolkitScreenState();
}

class _OfflineToolkitScreenState extends State<OfflineToolkitScreen> {
  bool _isFlashing = false;
  Timer? _flashTimer;
  Color _flashColor = Colors.red;

  @override
  void dispose() {
    _flashTimer?.cancel();
    super.dispose();
  }

  void _toggleSosBeacon() {
    setState(() {
      _isFlashing = !_isFlashing;
    });

    if (_isFlashing) {
      // Flashes between red and white every 300ms
      _flashTimer = Timer.periodic(const Duration(milliseconds: 300), (timer) {
        setState(() {
          _flashColor = _flashColor == Colors.red ? Colors.white : Colors.red;
        });
      });
    } else {
      _flashTimer?.cancel();
      _flashTimer = null;
    }
  }

  Future<void> _sendSosSms() async {
    String msg = "SOS! Emergency assistance needed.\n";
    if (widget.userPosition != null) {
      msg +=
          "My raw GPS Coordinates are: ${widget.userPosition!.latitude}, ${widget.userPosition!.longitude}\n";
    } else {
      msg += "My GPS is currently undetected.\n";
    }
    if (widget.isRedZone) {
      msg += "I am currently trapped in a High-Risk Hazard Zone.";
    } else {
      msg += "I am outside the designated hazard zone but need help.";
    }

    final Uri smsUri = Uri(
      scheme: 'sms',
      path:
          '', // leave empty to prompt user to enter contact manually, or add default emergency numbers like '911'/'112'
      queryParameters: <String, String>{'body': msg},
    );

    try {
      await launchUrl(smsUri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not open SMS: $e')));
      }
    }
  }

  Widget _buildCompassDirection() {
    if (widget.userPosition == null || widget.safeZones.isEmpty) {
      return const Text("Location or Safe Zones unavailable.");
    }

    // Find nearest safe zone
    LatLng nearestSafeZone = widget.safeZones.first;
    double minDistance = double.infinity;
    for (LatLng safeZone in widget.safeZones) {
      double dist = Geolocator.distanceBetween(
        widget.userPosition!.latitude,
        widget.userPosition!.longitude,
        safeZone.latitude,
        safeZone.longitude,
      );
      if (dist < minDistance) {
        minDistance = dist;
        nearestSafeZone = safeZone;
      }
    }

    // Calculate heading/bearing
    double bearing = Geolocator.bearingBetween(
      widget.userPosition!.latitude,
      widget.userPosition!.longitude,
      nearestSafeZone.latitude,
      nearestSafeZone.longitude,
    );

    String direction = _getCompassDirection(bearing);
    String distString = minDistance < 1000
        ? "${minDistance.round()} meters"
        : "${(minDistance / 1000).toStringAsFixed(1)} km";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.explore, color: Colors.blueAccent),
            const SizedBox(width: 8),
            Text(
              "Nearest Safe Zone: $distString $direction",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          "If maps fail to load, use a physical compass or the sun to walk in this general heading until you reach higher ground.",
          style: TextStyle(fontSize: 13, color: Colors.grey),
        ),
      ],
    );
  }

  String _getCompassDirection(double bearing) {
    if (bearing < 0) bearing += 360;
    if (bearing >= 337.5 || bearing < 22.5) return 'North';
    if (bearing >= 22.5 && bearing < 67.5) return 'Northeast';
    if (bearing >= 67.5 && bearing < 112.5) return 'East';
    if (bearing >= 112.5 && bearing < 157.5) return 'Southeast';
    if (bearing >= 157.5 && bearing < 202.5) return 'South';
    if (bearing >= 202.5 && bearing < 247.5) return 'Southwest';
    if (bearing >= 247.5 && bearing < 292.5) return 'West';
    if (bearing >= 292.5 && bearing < 337.5) return 'Northwest';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    // If flashing, override the whole screen
    if (_isFlashing) {
      return GestureDetector(
        onTap: _toggleSosBeacon,
        child: Scaffold(
          backgroundColor: _flashColor,
          body: Center(
            child: Text(
              'TAP ANYWHERE TO STOP SOS',
              style: TextStyle(
                color: _flashColor == Colors.red ? Colors.white : Colors.black,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("🚨 Offline Toolkit"),
        backgroundColor: Colors.red[900],
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Tools available without internet connection.",
              style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 20),

            // Compass & Directions
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: _buildCompassDirection(),
              ),
            ),
            const SizedBox(height: 16),

            // SMS Broadcast
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton.icon(
                onPressed: _sendSosSms,
                icon: const Icon(Icons.sms),
                label: const Text(
                  "Draft SOS SMS via Cell Network",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[800],
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Flasher
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton.icon(
                onPressed: _toggleSosBeacon,
                icon: const Icon(Icons.flashlight_on),
                label: const Text(
                  "Activate Visual SOS Beacon",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[800],
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Offline Guide
            const Text(
              "Basic Survival Protocol",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            const ListTile(
              leading: Icon(Icons.warning, color: Colors.orange),
              title: Text("1. Do NOT walk through flowing water."),
              subtitle: Text(
                "Just 6 inches of moving water can knock you down.",
              ),
            ),
            const ListTile(
              leading: Icon(Icons.directions_car, color: Colors.orange),
              title: Text("2. Do NOT drive through flooded roads."),
              subtitle: Text(
                "Almost half of all flash flood deaths happen in vehicles.",
              ),
            ),
            const ListTile(
              leading: Icon(Icons.house, color: Colors.orange),
              title: Text("3. Move to the highest level of a sturdy building."),
              subtitle: Text(
                "Only go to the roof if necessary, and signal for help.",
              ),
            ),
            const ListTile(
              leading: Icon(Icons.electrical_services, color: Colors.orange),
              title: Text("4. Disconnect utilities."),
              subtitle: Text(
                "Turn off electricity and gas at the main switches if instructed or if water enters your home.",
              ),
            ),
          ],
        ),
      ),
    );
  }
}
