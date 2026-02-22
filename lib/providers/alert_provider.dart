import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/firebase_service.dart';
import '../models/alert_model.dart';

final firebaseServiceProvider = Provider<FirebaseService>((ref) {
  return FirebaseService();
});

final alertStreamProvider = StreamProvider<AlertModel>((ref) {
  final firebaseService = ref.watch(firebaseServiceProvider);
  return firebaseService.alertsStream;
});
