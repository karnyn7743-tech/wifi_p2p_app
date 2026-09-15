import 'dart:convert';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class SignalingService {
  IOWebSocketChannel? _channel;
  
  // دالة الاتصال بالسيرفر والتسجيل
  void connect({
    required String serverIp,
    required String deviceId,
    required String deviceName,
    required Function(String myNumber) onRegistered,
    required Function(List<String> onlineNumbers) onDirectoryUpdate,
    required Function(String fromNumber, Map<String, dynamic> sdp) onIncomingCall,
  }) {
    final url = Uri.parse('ws://$serverIp:8765');
    _channel = IOWebSocketChannel.connect(url);

    // 1. إرسال طلب التسجيل بمجرد الاتصال
    _send({
      'type': 'REGISTER',
      'device_id': deviceId,
      'name': deviceName,
    });

    // 2. الاستماع للرسائل القادمة من اللابتوب
    _channel!.stream.listen((message) {
      final data = jsonDecode(message);
      final type = data['type'];

      switch (type) {
        case 'REGISTER_RESPONSE':
          if (data['status'] == 'SUCCESS') {
            onRegistered(data['phone_number']);
          }
          break;

        case 'DIRECTORY_UPDATE':
          List<String> numbers = List<String>.from(data['online_numbers']);
          onDirectoryUpdate(numbers);
          break;

        case 'INCOMING_CALL':
          onIncomingCall(data['from_number'], data['sdp']);
          break;
      }
    }, onError: (error) {
      print('خطأ في الاتصال بالسيرفر: $error');
    }, onDone: () {
      print('تم قطع الاتصال بالسيرفر');
    });
  }

  // دالة طلب اتصال برقم معين
  void makeCall(String targetNumber, Map<String, dynamic> sdpOffer) {
    _send({
      'type': 'CALL_OFFER',
      'target_number': targetNumber,
      'sdp': sdpOffer,
    });
  }

  // دالة قبول المكالمة
  void answerCall(String targetNumber, Map<String, dynamic> sdpAnswer) {
    _send({
      'type': 'CALL_ANSWER',
      'target_number': targetNumber,
      'sdp': sdpAnswer,
    });
  }

  void _send(Map<String, dynamic> data) {
    _channel?.sink.add(jsonEncode(data));
  }

  void disconnect() {
    _channel?.sink.close();
  }
}
