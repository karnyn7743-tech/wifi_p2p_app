import 'package:shared_preferences/shared_preferences.dart';

class BlockService {
  static const String _keyBlockedDevices = 'lanphone_blocked_devices';

  /// فحص هل الجهاز محظور
  static Future<bool> isBlocked(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> blocked = prefs.getStringList(_keyBlockedDevices) ?? [];
    return blocked.contains(deviceId.trim());
  }

  /// حظر جهاز
  static Future<void> blockDevice(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> blocked = prefs.getStringList(_keyBlockedDevices) ?? [];
    if (!blocked.contains(deviceId.trim())) {
      blocked.add(deviceId.trim());
      await prefs.setStringList(_keyBlockedDevices, blocked);
    }
  }

  /// إلغاء حظر جهاز
  static Future<void> unblockDevice(String deviceId) async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> blocked = prefs.getStringList(_keyBlockedDevices) ?? [];
    blocked.remove(deviceId.trim());
    await prefs.setStringList(_keyBlockedDevices, blocked);
  }

  /// جلب قائمة جميع الأجهزة المحظورة
  static Future<List<String>> getBlockedDevices() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_keyBlockedDevices) ?? [];
  }
}
