import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ContactModel {
  final String deviceId;
  final String name;
  final String extension; // الرقم اللاسلكي المختصر (مثل: 101)

  ContactModel({
    required this.deviceId,
    required this.name,
    this.extension = '',
  });

  Map<String, String> toMap() => {
        'deviceId': deviceId,
        'name': name,
        'extension': extension,
      };

  factory ContactModel.fromMap(Map<String, dynamic> map) => ContactModel(
        deviceId: map['deviceId']?.toString().trim() ?? '',
        name: map['name']?.toString().trim() ?? '',
        extension: map['extension']?.toString().trim() ?? '',
      );
}

class ContactService {
  static const String _contactsKey = 'saved_p2p_contacts';

  /// 1️⃣ حفظ جهة اتصال جديدة أو تحديثها مع الرقم اللاسلكي المختصر
  static Future<void> saveContact(String deviceId, String name, {String extension = ''}) async {
    final cleanId = deviceId.trim();
    final cleanName = name.trim();
    final cleanExt = extension.trim();
    if (cleanId.isEmpty || cleanName.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    List<ContactModel> contacts = await getAllContacts();

    // حذف السجل القديم للجهاز إن وجد لمنع التكرار
    contacts.removeWhere((c) => c.deviceId == cleanId);
    contacts.add(ContactModel(deviceId: cleanId, name: cleanName, extension: cleanExt));

    List<String> rawList = contacts.map((c) => jsonEncode(c.toMap())).toList();
    await prefs.setString(_contactsKey, jsonEncode(rawList));
  }

  /// 2️⃣ جلب كل جهات الاتصال المحفوظة كقائمة كائنات (ContactModel)
  static Future<List<ContactModel>> getAllContacts() async {
    final prefs = await SharedPreferences.getInstance();
    String? rawData = prefs.getString(_contactsKey);
    if (rawData == null || rawData.isEmpty) {
      return [];
    }
    try {
      final decoded = jsonDecode(rawData);
      
      // التوافقية مع البيانات القديمة (Map<String, String>)
      if (decoded is Map) {
        List<ContactModel> legacyContacts = [];
        decoded.forEach((key, value) {
          legacyContacts.add(ContactModel(
            deviceId: key.toString().trim(),
            name: value.toString().trim(),
            extension: '',
          ));
        });
        return legacyContacts;
      } 
      // التوافقية مع التنسيق الجديد (List)
      else if (decoded is List) {
        return decoded
            .map((item) => ContactModel.fromMap(jsonDecode(item)))
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// 3️⃣ جلب الخريطة القديمة لجهات الاتصال لضمان التوافق التام مع بقية الشاشات
  static Future<Map<String, String>> getContacts() async {
    List<ContactModel> contacts = await getAllContacts();
    Map<String, String> resultMap = {};
    for (var contact in contacts) {
      resultMap[contact.deviceId] = contact.name;
    }
    return resultMap;
  }

  /// 4️⃣ جلب اسم جهة اتصال محددة بناءً على deviceId
  static Future<String?> getContactName(String deviceId) async {
    final cleanId = deviceId.trim();
    if (cleanId.isEmpty) return null;

    List<ContactModel> contacts = await getAllContacts();
    try {
      final contact = contacts.firstWhere((c) => c.deviceId == cleanId);
      return contact.name;
    } catch (_) {
      return null;
    }
  }

  /// 5️⃣ البحث عن جهة اتصال بناءً على الرقم اللاسلكي المختصر (لوحة الأرقام)
  static Future<ContactModel?> getContactByExtension(String ext) async {
    final cleanExt = ext.trim();
    if (cleanExt.isEmpty) return null;

    List<ContactModel> contacts = await getAllContacts();
    try {
      return contacts.firstWhere((c) => c.extension == cleanExt);
    } catch (_) {
      return null;
    }
  }

  /// 6️⃣ حذف جهة اتصال باستخدام deviceId
  static Future<void> deleteContact(String deviceId) async {
    final cleanId = deviceId.trim();
    if (cleanId.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    List<ContactModel> contacts = await getAllContacts();
    
    contacts.removeWhere((c) => c.deviceId == cleanId);
    List<String> rawList = contacts.map((c) => jsonEncode(c.toMap())).toList();
    await prefs.setString(_contactsKey, jsonEncode(rawList));
  }
}
