import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class GroupModel {
  final String groupId;
  final String groupName;
  final List<String> memberDeviceIds; // الأجهزة المنضمة للمجموعة

  GroupModel({
    required this.groupId,
    required this.groupName,
    required this.memberDeviceIds,
  });

  Map<String, dynamic> toJson() => {
        'groupId': groupId,
        'groupName': groupName,
        'memberDeviceIds': memberDeviceIds,
      };

  factory GroupModel.fromJson(Map<String, dynamic> json) => GroupModel(
        groupId: json['groupId'],
        groupName: json['groupName'],
        memberDeviceIds: List<String>.from(json['memberDeviceIds'] ?? []),
      );
}

class GroupService {
  static const String _groupsKey = 'p2p_saved_groups';

  /// إنشاء مجموعة جديدة
  static Future<void> createGroup(String groupName, List<String> initialMembers) async {
    final prefs = await SharedPreferences.getInstance();
    List<GroupModel> groups = await getGroups();

    String groupId = 'group_${DateTime.now().millisecondsSinceEpoch}';
    GroupModel newGroup = GroupModel(
      groupId: groupId,
      groupName: groupName,
      memberDeviceIds: initialMembers,
    );

    groups.add(newGroup);
    await _saveGroupsList(prefs, groups);
  }

  /// جلب كافة المجموعات المحفوظة
  static Future<List<GroupModel>> getGroups() async {
    final prefs = await SharedPreferences.getInstance();
    String? rawData = prefs.getString(_groupsKey);
    if (rawData == null || rawData.isEmpty) return [];

    try {
      List<dynamic> list = jsonDecode(rawData);
      return list.map((item) => GroupModel.fromJson(item)).toList();
    } catch (_) {
      return [];
    }
  }

  /// إضافة عضو للمجموعة (بشرط ألا يتجاوز 100 عضو)
  static Future<bool> addMemberToGroup(String groupId, String newDeviceId) async {
    final prefs = await SharedPreferences.getInstance();
    List<GroupModel> groups = await getGroups();

    int index = groups.indexWhere((g) => g.groupId == groupId);
    if (index != -1) {
      if (groups[index].memberDeviceIds.length >= 100) {
        return false; // تجاوز الحد الأقصى للمجموعة (100 عضو)
      }
      if (!groups[index].memberDeviceIds.contains(newDeviceId)) {
        groups[index].memberDeviceIds.add(newDeviceId);
        await _saveGroupsList(prefs, groups);
      }
    }
    return true;
  }

  static Future<void> _saveGroupsList(SharedPreferences prefs, List<GroupModel> groups) async {
    String encoded = jsonEncode(groups.map((g) => g.toJson()).toList());
    await prefs.setString(_groupsKey, encoded);
  }
}
