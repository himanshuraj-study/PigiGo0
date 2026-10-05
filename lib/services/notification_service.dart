import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Must be top-level function for background message handling
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // FCM handles background notification display automatically on Android
}

class NotificationService {
  // Singleton so we only initialize once
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final _messaging = FirebaseMessaging.instance;
  final _localNotifications = FlutterLocalNotificationsPlugin();

  // Must match channel_id in your Edge Function
  static const _channel = AndroidNotificationChannel(
    'pigigo_high_importance',
    'PigiGo Notifications',
    description: 'Likes, comments, follows and messages',
    importance: Importance.high,
    playSound: true,
  );

  Future<void> initialize() async {
    // 1. Request permission (required for Android 13+)
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      // User denied — notifications won't work but app still runs fine
      return;
    }

    // 2. Create Android notification channel
    await _localNotifications
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    // 3. Initialize local notifications plugin
    const androidSettings =
    AndroidInitializationSettings('@mipmap/ic_launcher');
    await _localNotifications.initialize(
      const InitializationSettings(android: androidSettings),
    );

    // 4. Show heads-up banner when app is in foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notification = message.notification;
      final android = message.notification?.android;
      if (notification != null && android != null) {
        _localNotifications.show(
          notification.hashCode,
          notification.title,
          notification.body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              _channel.id,
              _channel.name,
              channelDescription: _channel.description,
              importance: Importance.high,
              priority: Priority.high,
              icon: '@mipmap/ic_launcher',
            ),
          ),
        );
      }
    });

    // 5. Register background message handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // 6. Save this device's FCM token to Supabase
    await _saveTokenToSupabase();

    // 7. Refresh token automatically if FCM rotates it
    _messaging.onTokenRefresh.listen(_upsertToken);
  }

  Future<void> _saveTokenToSupabase() async {
    final user = Supabase.instance.client.auth.currentUser;
    debugPrint("USER = ${user?.id}");

    if (user == null) {
      debugPrint("NO USER FOUND");
      return;
    }

    final token = await _messaging.getToken();
    debugPrint("FCM TOKEN = $token");

    if (token == null) {
      debugPrint("TOKEN IS NULL");
      return;
    }

    await _upsertToken(token);
    debugPrint("TOKEN SAVED SUCCESSFULLY");
  }

  Future<void> _upsertToken(String token) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    // Save token to fcm_tokens table (one row per user)
    await Supabase.instance.client.from('fcm_tokens').upsert(
      {
        'user_id': user.id,
        'token': token,
        'updated_at': DateTime.now().toIso8601String(),
      },
      onConflict: 'user_id',
    );
  }

  /// Call this on logout to prevent ghost notifications after sign out
  Future<void> removeToken() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    await Supabase.instance.client
        .from('fcm_tokens')
        .delete()
        .eq('user_id', user.id);

    await _messaging.deleteToken();
  }

  /// Call this anywhere to trigger a push notification via Edge Function.
  /// Fire-and-forget — notification failure never crashes the main action.
  static Future<void> send({
    required String type,       // 'like', 'comment', 'follow', 'message'
    required String actorId,    // who did the action
    required String targetUserId, // who should receive the notification
    String? postId,             // optional, for like/comment
  }) async {
    // Never notify yourself
    if (actorId == targetUserId) return;

    try {
      await Supabase.instance.client.functions.invoke(
        'send-notification',
        body: {
          'type': type,
          'actorId': actorId,
          'targetUserId': targetUserId,
          if (postId != null) 'postId': postId,
        },
      );
    } catch (_) {
      // Silently ignore — notification errors must never break the app
    }
  }
}
