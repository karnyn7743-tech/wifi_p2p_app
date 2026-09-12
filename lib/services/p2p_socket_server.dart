import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'encryption_service.dart'; // 🔐 استيراد خدمة التشفير
import 'contact_service.dart';    // 📖 استيراد خدمة جهات الاتصال
import 'file_transfer_service.dart'; // 📁 استيراد خدمة نقل الملفات

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
      // إغلاق أي سيرفر سابق لتجنب تعارض المنافذ
      await _server?.close();
      _server = await ServerSocket.bind(InternetAddress.anyIPv4, port, shared: true);
      
      _server?.listen((Socket clientSocket) {
        // ضبط خيارات تحسين استجابة الـ Socket
        clientSocket.setOption(SocketOption.tcpNoDelay, true);

        clientSocket.listen(
          (data) async {
            String message = utf8.decode(data, allowMalformed: true).trim();
            String remoteIp = clientSocket.remoteAddress.address;

            // 📁 1. التعرف المباشر على استقبال الملفات مع استدعاء FileTransferService
            if (message.startsWith("FILE_HEADER")) {
              List<String> parts = message.split("|");
              if (parts.length >= 3) {
                String fileName = parts[1];
                int fileSize = int.tryParse(parts[2]) ?? 0;

                await FileTransferService.receiveFile(
                  clientSocket,
                  fileName: fileName,
                  fileSize: fileSize,
                  onProgress: (progress) {
                    print("جاري استقبال الملف: ${(progress * 100).toStringAsFixed(0)}%");
                  },
                );
              }
              return;
            }

            // 📞 2. طلبات الاتصال والمكالمات
            if (message.startsWith("CONNECT_REQUEST")) {
              List<String> parts = message.split("|");
              String callerId = parts.length > 1 ? parts[1].trim() : remoteIp;
              String originalName = parts.length > 2 ? parts[2].trim() : callerId;

              String? savedName = await ContactService.getContactName(callerId);
              String displayName = (savedName != null && savedName.isNotEmpty)
                  ? savedName
                  : originalName;

              onRequestConnection(callerId, displayName, clientSocket);
            } else if (message == "CONNECT_ACCEPTED") {
              onMessageReceived(remoteIp, "CONNECT_ACCEPTED");
              clientSocket.destroy();
            } else {
              String processedMsg = message;
              try {
                processedMsg = EncryptionService.decryptText(message);
              } catch (_) {
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
              clientSocket.destroy();
            }
          },
          onError: (error) {
            clientSocket.destroy();
          },
          onDone: () {
            clientSocket.destroy();
          },
        );
      });
    } catch (e) {
      print("خطأ أثناء تشغيل السيرفر: $e");
    }
  }

  /// إرسال الرسائل عبر Socket مع إدارة سريعة للموارد وزمن استجابة محدد
  static Future<bool> sendMessageToHost(String host, int port, String message) async {
    Socket? socket;
    try {
      // تقليل مهلة الاتصال لـ 2.5 ثانية للتعامل السريع مع تغيرات الشبكة
      socket = await Socket.connect(host, port, timeout: const Duration(milliseconds: 2500));
      socket.setOption(SocketOption.tcpNoDelay, true);

      List<int> bytes = utf8.encode(message);
      socket.add(bytes);
      
      await socket.flush();
      await socket.close();
      return true;
    } catch (e) {
      print("خطأ في إرسال البيانات إلى $host: $e");
      socket?.destroy();
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
    _server = null;
  }
}
