import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'p2p_socket_server.dart';
import 'contact_service.dart';

class BackgroundServiceHelper {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  /// فحص دقيق لوجود اتصال فعلي بشبكة واي فاي محلياً من خلال عناوين الـ IP
  static Future<bool> isWifiActive() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (!addr.isLoopback) {
            return true;
          }
        }
      }
    } catch (_) {}
    return false;
  }

  /// initialize background service and notifications
  static Future<void> initializeService() async {
    final service = FlutterBackgroundService();

    // 1. تهيئة الإشعارات المحلية
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    await _notificationsPlugin.initialize(initializationSettings);

    // إنشاء قناة إشعارات عالية الأهمية
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'p2p_call_channel',
      'المكالمات والرسائل الواردة',
      description: 'إشعارات المكالمات والرسائل الواردة في الشبكة المحلية',
      importance: Importance.max,
      playSound: true,
    );

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // 2. إعداد خدمة الخلفية (تعطيل isForegroundMode المباشر لمنع الإشعار الإجباري)
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: false, // 🛑 منع إظهار الإشعار عند بداية التهيئة تلقائياً
        notificationChannelId: 'p2p_call_channel',
        initialNotificationTitle: 'خدمة الاتصال المحلي تعمل',
        initialNotificationContent: 'جاري الاستماع للرسائل والمكالمات الواردة...',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );

    // 📡 3. فحص ومراقبة الواي فاي
    _setupWifiListener(service);
  }

  /// مراقبة حالة الواي فاي وتدقيق الاتصال لتشغيل أو إيقاف الخدمة والإشعار
  static void _setupWifiListener(FlutterBackgroundService service) {
    // فحص فوري وقت التهيئة
    checkAndToggleService(service);

    Connectivity().onConnectivityChanged.listen((_) async {
      await checkAndToggleService(service);
    });
  }

  /// دالة التحقق والتأكد من حالة الخدمة
  static Future<void> checkAndToggleService(FlutterBackgroundService service) async {
    bool hasWifi = await isWifiActive();
    bool isRunning = await service.isRunning();

    if (hasWifi && !isRunning) {
      // 🟢 يوجد واي فاي والخدمة متوقفة -> تشغيل الخدمة
      await service.startService();
    } else if (!hasWifi && isRunning) {
      // 🔴 مفصول عن الواي فاي والخدمة تعمل -> إيقاف الخدمة وإخفاء الإشعار
      service.invoke('stopService');
    }
  }

  @pragma('vm:entry-point')
  static Future<bool> onIosBackground(ServiceInstance service) async {
    WidgetsFlutterBinding.ensureInitialized();
    return true;
  }

  @pragma('vm:entry-point')
  static void onStart(ServiceInstance service) async {
    DartPluginRegistrant.ensureInitialized();

    // ⚡ التأكد الفوري داخل الخيط: إن لم يوجد واي فاي نغلق الخدمة فوراً قبل إظهار أي إشعار
    bool active = await isWifiActive();
    if (!active) {
      if (service is AndroidServiceInstance) {
        service.stopSelf();
      }
      return;
    }

    // تحويل الخدمة لـ Foreground وإظهار الإشعار فقط بعد ثبوت وجود الواي فاي
    if (service is AndroidServiceInstance) {
      service.setAsForegroundService();
    }

    final P2PSocketServer socketServer = P2PSocketServer();

    // تشغيل سيرفر الستريم والاستماع بالخلفية على المنفذ 4040
    await socketServer.startServer(
      4040,
      onRequestConnection: (callerId, callerName, socket) async {
        String name = await ContactService.getContactName(callerId) ?? callerName;
        showNotification(
          id: 101,
          title: 'مكالمة واردة 📞',
          body: 'اتصال وارد من: $name',
        );
      },
      onMessageReceived: (senderIp, msg) async {
        showNotification(
          id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          title: 'رسالة جديدة 💬',
          body: msg,
        );
      },
    );

    // 🔄 فحص دوري حاسم كل 3 ثوانٍ لإغلاق الإشعار فور فصل الواي فاي
    Timer.periodic(const Duration(seconds: 3), (timer) async {
      bool isConnected = await isWifiActive();
      if (!isConnected) {
        timer.cancel();
        socketServer.stop();
        if (service is AndroidServiceInstance) {
          service.stopSelf();
        }
      }
    });

    service.on('stopService').listen((event) {
      socketServer.stop();
      if (service is AndroidServiceInstance) {
        service.stopSelf();
      }
    });
  }

  /// إظهار إشعار منبثق علوي
  static Future<void> showNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'p2p_call_channel',
      'المكالمات والرسائل الواردة',
      channelDescription: 'إشعارات المكالمات والرسائل الواردة في الشبكة المحلية',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
      fullScreenIntent: true,
    );

    const NotificationDetails platformDetails =
        NotificationDetails(android: androidDetails);

    await _notificationsPlugin.show(
      id,
      title,
      body,
      platformDetails,
    );
  }
}
