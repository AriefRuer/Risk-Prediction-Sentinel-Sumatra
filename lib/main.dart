import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'screens/skeleton_screen.dart';
import 'firebase_options.dart';
import 'services/firebase_service.dart';
import 'providers/theme_provider.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint("Handling a background message: \${message.messageId}");
}

// Global instance for triggering local mock notifications
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables for the frontend
  await dotenv.load(fileName: ".env");

  // Initialize Local Notifications Workaround
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );
  await flutterLocalNotificationsPlugin.initialize(
    settings: initializationSettings,
  );

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // Initialize Push Notifications immediately upon startup
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    final firebaseService = FirebaseService();
    await firebaseService.initNotifications();
  } catch (e) {
    debugPrint(
      'Firebase init failed: \$e',
    ); // Handled for UI testing without full config
  }
  runApp(const ProviderScope(child: SentinelSumatraApp()));
}

class SentinelSumatraApp extends ConsumerWidget {
  const SentinelSumatraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);

    return MaterialApp(
      title: 'Sentinel Sumatra',
      themeMode: themeMode,
      theme: ThemeData(
        brightness: Brightness.light,
        primaryColor: Colors.deepPurple,
        scaffoldBackgroundColor: Colors.grey[100],
        cardTheme: const CardThemeData(color: Colors.white),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: Colors.deepPurple,
        scaffoldBackgroundColor: const Color(0xFF121212),
        cardTheme: CardThemeData(color: Colors.grey[900]),
      ),
      home: const SkeletonScreen(),
    );
  }
}
