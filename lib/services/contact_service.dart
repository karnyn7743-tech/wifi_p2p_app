import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ContactService {
  // استخدام المفتاح المعزول لضمان نظافة السجلات
  static const String _contactsKey = 'saved_p2p_contacts';

  /// 1️⃣ حفظ جهة اتصال جديدة أو تحديثها باستخدام deviceId حصراً
  static Future<void> saveContact(String deviceId, String name) async {
    final cleanId = deviceId.trim();
    final cleanName = name.trim();
    if (cleanId.isEmpty || cleanName.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    Map<String, String> contacts = await getContacts();
    
    contacts[cleanId] = cleanName;
    await prefs.setString(_contactsKey, jsonEncode(contacts));
  }

  /// 2️⃣ جلب كل جهات الاتصال المحفوظة
  static Future<Map<String, String>> getContacts() async {
    final prefs = await SharedPreferences.getInstance();
    String? rawData = prefs.getString(_contactsKey);
    if (rawData == null || rawData.isEmpty) {
      return {};
    }
    try {
      Map<String, dynamic> decoded = jsonDecode(rawData);
      return decoded.map((key, value) => MapEntry(key.trim(), value.toString().trim()));
    } catch (_) {
      return {};
    }
  }

  /// 3️⃣ جلب اسم جهة اتصال محددة بناءً على deviceId
  static Future<String?> getContactName(String deviceId) async {
    final cleanId = deviceId.trim();
    if (cleanId.isEmpty) return null;

    Map<String, String> contacts = await getContacts();
    return contacts[cleanId];
  }

  /// 4️⃣ حذف جهة اتصال باستخدام deviceId
  static Future<void> deleteContact(String deviceId) async {
    final cleanId = deviceId.trim();
    if (cleanId.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    Map<String, String> contacts = await getContacts();
    if (contacts.containsKey(cleanId)) {
      contacts.remove(cleanId);
      await prefs.setString(_contactsKey, jsonEncode(contacts));
    }
  }
}
