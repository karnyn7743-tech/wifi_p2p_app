import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';

class PhoneNumberService {
  static const String _keyPhoneNumber = 'lanphone_unique_number_5d';

  /// جلب الرقم المكون من 5 أرقام، أو توليده وحفظه إن لم يكن موجوداً
  static Future<String> getOrGeneratePhoneNumber() async {
    final prefs = await SharedPreferences.getInstance();
    String? existingNumber = prefs.getString(_keyPhoneNumber);

    if (existingNumber != null && existingNumber.length == 5) {
      return existingNumber;
    }

    // توليد رقم مشتق من بصمة الجهاز أو رقم عشوائي بين 10000 و 99999
    String newNumber = await _generateDeterministicOrRandom5Digits();
    await prefs.setString(_keyPhoneNumber, newNumber);
    return newNumber;
  }

  /// توليد 5 أرقام ثابتة للجهاز
  static Future<String> _generateDeterministicOrRandom5Digits() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      String rawId = '';

      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        rawId = androidInfo.id;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        rawId = iosInfo.identifierForVendor ?? '';
      }

      if (rawId.isNotEmpty) {
        // اشتقاق رقم محدد وثابت من الـ Hashcode للجهاز ليبقى متطابقاً
        int hash = rawId.hashCode.abs();
        int fiveDigits = 10000 + (hash % 90000); // يضمن المدى بين 10000 و 99999
        return fiveDigits.toString();
      }
    } catch (_) {}

    // بديل عشوائي إذا تعذر قراءة هوية الجهاز
    int randomNum = 10000 + Random().nextInt(90000);
    return randomNum.toString();
  }

  /// إمكانية تغيير الرقم يدوياً إذا رغب المستخدم في رقم مخصص
  static Future<void> setCustomPhoneNumber(String number) async {
    if (number.length == 5 && int.tryParse(number) != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyPhoneNumber, number);
    }
  }
}
