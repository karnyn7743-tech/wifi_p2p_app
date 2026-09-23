import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ChatStorageService {
  static const String _prefix = 'chat_history_';

  /// جلب سجل الرسائل لجهاز معين
  static Future<List<Map<String, String>>> getMessages(String targetId) async {
    final prefs = await SharedPreferences.getInstance();
    final String? rawData = prefs.getString('$_prefix$targetId');
    if (rawData == null || rawData.isEmpty) return [];

    try {
      final List<dynamic> decoded = jsonDecode(rawData);
      return decoded.map((item) => Map<String, String>.from(item)).toList();
    } catch (_) {
      return [];
    }
  }

  /// حفظ رسالة جديدة في السجل
  static Future<void> saveMessage(String targetId, Map<String, String> message) async {
    final prefs = await SharedPreferences.getInstance();
    List<Map<String, String>> currentMessages = await getMessages(targetId);
    currentMessages.add(message);

    await prefs.setString('$_prefix$targetId', jsonEncode(currentMessages));
  }

  /// مسح سجل المحادثة
  static Future<void> clearChat(String targetId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$targetId');
  }
}
