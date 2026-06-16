import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class NotificationItem {
  final int id;
  final String title;
  final String body;
  final String? imageUrl;
  final DateTime timestamp;

  NotificationItem({
    required this.id,
    required this.title,
    required this.body,
    this.imageUrl,
    required this.timestamp,
  });
}

class NotificationService extends ChangeNotifier {
  static final FlutterLocalNotificationsPlugin _localNotifs =
      FlutterLocalNotificationsPlugin();

  WebSocketChannel? _channel;
  bool _connected = false;
  String _status = 'Disconnected';
  String? _serverUrl;
  final List<NotificationItem> notifications = [];

  bool get connected => _connected;
  String get status => _status;
  String? get serverUrl => _serverUrl;

  static Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _localNotifs.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
  }

  Future<void> requestPermission() async {
    await _localNotifs
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _localNotifs
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  Future<bool> connect(String url) async {
    if (_connected) await disconnect();

    _status = 'Connecting...';
    notifyListeners();

    try {
      _serverUrl = url.trim();
      _channel = WebSocketChannel.connect(Uri.parse(_serverUrl!));
      await _channel!.ready;

      _connected = true;
      _status = 'Connected';
      notifyListeners();

      _channel!.stream.listen(
        _onMessage,
        onError: (_) => _onDisconnected(),
        onDone: _onDisconnected,
      );
      return true;
    } catch (e) {
      _connected = false;
      _status = 'Connection failed';
      _channel = null;
      notifyListeners();
      return false;
    }
  }

  Future<void> disconnect() async {
    await _channel?.sink.close();
    _channel = null;
    _connected = false;
    _status = 'Disconnected';
    notifyListeners();
  }

  void _onMessage(dynamic raw) {
    try {
      final data = jsonDecode(raw as String) as Map<String, dynamic>;
      if (data['type'] == 'notification') {
        final item = NotificationItem(
          id: (data['id'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
          title: data['title'] as String,
          body: data['body'] as String,
          imageUrl: data['imageUrl'] as String?,
          timestamp: data['timestamp'] != null
              ? DateTime.parse(data['timestamp'] as String)
              : DateTime.now(),
        );
        notifications.insert(0, item);
        _showNotification(item);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('WS message error: $e');
    }
  }

  Future<void> _showNotification(NotificationItem item) async {
    const android = AndroidNotificationDetails(
      'notime_ch',
      'Notime',
      channelDescription: 'Notifications from Notime dashboard',
      importance: Importance.max,
      priority: Priority.high,
    );
    const ios = DarwinNotificationDetails();
    await _localNotifs.show(
      item.id % 10000,
      item.title,
      item.body,
      const NotificationDetails(android: android, iOS: ios),
    );
  }

  void _onDisconnected() {
    _connected = false;
    _status = 'Disconnected';
    _channel = null;
    notifyListeners();
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
