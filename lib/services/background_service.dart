import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:web_socket_channel/io.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'p2p_socket_server.dart';
import 'contact_service.dart';

/// معالج المهام المستمرة بالخلفية لمنع خمول المعالج وإبقاء السيرفر نشطاً
class BackgroundTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await WakelockPlus.enable();
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {
    // إبقاء الاتصالات والأنشطة حية بالخلفية
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    await WakelockPlus.disable();
  }
}

@pragma('vm:entry-point')
void startForegroundTaskCallback() {
  FlutterForegroundTask.setTaskHandler(BackgroundTaskHandler());
}

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

  /// ⚡ تهيئة خدمة flutter_foreground_task للإشعارات الدائمة والـ WakeLock
  static void initService() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'p2p_call_channel',
        channelName: 'خدمة اتصالات P2P',
        channelDescription: 'إبقاء اتصال التطبيق نشطاً للاستقبال',
        channelImportance: NotificationChannelImportance.MAX, // 🛠️ استخدام NotificationChannelImportance
        priority: NotificationPriority.MAX,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  /// ⚡ بدء خدمة التشغيل المستمر في الخلفية
  static Future<bool> startService() async {
    if (await FlutterForegroundTask.isRunningService) {
      return true;
    }

    final result = await FlutterForegroundTask.startService(
      serviceId: 257,
      notificationTitle: 'الاتصال اللاسلكي محلياً نشط',
      notificationText: 'التطبيق جاهز لاستقبال الاتصالات والرسائل الواردة',
      notificationIcon: const NotificationIcon(
        metaDataName: 'ic_launcher', // 🛠️ استخدام metaDataName بدلاً من name
      ),
      callback: startForegroundTaskCallback,
    );

    return result is ServiceRequestSuccess;
  }

  /// ⚡ إيقاف خدمة التشغيل المستمر
  static Future<bool> stopForegroundService() async {
    final result = await FlutterForegroundTask.stopService();
    return result is ServiceRequestSuccess;
  }

  /// initialize background service and notifications
  static Future<void> initializeService() async {
    initService(); // تهيئة إعدادات المستمر

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
      await startService(); // تشغيل الوقاية المستمرة من النوم
    } else if (!hasWifi && isRunning) {
      // 🔴 مفصول عن الواي فاي والخدمة تعمل -> إيقاف الخدمة وإخفاء الإشعار
      service.invoke('stopService');
      await stopForegroundService();
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

    // ⚡ الاتصال بسيرفر اللابتوب المركزي (WebSocket) لإدارة الأرقام والمكالمات
    IOWebSocketChannel? pbxChannel;
    _connectToLaptopPBX().then((channel) {
      pbxChannel = channel;
    });

    // 🔄 فحص دوري حاسم كل 3 ثوانٍ لإغلاق الإشعار فور فصل الواي فاي
    Timer.periodic(const Duration(seconds: 3), (timer) async {
      bool isConnected = await isWifiActive();
      if (!isConnected) {
        timer.cancel();
        socketServer.stop();
        pbxChannel?.sink.close();
        if (service is AndroidServiceInstance) {
          service.stopSelf();
        }
      }
    });

    service.on('stopService').listen((event) {
      socketServer.stop();
      pbxChannel?.sink.close();
      if (service is AndroidServiceInstance) {
        service.stopSelf();
      }
    });
  }

  /// ⚡ دالة مساعدة للاتصال بسيرفر اللابتوب وتسجيل الجوال برقم داخلي
  static Future<IOWebSocketChannel?> _connectToLaptopPBX() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? serverIp = prefs.getString('server_ip');
      if (serverIp == null || serverIp.isEmpty) return null;

      final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      String deviceId = 'unknown_device';
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        deviceId = androidInfo.id;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        deviceId = iosInfo.identifierForVendor ?? 'ios_device';
      }

      final channel = IOWebSocketChannel.connect(Uri.parse('ws://$serverIp:8765'));

      // إرسال طلب التسجيل
      channel.sink.add(jsonEncode({
        'type': 'REGISTER',
        'device_id': deviceId,
        'name': 'جوال محلي',
      }));

      // الاستماع للإشعارات الواردة من السيرفر
      channel.stream.listen((message) async {
        final data = jsonDecode(message);
        if (data['type'] == 'INCOMING_CALL') {
          String fromNumber = data['from_number'] ?? 'مجهول';
          showNotification(
            id: 202,
            title: 'مكالمة واردة 📞',
            body: 'اتصال من الرقم الداخلي: $fromNumber',
          );
        }
      }, onError: (_) {}, onDone: () {});

      return channel;
    } catch (_) {
      return null;
    }
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
