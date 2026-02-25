import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/firebase_service.dart';
import '../models/alert_model.dart';

final firebaseServiceProvider = Provider<FirebaseService>((ref) {
  // FIX 4: keepAlive prevents Riverpod from destroying and recreating FirebaseService
  // (and its underlying Firestore stream) when the provider graph rebuilds.
  ref.keepAlive();
  return FirebaseService();
});

final alertStreamProvider = StreamProvider<AlertModel>((ref) {
  final firebaseService = ref.watch(firebaseServiceProvider);
  return firebaseService.alertsStream;
});
