import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart'; // 📞 استيراد أحداث CallKit
import 'services/background_service.dart';
import 'services/license_service.dart';
import 'services/p2p_socket_server.dart';
import 'services/embedded_pbx_server.dart';
import 'services/biometric_service.dart'; // 🔐 استيراد خدمة قفل البصمة
import 'services/callkit_service.dart'; // 📞 استيراد خدمة المكالمات
import 'views/activation_view.dart';
import 'views/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 1. طلب الأذونات المطلوبة فور التشغيل
  await _requestPermissions();

  // 2. تهيئة خدمات الخلفية والإشعارات المحلية
  await BackgroundServiceHelper.initializeService();

  // 3. التحقق من حالة تفعيل التطبيق
  bool isActivated = await LicenseService.isAppActivated();

  // 4. تشغيل السيرفرات وخدمة الخلفية في حال كان التطبيق مفعّلاً
  if (isActivated) {
    await _startAllServices();
  }

  runApp(WifiP2PApp(isActivated: isActivated));
}

/// إنشاء كائن من P2PSocketServer لكون الدالة startServer ليست static
final P2PSocketServer _p2pServerInstance = P2PSocketServer();

/// تشغيل السيرفرات الداخلية وخدمة الخلفية بأمان مستقل لكل خدمة
Future<void> _startAllServices() async {
  try {
    // تشغيل سيرفر الـ P2P وتمرير البورت والـ Callbacks المطلوبة حسب تعريف الكلاس
    await _p2pServerInstance.startServer(
      8888,
      onRequestConnection: (callerId, callerName, socket) {
        debugPrint('طلب اتصال جديد من: $callerName ($callerId)');
      },
      onMessageReceived: (senderId, message) {
        debugPrint('رسالة جديدة من $senderId: $message');
      },
    );
  } catch (e) {
    debugPrint('Error starting P2PSocketServer: $e');
  }

  try {
    // تشغيل سيرفر المقسم المدمج PBX
    await EmbeddedPbxServer.startServer();
  } catch (e) {
    debugPrint('Error starting EmbeddedPbxServer: $e');
  }

  try {
    // تشغيل خدمة المهام في الخلفية
    await BackgroundServiceHelper.startService();
  } catch (e) {
    debugPrint('Error starting BackgroundService: $e');
  }
}

Future<void> _requestPermissions() async {
  await [
    Permission.microphone,
    Permission.camera,
    Permission.location,
    Permission.nearbyWifiDevices,
    Permission.notification,
    Permission.ignoreBatteryOptimizations,
  ].request();
}

class WifiP2PApp extends StatefulWidget {
  final bool isActivated;

  const WifiP2PApp({Key? key, required this.isActivated}) : super(key: key);

  @override
  State<WifiP2PApp> createState() => _WifiP2PAppState();
}

class _WifiP2PAppState extends State<WifiP2PApp> {
  late bool _isActivated;
  bool _isAuthenticated = false;
  bool _requiresBiometrics = false;
  bool _isCheckingAuth = true;

  @override
  void initState() {
    super.initState();
    _isActivated = widget.isActivated;
    _checkBiometricLock();
    _listenToCallEvents(); // 📞 الاستماع لأحداث شاشة قفل المكالمات
  }

  /// 📞 الاستماع لأزرار شاشة القفل (رد / رفض) باستخدام if / else لتفادي خطأ Constant Expression
  void _listenToCallEvents() {
    FlutterCallkitIncoming.onEvent.listen((event) {
      if (event == null) return;
      
      final eventType = event.event;
      if (eventType == Event.actionCallAccept) {
        debugPrint('تم قبول المكالمة من شاشة القفل');
        CallKitService.endAllCalls();
      } else if (eventType == Event.actionCallDecline) {
        debugPrint('تم رفض المكالمة من شاشة القفل');
        CallKitService.endAllCalls();
      } else if (eventType == Event.actionCallEnded) {
        CallKitService.endAllCalls();
      }
    });
  }

  /// 🔐 فحص ما إذا كان قفل البصمة مفعلاً والتحقق منه
  Future<void> _checkBiometricLock() async {
    bool enabled = await BiometricService.isBiometricEnabled();
    if (enabled && _isActivated) {
      if (mounted) {
        setState(() {
          _requiresBiometrics = true;
          _isCheckingAuth = false;
        });
      }
      _authenticateUser();
    } else {
      if (mounted) {
        setState(() {
          _isAuthenticated = true;
          _isCheckingAuth = false;
        });
      }
    }
  }

  Future<void> _authenticateUser() async {
    bool authenticated = await BiometricService.authenticate();
    if (mounted) {
      setState(() {
        _isAuthenticated = authenticated;
      });
    }
  }

  void _handleActivation() async {
    await _startAllServices();
    if (mounted) {
      setState(() {
        _isActivated = true;
      });
    }
    _checkBiometricLock();
  }

  @override
  Widget build(BuildContext context) {
    return WithForegroundTask(
      child: MaterialApp(
        title: 'المستكشف لإتصالات ألعاب الواي فاي',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
        ),
        home: !_isActivated
            ? ActivationView(onActivated: _handleActivation)
            : _isCheckingAuth
                ? const Scaffold(body: Center(child: CircularProgressIndicator()))
                : (_requiresBiometrics && !_isAuthenticated)
                    ? _buildLockScreen()
                    : const HomeScreen(),
      ),
    );
  }

  /// 🔒 شاشة القفل عند تفعيل البصمة
  Widget _buildLockScreen() {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.fingerprint, size: 85, color: Colors.blue),
              const SizedBox(height: 20),
              const Text(
                'التطبيق مقفل بالبصمة',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'يرجى تأكيد هويتك للوصول إلى المحادثات والاتصالات',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 28),
              ElevatedButton.icon(
                icon: const Icon(Icons.lock_open),
                label: const Text('إلغاء القفل'),
                onPressed: _authenticateUser,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
