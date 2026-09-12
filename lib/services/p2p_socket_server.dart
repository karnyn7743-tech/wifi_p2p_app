import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'encryption_service.dart'; // 🔐 استيراد خدمة التشفير
import 'contact_service.dart';    // 📖 استيراد خدمة جهات الاتصال

class P2PSocketServer {
  ServerSocket? _server;
  
  static final StreamController<String> _messageStreamController = StreamController<String>.broadcast();
  static Stream<String> get messageStream => _messageStreamController.stream;

  // مشغل الصوت للرنين والتنبيهات
  static final AudioPlayer _audioPlayer = AudioPlayer();

  /// تشغيل صوت نغمة التنبيه للرسائل أو المكالمات
  static Future<void> playRingtone({bool loop = false}) async {
    try {
      await _audioPlayer.stop();
      if (loop) {
        await _audioPlayer.setReleaseMode(ReleaseMode.loop);
      } else {
        await _audioPlayer.setReleaseMode(ReleaseMode.release);
      }
      // تشغيل النغمة الافتراضية
      await _audioPlayer.play(UrlSource('https://actions.google.com/sounds/v1/alarms/digital_watch_alarm.ogg'));
    } catch (_) {}
  }

  /// إيقاف صوت الرنين فوراً
  static Future<void> stopRingtone() async {
    try {
      await _audioPlayer.stop();
    } catch (_) {}
  }

  Future<void> startServer(
    int port, {
    required Function(String callerId, String callerName, Socket socket) onRequestConnection,
    required Function(String senderId, String message) onMessageReceived,
  }) async {
    try {
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      _server?.listen((Socket clientSocket) {
        clientSocket.listen((data) async {
          String message = utf8.decode(data, allowMalformed: true).trim();
          String remoteIp = clientSocket.remoteAddress.address;

          if (message.startsWith("CONNECT_REQUEST")) {
            List<String> parts = message.split("|");
            // استخراج deviceId والمعرف الأصلي المرسل
            String callerId = parts.length > 1 ? parts[1].trim() : remoteIp;
            String originalName = parts.length > 2 ? parts[2].trim() : callerId;

            // 🔍 البحث عن اسم جهة الاتصال المحفوظة استناداً إلى رقم المعرف (deviceId) وليس الـ IP
            String? savedName = await ContactService.getContactName(callerId);
            
            // 📞 صياغة نص التنبيه المخصص
            String displayName = (savedName != null && savedName.isNotEmpty)
                ? savedName
                : originalName;

            onRequestConnection(callerId, displayName, clientSocket);
          } else if (message == "CONNECT_ACCEPTED") {
            onMessageReceived(remoteIp, "CONNECT_ACCEPTED");
          } else {
            // 🔓 فك التشفير للرسائل العامة أو رسائل المجموعات الواردة قبل إرسالها للواجهة وإشعار الخلفية
            String processedMsg = message;
            try {
              // محاولة فك التشفير أولاً إن كانت تشفيراً فردياً أو مشفرة كلياً
              processedMsg = EncryptionService.decryptText(message);
            } catch (_) {
              // في حال كانت حزمة JSON للمجموعات، نقوم بفك تشفير الحقل الداخلي للمحتوى فقط
              try {
                final decoded = jsonDecode(message);
                if (decoded is Map<String, dynamic> && decoded.containsKey('message')) {
                  decoded['message'] = EncryptionService.decryptText(decoded['message']);
                  processedMsg = jsonEncode(decoded);
                }
              } catch (_) {}
            }

            _messageStreamController.add(processedMsg);
            onMessageReceived(remoteIp, processedMsg);
          }
        });
      });
    } catch (e) {
      print("خطأ أثناء تشغيل السيرفر: $e");
    }
  }

  static Future<bool> sendMessageToHost(String host, int port, String message) async {
    try {
      Socket socket = await Socket.connect(host, port, timeout: const Duration(seconds: 4));
      
      List<int> bytes = utf8.encode(message);
      socket.add(bytes);
      
      await socket.flush();
      await Future.delayed(const Duration(milliseconds: 300));
      await socket.close();
      return true;
    } catch (e) {
      print("خطأ في إرسال البيانات إلى $host: $e");
      return false;
    }
  }

  /// إرسال طلب الاتصال مع تمرير الـ deviceId الخاص بك والاسم
  static Future<bool> sendConnectRequest(String host, int port, String myDeviceId, String myName) async {
    return await sendMessageToHost(host, port, "CONNECT_REQUEST|$myDeviceId|$myName");
  }

  void stop() {
    stopRingtone();
    _server?.close();
  }
}
