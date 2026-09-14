import 'package:flutter/material.dart';
import 'dart:io';
import '../services/identity_service.dart';
import '../services/network_discovery_service.dart';
import '../services/p2p_socket_server.dart';
import '../services/contact_service.dart';
import '../services/audio_helper.dart';
import '../services/background_service.dart';
import '../services/group_service.dart';
import 'chat_detail_screen.dart';
import 'group_chat_screen.dart';
import 'dialpad_screen.dart'; // 📞 استيراد شاشة لوحة الأرقام اللاسلكية
import 'package:permission_handler/permission_handler.dart';

Future<void> disableBatteryOptimization() async {
  if (await Permission.ignoreBatteryOptimizations.isDenied) {
    await Permission.ignoreBatteryOptimizations.request();
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final NetworkDiscoveryService _discoveryService = NetworkDiscoveryService();
  final P2PSocketServer _socketServer = P2PSocketServer();
  
  final Map<String, Map<String, dynamic>> _discoveredDevices = {};
  final int localPort = 4040;
  List<String> _myLocalIps = [];

  @override
  void initState() {
    super.initState();
    disableBatteryOptimization();

    // ⚡ تشغيل خدمة الخلفية المستمرة لضمان بقاء السيرفر واستقبال الاتصالات
    BackgroundServiceHelper.startService();

    BackgroundServiceHelper.isWifiActive().then((_) {
      _fetchMyLocalIps().then((_) {
        _initNetworkServices();
      });
    });
  }

  Future<void> _fetchMyLocalIps() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      _myLocalIps = interfaces
          .expand((interface) => interface.addresses)
          .map((addr) => addr.address)
          .toList();
      _myLocalIps.add('127.0.0.1');
    } catch (e) {
      print("خطأ في جلب عناوين IP المحلية: $e");
    }
  }

  Future<void> _initNetworkServices() async {
    await _socketServer.startServer(
      localPort,
      onRequestConnection: (callerId, callerName, socket) async {
        await SoundHelper.startRingtone();

        String displayName = await ContactService.getContactName(callerId) ?? callerName;

        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: Text('مكالمة واردة من $displayName'),
              content: const Text('هل تريد الرد على المكالمة؟'),
              actions: [
                TextButton(
                  onPressed: () {
                    SoundHelper.stopRingtone();
                    Navigator.pop(ctx);
                    socket.destroy();
                  },
                  child: const Text('رفض', style: TextStyle(color: Colors.red)),
                ),
                ElevatedButton(
                  onPressed: () {
                    SoundHelper.stopRingtone();
                    Navigator.pop(ctx);
                    _openChatRoom(callerId, socket.remoteAddress.address, localPort);
                  },
                  child: const Text('رد'),
                ),
              ],
            ),
          );
        }
      },
      onMessageReceived: (senderIp, msg) {
        SoundHelper.playNotificationSound();
      },
    );

    await _discoveryService.startBroadcasting(localPort);

    await _discoveryService.startListening((devicesList) async {
      if (!mounted) return;

      setState(() {
        _discoveredDevices.clear();
        for (var service in devicesList) {
          String resolvedIp = service.host ?? '';

          if (resolvedIp.isNotEmpty && !_myLocalIps.contains(resolvedIp)) {
            final deviceName = service.name ?? 'جهاز محلي';
            final port = service.port ?? 4040;

            IdentityService.trustDevice(resolvedIp, deviceName);

            _discoveredDevices[resolvedIp] = {
              'id': deviceName,
              'port': port,
              'ip': resolvedIp,
            };
          }
        }
      });
    });
  }

  /// 📞 حوار حفظ / تعديل جهة الاتصال مع إضافة الرقم اللاسلكي المختصر
  void _showSaveContactDialog(String deviceId, {String currentName = '', String currentExt = ''}) {
    final nameController = TextEditingController(text: currentName);
    final extController = TextEditingController(text: currentExt);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حفظ جهة اتصال'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'اسم الجهة',
                hintText: 'مثال: المكتب الرئيسية',
                icon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: extController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'الرقم اللاسلكي المختصر',
                hintText: 'مثال: 101',
                icon: Icon(Icons.dialpad),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = nameController.text.trim();
              final ext = extController.text.trim();
              if (name.isNotEmpty) {
                await ContactService.saveContact(deviceId, name, extension: ext);
                if (mounted) {
                  Navigator.pop(ctx);
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم حفظ جهة الاتصال بنجاح')),
                  );
                }
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  void _showSavedContactsBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return FutureBuilder<List<ContactModel>>(
          future: ContactService.getAllContacts(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              );
            }

            final contacts = snapshot.data!;
            if (contacts.isEmpty) {
              return const SizedBox(
                height: 200,
                child: Center(child: Text('لا توجد جهات اتصال محفوظة حتى الآن')),
              );
            }

            return Container(
              padding: const EdgeInsets.all(16),
              height: 450,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'جهات الاتصال المحفوظة',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Divider(),
                  Expanded(
                    child: ListView.builder(
                      itemCount: contacts.length,
                      itemBuilder: (context, index) {
                        final contact = contacts[index];
                        final extText = contact.extension.isNotEmpty ? ' | الرقم اللاسلكي: ${contact.extension}' : '';

                        return ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Colors.blueAccent,
                            child: Icon(Icons.person, color: Colors.white),
                          ),
                          title: Text(contact.name),
                          subtitle: Text('معرف: ${contact.deviceId}$extText'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit, color: Colors.blue),
                                onPressed: () {
                                  Navigator.pop(context);
                                  _showSaveContactDialog(
                                    contact.deviceId,
                                    currentName: contact.name,
                                    currentExt: contact.extension,
                                  );
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.redAccent),
                                onPressed: () async {
                                  await ContactService.deleteContact(contact.deviceId);
                                  if (mounted) {
                                    Navigator.pop(context);
                                    setState(() {});
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('تم حذف جهة الاتصال')),
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showCreateGroupDialog() {
    TextEditingController groupNameController = TextEditingController();
    List<String> selectedMembers = [];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('إنشاء مجموعة جديدة'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: groupNameController,
                  decoration: const InputDecoration(
                    labelText: 'اسم المجموعة',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('اختر الأعضاء (الأجهزة المتاحة):',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(
                  height: 150,
                  width: double.maxFinite,
                  child: _discoveredDevices.isEmpty
                      ? const Center(child: Text('لا توجد أجهزة متصلة بالشبكة حالياً'))
                      : ListView(
                          children: _discoveredDevices.entries.map((entry) {
                            String devId = entry.value['id'];
                            bool isSelected = selectedMembers.contains(devId);
                            return CheckboxListTile(
                              title: Text(devId),
                              value: isSelected,
                              onChanged: (val) {
                                setDialogState(() {
                                  if (val == true) {
                                    selectedMembers.add(devId);
                                  } else {
                                    selectedMembers.remove(devId);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () async {
                  String name = groupNameController.text.trim();
                  if (name.isNotEmpty) {
                    await GroupService.createGroup(name, selectedMembers);
                    if (mounted) {
                      Navigator.pop(ctx);
                      setState(() {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('تم إنشاء المجموعة بنجاح')),
                      );
                    }
                  }
                },
                child: const Text('إنشاء'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    SoundHelper.stopRingtone();
    _discoveryService.stop();
    _socketServer.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('المستكشف للاتصالات المحلية'),
        centerTitle: true,
        actions: [
          // 📞 زر لوحة الأرقام اللاسلكية بارز ومبرز بلون واضح
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.green.shade600,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.dialpad, color: Colors.white, size: 22),
                tooltip: 'لوحة الأرقام اللاسلكية',
                onPressed: () {
                  List<DiscoveredService> services = _discoveredDevices.entries.map((e) {
                    return DiscoveredService(
                      name: e.value['id'],
                      host: e.key,
                      port: e.value['port'],
                    );
                  }).toList();

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => DialpadScreen(activeDevices: services),
                    ),
                  );
                },
              ),
            ),
          ),
          // 👥 زر إنشاء مجموعة جديدة
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.orange.shade700,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.group_add, color: Colors.white, size: 22),
                tooltip: 'إنشاء مجموعة جديدة',
                onPressed: _showCreateGroupDialog,
              ),
            ),
          ),
          // 📖 زر جهات الاتصال المحفوظة
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.indigo.shade600,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.contacts, color: Colors.white, size: 22),
                tooltip: 'جهات الاتصال المحفوظة',
                onPressed: _showSavedContactsBottomSheet,
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Colors.blue.shade50,
            padding: const EdgeInsets.all(12),
            child: const Row(
              children: [
                Icon(Icons.wifi, color: Colors.blue),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'متصل بالشبكة المحلية - جميع الأجهزة متصلة وموثوقة تلقائياً',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          FutureBuilder<List<GroupModel>>(
            future: GroupService.getGroups(),
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                List<GroupModel> groups = snapshot.data!;
                return Container(
                  color: Colors.grey.shade100,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: Text(
                          'المجموعات المحلية:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blueGrey,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 70,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: groups.length,
                          itemBuilder: (context, index) {
                            var group = groups[index];
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              child: ActionChip(
                                avatar: const CircleAvatar(
                                  backgroundColor: Colors.blue,
                                  child: Icon(Icons.group, color: Colors.white, size: 16),
                                ),
                                label: Text(group.groupName),
                                onPressed: () {
                                  Map<String, String> activeIps = {};
                                  _discoveredDevices.forEach((ip, data) {
                                    activeIps[data['id']] = ip;
                                  });

                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => GroupChatScreen(
                                        group: group,
                                        activeDeviceIps: activeIps,
                                      ),
                                    ),
                                  ).then((_) {
                                    if (mounted) setState(() {});
                                  });
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          const Divider(height: 1),
          Expanded(
            child: _discoveredDevices.isEmpty
                ? const Center(child: Text('جاري البحث عن أجهزة متصلة بالشبكة...'))
                : ListView.builder(
                    itemCount: _discoveredDevices.length,
                    itemBuilder: (context, index) {
                      String targetIp = _discoveredDevices.keys.elementAt(index);
                      var deviceData = _discoveredDevices[targetIp]!;
                      String deviceId = deviceData['id'];

                      return FutureBuilder<String?>(
                        future: ContactService.getContactName(deviceId),
                        builder: (context, snapshot) {
                          String displayName = (snapshot.hasData &&
                                  snapshot.data != null &&
                                  snapshot.data!.isNotEmpty)
                              ? snapshot.data!
                              : deviceId;

                          return ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: Colors.green,
                              child: Icon(Icons.person, color: Colors.white),
                            ),
                            title: Text('$displayName (موثوق)'),
                            subtitle: Text('$targetIp:${deviceData['port']}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.bookmark_add, color: Colors.orange),
                                  tooltip: 'حفظ كجهة اتصال',
                                  onPressed: () => _showSaveContactDialog(deviceId, currentName: displayName),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.chat, color: Colors.blue, size: 28),
                                  onPressed: () {
                                    _openChatRoom(deviceId, targetIp, deviceData['port']);
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _openChatRoom(String deviceId, String targetIp, int port) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatDetailScreen(
          targetDeviceId: deviceId,
          targetHost: targetIp,
          targetPort: port,
        ),
      ),
    ).then((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }
}
