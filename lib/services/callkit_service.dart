import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

class CallKitService {
  /// إظهار شاشة مكالمة واردة على شاشة القفل بنمط الهاتف
  static Future<void> showIncomingCall({
    required String uuid,
    required String callerName,
    required String callerNumber,
    required bool isVideo,
  }) async {
    CallKitParams params = CallKitParams(
      id: uuid,
      nameCaller: callerName,
      appName: 'LanPhone',
      avatar: '',
      handle: callerNumber,
      type: isVideo ? 1 : 0,
      duration: 30000,
      textAccept: 'رد',
      textDecline: 'رفض',
      extra: <String, dynamic>{'userId': callerNumber},
      headers: <String, dynamic>{'platform': 'flutter'},
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#0955fa',
        actionColor: '#4CAF50',
        textColor: '#ffffff',
        incomingCallNotificationChannelName: "مكالمات LanPhone الواردة",
      ),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(params);
  }

  /// إنهاء وإغلاق شاشة المكالمة
  static Future<void> endCall(String uuid) async {
    await FlutterCallkitIncoming.endCall(uuid);
  }

  /// إنهاء كافة المكالمات الحالية
  static Future<void> endAllCalls() async {
    await FlutterCallkitIncoming.endAllCalls();
  }
}
