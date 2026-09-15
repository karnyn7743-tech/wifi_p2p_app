import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class EmbeddedPbxServer {
  static HttpServer? _server;
  static final Map<String, WebSocketChannel> _clients = {};
  static int _nextExt = 101;

  /// الحصول على عنوان الـ IP المحلي للجوال (سواء Wi-Fi أو Hotspot)
  static Future<String> getLocalIpAddress() async {
    try {
      final info = NetworkInfo();
      String? ip = await info.getWifiIP();
      if (ip != null && ip.isNotEmpty && ip != "0.0.0.0") {
        return ip;
      }
      
      // في حال تفعيل الـ Hotspot (غالباً يكون 192.168.43.1 في أندرويد)
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      print("خطأ أثناء استخراج الـ IP: $e");
    }
    return "127.0.0.1";
  }

  /// تشغيل سيرفر WebSocket محلي على المنفذ 8888
  static Future<bool> startServer({int port = 8888}) async {
    if (_server != null) return true; // السيرفر يعمل بالفعل

    try {
      var handler = webSocketHandler((WebSocketChannel webSocket) {
        String? ext;

        webSocket.stream.listen(
          (message) {
            try {
              final data = jsonDecode(message);
              final type = data['type'];

              if (type == 'register') {
                ext = _nextExt.toString();
                _nextExt++;
                _clients[ext!] = webSocket;

                // إرسال تأكيد التسجيل متبوعاً بالرقم الداخلي
                webSocket.sink.add(jsonEncode({
                  'type': 'registered',
                  'ext': ext,
                  'message': 'تم التسجيل في السيرفر المحلي بنجاح'
                }));

                _broadcastUserList();
              } else if (type == 'call_offer' || type == 'call_answer' || type == 'ice_candidate' || type == 'hangup') {
                final targetExt = data['target'];
                if (targetExt != null && _clients.containsKey(targetExt)) {
                  _clients[targetExt]!.sink.add(message);
                }
              }
            } catch (e) {
              print("خطأ في معالجة رسالة السيرفر: $e");
            }
          },
          onDone: () {
            if (ext != null) {
              _clients.remove(ext);
              _broadcastUserList();
            }
          },
          onError: (error) {
            if (ext != null) {
              _clients.remove(ext);
              _broadcastUserList();
            }
          },
        );
      });

      _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
      print('⚡ تم تشغيل السيرفر المحلي للجوال على البورت: ${_server!.port}');
      return true;
    } catch (e) {
      print("خطأ في بدء السيرفر المحلي: $e");
      return false;
    }
  }

  /// إرسال قائمة الأجهزة المتاحة لجميع المتصلين
  static void _broadcastUserList() {
    final userList = _clients.keys.toList();
    final message = jsonEncode({
      'type': 'user_list',
      'users': userList,
    });

    for (var client in _clients.values) {
      client.sink.add(message);
    }
  }

  /// إيقاف السيرفر
  static Future<void> stopServer() async {
    await _server?.close(force: true);
    _server = null;
    _clients.clear();
    _nextExt = 101;
  }
}
