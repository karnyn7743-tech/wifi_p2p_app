import 'package:flutter/material.dart';
import 'dart:io';
import '../services/identity_service.dart';
import '../services/network_discovery_service.dart';
import '../services/p2p_socket_server.dart';
import '../services/contact_service.dart';
import '../services/audio_helper.dart';
import '../services/background_service.dart'; // ⚡ استيراد خدمة الخلفية
import 'chat_detail_screen.dart';
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
    // 🔋 1. طلب استثناء البطارية
    disableBatteryOptimization();

    // 📡 2. فحص حالة الواي فاي وتحديث خدمة الخلفية والإشعار
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
    // 📞 3. تفعيل السيرفر المحلي وربط النغمات والمكالمات الواردة
    await _socketServer.startServer(
      localPort,
      onRequestConnection: (callerId, callerName, socket) async {
        // 🔔 تشغيل نغمة الرنين فور استقبال اتصال
        await SoundHelper.startRingtone();

        // إظهار حوار مكالمة واردة باسم جهة الاتصال أو المعرف
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
                    SoundHelper.stopRingtone(); // إيقاف الرنين عند الرفض
                    Navigator.pop(ctx);
                    socket.destroy();
                  },
                  child: const Text('رفض', style: TextStyle(color: Colors.red)),
                ),
                ElevatedButton(
                  onPressed: () {
                    SoundHelper.stopRingtone(); // إيقاف الرنين عند القبول
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
        // 🔔 تشغيل صوت التنبيه فور وصول رسالة جديدة
        SoundHelper.playNotificationSound();
      },
    );

    // 🚀 4. بدء اكتشاف الأجهزة بسرعة بث UDP Broadcast
    await _discoveryService.startBroadcasting(localPort);

    await _discoveryService.startListening((service) async {
      String resolvedIp = service.host ?? '';

      if (resolvedIp.isNotEmpty) {
        try {
          final addresses = await InternetAddress.lookup(resolvedIp);
          if (addresses.isNotEmpty) {
            resolvedIp = addresses.first.address;
          }
        } catch (_) {}

        if (!_myLocalIps.contains(resolvedIp)) {
          final deviceName = service.name ?? 'جهاز محلي';
          final port = service.port ?? 4040;

          await IdentityService.trustDevice(resolvedIp, deviceName);

          if (mounted) {
            setState(() {
              _discoveredDevices[resolvedIp] = {
                'id': deviceName, // المعرف الفريد للجهاز (deviceId)
                'port': port,
                'ip': resolvedIp,
              };
            });
          }
        }
      }
    });
  }

  void _showSavedContactsBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return FutureBuilder<Map<String, String>>(
          future: ContactService.getContacts(),
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
              height: 400,
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
                        String deviceId = contacts.keys.elementAt(index);
                        String savedName = contacts.values.elementAt(index);

                        return ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Colors.blueAccent,
                            child: Icon(Icons.person, color: Colors.white),
                          ),
                          title: Text(savedName),
                          subtitle: Text('معرف الجهاز: $deviceId'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.redAccent),
                            onPressed: () async {
                              await ContactService.deleteContact(deviceId);
                              if (mounted) {
                                Navigator.pop(context);
                                setState(() {});
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('تم حذف جهة الاتصال')),
                                );
                              }
                            },
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
          IconButton(
            icon: const Icon(Icons.contacts, color: Colors.white),
            tooltip: 'جهات الاتصال المحفوظة',
            onPressed: _showSavedContactsBottomSheet,
          ),
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
                            trailing: IconButton(
                              icon: const Icon(Icons.chat, color: Colors.blue, size: 28),
                              onPressed: () {
                                _openChatRoom(deviceId, targetIp, deviceData['port']);
                              },
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
