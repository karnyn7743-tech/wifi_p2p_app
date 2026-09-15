import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';
import 'services/background_service.dart';
import 'services/license_service.dart';
import 'services/p2p_socket_server.dart';
import 'services/embedded_pbx_server.dart';
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

/// تشغيل السيرفرات الداخلية وخدمة الخلفية بأمان مستقل لكل خدمة
Future<void> _startAllServices() async {
  try {
    // تشغيل سيرفر السوكيت المحلي
    await P2PSocketServer.startServer();
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

  @override
  void initState() {
    super.initState();
    _isActivated = widget.isActivated;
  }

  void _handleActivation() async {
    await _startAllServices();
    if (mounted) {
      setState(() {
        _isActivated = true;
      });
    }
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
        home: _isActivated
            ? const HomeScreen()
            : ActivationView(
                onActivated: _handleActivation,
              ),
      ),
    );
  }
}
