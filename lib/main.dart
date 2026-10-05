import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/auth/login_screen.dart';
import 'screens/feed/home_screen.dart';
import 'services/notification_service.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Firebase init error: $e');
  }

  await Supabase.initialize(
    url: 'https://jimklteljufjvbuavpmr.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImppbWtsdGVsanVmanZidWF2cG1yIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ3OTg5OTUsImV4cCI6MjA5MDM3NDk5NX0.0DW_KFCpHpiRGQomQjuJoTVLqlU9Xd9RarBZpBBLcFY',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PigiGo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();

    supabase.auth.onAuthStateChange.listen((data) async {
      if (!mounted) return;
      final event = data.event;

      if (event == AuthChangeEvent.signedIn) {
        try {
          await NotificationService().initialize();
        } catch (e) {
          debugPrint('Notification init error: $e');
        }

        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const HomeScreen()),
                (route) => false,
          );
        }
      } else if (event == AuthChangeEvent.signedOut) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
              (route) => false,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = supabase.auth.currentSession;

    if (session != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          NotificationService().initialize();
        } catch (e) {
          debugPrint('Notification init error: $e');
        }
      });
      return const HomeScreen();
    }

    return const LoginScreen();
  }
}