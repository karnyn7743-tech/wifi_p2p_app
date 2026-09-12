import 'dart:async';
import 'dart:convert';
import 'dart:io';

class DiscoveredService {
  final String? name;
  final String? host;
  final int? port;
  DateTime lastSeen; // تتبع آخر زمن ظهور للجهاز

  DiscoveredService({
    this.name, 
    this.host, 
    this.port, 
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();
}

class NetworkDiscoveryService {
  static const int _discoveryPort = 8888;
  RawDatagramSocket? _socket;
  Timer? _broadcastTimer;
  Timer? _cleanupTimer;

  // خريطة لتخزين الأجهزة النشطة
  final Map<String, DiscoveredService> _activeDevices = {};

  /// 1️⃣ بدء الاستماع والتسجيل التلقائي للأجهزة وتحديث حالتها
  Future<void> startListening(
    Function(List<DiscoveredService>) onDevicesUpdated,
  ) async {
    try {
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, _discoveryPort);
      _socket?.broadcastEnabled = true;

      _socket?.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          Datagram? dg = _socket?.receive();
          if (dg != null) {
            String message = utf8.decode(dg.data).trim();
            String hostIp = dg.address.address;

            // استقبال إشارة طلب الاكتشاف والرد عليها
            if (message.startsWith("DISCOVER_REQ")) {
              List<String> parts = message.split("|");
              String deviceName = parts.length > 1 ? parts[1] : "جهاز محلي";
              int port = parts.length > 2 ? int.tryParse(parts[2]) ?? 4040 : 4040;

              _registerOrUpdateDevice(hostIp, deviceName, port, onDevicesUpdated);
              _sendResponse(dg.address, deviceName);
            } 
            // استقبال استجابة أو إشارة نبض (HEARTBEAT) من جهاز آخر
            else if (message.startsWith("DISCOVER_RESP") || message.startsWith("HEARTBEAT")) {
              List<String> parts = message.split("|");
              String deviceName = parts.length > 1 ? parts[1] : "جهاز محلي";
              int port = parts.length > 2 ? int.tryParse(parts[2]) ?? 4040 : 4040;

              _registerOrUpdateDevice(hostIp, deviceName, port, onDevicesUpdated);
            }
          }
        }
      });

      // بدء مؤقت تنظيف الأجهزة المنقطعة كل 4 ثوانٍ
      _startCleanupTimer(onDevicesUpdated);

    } catch (e) {
      print("خطأ في بدء خدمة الاكتشاف: $e");
    }
  }

  /// 2️⃣ تسجيل أو تحديث زمن تواجد الجهاز في الشبكة
  void _registerOrUpdateDevice(
    String hostIp, 
    String deviceName, 
    int port, 
    Function(List<DiscoveredService>) onDevicesUpdated,
  ) {
    _activeDevices[hostIp] = DiscoveredService(
      name: deviceName,
      host: hostIp,
      port: port,
      lastSeen: DateTime.now(),
    );
    onDevicesUpdated(_activeDevices.values.toList());
  }

  /// 3️⃣ إرسال إشارة بث عام (Broadcast/Ping) كل ثانيتين
  Future<void> startBroadcasting(int localPort, {String deviceName = "طالوت_الهاشمي"}) async {
    _broadcastTimer?.cancel();
    _broadcastTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _sendDiscoveryBroadcast(localPort, deviceName);
    });
    _sendDiscoveryBroadcast(localPort, deviceName);
  }

  void _sendDiscoveryBroadcast(int localPort, String deviceName) {
    try {
      String payload = "DISCOVER_REQ|$deviceName|$localPort";
      List<int> data = utf8.encode(payload);
      _socket?.send(data, InternetAddress('255.255.255.255'), _discoveryPort);
    } catch (e) {
      print("خطأ في إرسال حزمة البث: $e");
    }
  }

  void _sendResponse(InternetAddress targetAddress, String deviceName) {
    try {
      String payload = "DISCOVER_RESP|$deviceName|4040";
      List<int> data = utf8.encode(payload);
      _socket?.send(data, targetAddress, _discoveryPort);
    } catch (e) {
      print("خطأ في رد الاستجابة: $e");
    }
  }

  /// 4️⃣ تنظيف قائمة الأجهزة وحذف من ينقطع اتصاله لأكثر من 6 ثوانٍ
  void _startCleanupTimer(Function(List<DiscoveredService>) onDevicesUpdated) {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
      DateTime now = DateTime.now();
      bool hasChanges = false;

      _activeDevices.removeWhere((ip, device) {
        bool isTimedOut = now.difference(device.lastSeen).inSeconds > 6;
        if (isTimedOut) hasChanges = true;
        return isTimedOut;
      });

      if (hasChanges) {
        onDevicesUpdated(_activeDevices.values.toList());
      }
    });
  }

  /// 5️⃣ إيقاف الخدمة وتنظيف المؤقتات
  void stop() {
    _broadcastTimer?.cancel();
    _cleanupTimer?.cancel();
    _socket?.close();
    _socket = null;
    _activeDevices.clear();
  }
}
