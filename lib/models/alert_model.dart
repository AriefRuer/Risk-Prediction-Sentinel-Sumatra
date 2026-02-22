import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class AlertModel {
  final String riskLevel;
  final DateTime predictedTime;
  final List<LatLng> safeRoutePoints;
  final String aiAdvice;
  final String statusMessage;
  final bool isFromCache;

  AlertModel({
    required this.riskLevel,
    required this.predictedTime,
    required this.safeRoutePoints,
    required this.aiAdvice,
    required this.statusMessage,
    this.isFromCache = false,
  });

  factory AlertModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic>? data = doc.data() as Map<String, dynamic>?;

    if (data == null) {
      return AlertModel(
        riskLevel: 'Unknown',
        predictedTime: DateTime.now(),
        safeRoutePoints: [],
        aiAdvice: 'No data',
        statusMessage: 'No data',
      );
    }

    List<LatLng> points = [];
    if (data['safeRoutePoints'] != null) {
      for (var point in data['safeRoutePoints']) {
        if (point is GeoPoint) {
          points.add(LatLng(point.latitude, point.longitude));
        }
      }
    }

    return AlertModel(
      riskLevel: data['riskLevel'] ?? 'Unknown',
      predictedTime:
          (data['predictedTime'] as Timestamp?)?.toDate() ?? DateTime.now(),
      safeRoutePoints: points,
      aiAdvice: data['aiAdvice'] ?? 'No advice available.',
      statusMessage: data['statusMessage'] ?? 'Awaiting status...',
      isFromCache: doc.metadata.isFromCache,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'riskLevel': riskLevel,
      'predictedTime': Timestamp.fromDate(predictedTime),
      'safeRoutePoints': safeRoutePoints
          .map((e) => GeoPoint(e.latitude, e.longitude))
          .toList(),
      'aiAdvice': aiAdvice,
      'statusMessage': statusMessage,
    };
  }
}
