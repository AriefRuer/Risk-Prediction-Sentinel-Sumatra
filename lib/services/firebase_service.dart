import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../models/alert_model.dart';

class FirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  FirebaseService() {
    _firestore.settings = const Settings(persistenceEnabled: true);
  }

  Future<void> initNotifications() async {
    try {
      NotificationSettings settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        debugPrint('User granted push notification permission');
      }

      if (!kIsWeb) {
        // FCM Topics are natively supported on Android/iOS, but not on Web.
        await _messaging.subscribeToTopic('disaster_alerts');
        debugPrint('Subscribed to FCM topic: disaster_alerts');
      } else {
        debugPrint(
          'FCM Topics are not supported on Web. Background pushes disabled for Web prototype.',
        );
      }

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('Foreground Push Received: \${message.notification?.title}');
      });
    } catch (e) {
      debugPrint('FCM Init Error: \$e');
    }
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
