import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';
import 'services/background_service.dart';
import 'services/license_service.dart';
import 'views/activation_view.dart';
import 'views/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 1. طلب الأذونات المطلوبة بما فيها أذونات الخلفية والإشعارات
  await _requestPermissions();

  // 2. تهيئة خدمات الخلفية والإشعارات المحلية بالكامل
  await BackgroundServiceHelper.initializeService();

  // 3. التحقق من حالة تفعيل التطبيق للجهاز أولاً
  bool isActivated = await LicenseService.isAppActivated();

  // 4. تشغيل خدمة الخلفية والإشعارات في حال كان التطبيق مفعّلاً
  if (isActivated) {
    await BackgroundServiceHelper.startService();
  }

  runApp(WifiP2PApp(isActivated: isActivated));
}

Future<void> _requestPermissions() async {
  await [
    Permission.microphone,
    Permission.camera,
    Permission.location,
    Permission.nearbyWifiDevices,
    Permission.notification, // إذن الإشعارات لأندرويد 13+
    Permission.ignoreBatteryOptimizations, // طلب استثناء تحسين البطارية لضمان عدم إغلاق السيرفر
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

  /// دالة تفعيل التطبيق بعد إدخال الكود الصحيح
  void _handleActivation() async {
    // ⚡ بدء خدمة الخلفية فور إتمام التفعيل بنجاح
    await BackgroundServiceHelper.startService();
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
