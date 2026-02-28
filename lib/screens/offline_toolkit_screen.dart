import 'dart:async';
import 'dart:ui';
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

  Future<void> _sendSosSms(String phoneNumber) async {
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
      path: phoneNumber,
      queryParameters: <String, String>{'body': msg},
    );

    try {
      if (mounted) Navigator.pop(context); // Close the bottom sheet
      await launchUrl(smsUri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not open SMS: $e')));
      }
    }
  }

  void _showEmergencyContactsDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  "Select Emergency Service",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  "Who do you want to send your GPS coordinates to?",
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 24),
                _buildContactTile(
                  title: "112 - National Command Center",
                  subtitle: "General Emergencies & Dispatch",
                  icon: Icons.local_hospital_rounded,
                  color: Colors.redAccent,
                  phoneNumber: "112",
                ),
                _buildContactTile(
                  title: "110 - National Police",
                  subtitle: "Immediate threat or crime",
                  icon: Icons.local_police_rounded,
                  color: Colors.blueAccent,
                  phoneNumber: "110",
                ),
                _buildContactTile(
                  title: "115 - Search & Rescue (BASARNAS)",
                  subtitle: "Floods, landslides, missing persons",
                  icon: Icons.support_rounded,
                  color: Colors.orangeAccent,
                  phoneNumber: "115",
                ),
                _buildContactTile(
                  title: "Custom Contact",
                  subtitle: "Select from your phonebook",
                  icon: Icons.person_search_rounded,
                  color: Colors.purpleAccent,
                  phoneNumber: "", // Leaves path blank so OS asks for contact
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildContactTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required String phoneNumber,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      elevation: 0,
      color: isDark
          ? Colors.white.withOpacity(0.05)
          : Colors.black.withOpacity(0.03),
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.2),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
        onTap: () => _sendSosSms(phoneNumber),
      ),
    );
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
    // Apply a standard circuitous winding factor (1.35) to convert straight-line to estimated road distance
    double estimatedRoadDistance = minDistance * 1.35;
    String distString = estimatedRoadDistance < 1000
        ? "~${estimatedRoadDistance.round()} meters"
        : "~${(estimatedRoadDistance / 1000).toStringAsFixed(1)} km";

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

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          "🚨 Offline Toolkit",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: (isDark ? const Color(0xFF0F172A) : Colors.white)
            .withValues(alpha: 0.7),
        elevation: 0,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.transparent),
          ),
        ),
        foregroundColor: isDark ? Colors.white : Colors.red[800],
        iconTheme: IconThemeData(
          color: isDark ? Colors.white : Colors.red[800],
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [const Color(0xFF0F172A), const Color(0xFF1E293B)]
                : [const Color(0xFFF8FAFC), const Color(0xFFE2E8F0)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: 20.0,
              vertical: 24.0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Tools available without internet connection.",
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 24),

                // Compass & Directions
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardTheme.color,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF334155)
                          : const Color(0xFFE2E8F0),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(20.0),
                  child: _buildCompassDirection(),
                ),
                const SizedBox(height: 24),

                // SMS Broadcast
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _showEmergencyContactsDialog,
                    icon: const Icon(Icons.sms_rounded),
                    label: const Text("Draft SOS SMS via Cell Network"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDark
                          ? const Color(0xFF3B82F6)
                          : const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Flasher
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _toggleSosBeacon,
                    icon: const Icon(Icons.flashlight_on_rounded),
                    label: const Text("Activate Visual SOS Beacon"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626), // Modern red
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Offline Guide
                Text(
                  "Basic Survival Protocol",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : const Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardTheme.color?.withValues(
                          alpha: isDark ? 0.3 : 0.6,
                        ),
                        border: Border.all(
                          color: Colors.white.withValues(
                            alpha: isDark ? 0.1 : 0.4,
                          ),
                        ),
                      ),
                      child: Column(
                        children: [
                          const ListTile(
                            leading: Icon(
                              Icons.warning_amber_rounded,
                              color: Color(0xFFF59E0B),
                            ),
                            title: Text(
                              "1. Do NOT walk through flowing water.",
                            ),
                            subtitle: Text(
                              "Just 6 inches of moving water can knock you down.",
                            ),
                          ),
                          Divider(
                            color: Colors.white.withValues(
                              alpha: isDark ? 0.1 : 0.3,
                            ),
                            height: 1,
                          ),
                          const ListTile(
                            leading: Icon(
                              Icons.directions_car_rounded,
                              color: Color(0xFFF59E0B),
                            ),
                            title: Text(
                              "2. Do NOT drive through flooded roads.",
                            ),
                            subtitle: Text(
                              "Almost half of all flash flood deaths happen in vehicles.",
                            ),
                          ),
                          Divider(
                            color: Colors.white.withValues(
                              alpha: isDark ? 0.1 : 0.3,
                            ),
                            height: 1,
                          ),
                          const ListTile(
                            leading: Icon(
                              Icons.house_siding_rounded,
                              color: Color(0xFFF59E0B),
                            ),
                            title: Text(
                              "3. Move to the highest level of a sturdy building.",
                            ),
                            subtitle: Text(
                              "Only go to the roof if necessary, and signal for help.",
                            ),
                          ),
                          Divider(
                            color: Colors.white.withValues(
                              alpha: isDark ? 0.1 : 0.3,
                            ),
                            height: 1,
                          ),
                          const ListTile(
                            leading: Icon(
                              Icons.electrical_services_rounded,
                              color: Color(0xFFF59E0B),
                            ),
                            title: Text("4. Disconnect utilities."),
                            subtitle: Text(
                              "Turn off electricity and gas at the main switches if instructed or if water enters your home.",
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
