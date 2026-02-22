import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/alert_model.dart';

class FirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  FirebaseService() {
    _firestore.settings = const Settings(persistenceEnabled: true);
  }

  Stream<AlertModel> get alertsStream {
    return _firestore
        .collection('alerts')
        .doc('aceh_jaya')
        .snapshots()
        .map((document) => AlertModel.fromFirestore(document));
  }

  Future<void> sendChatMessage(String message) async {
    await _firestore
        .collection('alerts')
        .doc('aceh_jaya')
        .collection('chat')
        .add({
      'message': message,
      'timestamp': FieldValue.serverTimestamp(),
      'sender': 'user',
    });
  }
}
