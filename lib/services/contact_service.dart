import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ContactService {
  static const String _contactsKey = 'saved_p2p_contacts';

  // 1️⃣ حفظ جهة اتصال جديدة أو تحديثها
  static Future<void> saveContact(String deviceIdOrIp, String name) async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, String> contacts = await getContacts();
    contacts[deviceIdOrIp] = name;
    await prefs.setString(_contactsKey, jsonEncode(contacts));
  }

  // 2️⃣ جلب كل جهات الاتصال المحفوظة
  static Future<Map<String, String>> getContacts() async {
    final prefs = await SharedPreferences.getInstance();
    String? rawData = prefs.getString(_contactsKey);
    if (rawData == null || rawData.isEmpty) {
      return {};
    }
    try {
      Map<String, dynamic> decoded = jsonDecode(rawData);
      return decoded.map((key, value) => MapEntry(key, value.toString()));
    } catch (_) {
      return {};
    }
  }

  // 3️⃣ جلب اسم جهة اتصال محددة بناءً على ID أو IP
  static Future<String?> getContactName(String deviceIdOrIp) async {
    Map<String, String> contacts = await getContacts();
    return contacts[deviceIdOrIp];
  }

  // 4️⃣ 🔑 الدالة المفقودة: حذف جهة اتصال
  static Future<void> deleteContact(String deviceIdOrIp) async {
    final prefs = await SharedPreferences.getInstance();
    Map<String, String> contacts = await getContacts();
    if (contacts.containsKey(deviceIdOrIp)) {
      contacts.remove(deviceIdOrIp);
      await prefs.setString(_contactsKey, jsonEncode(contacts));
    }
  }
}
