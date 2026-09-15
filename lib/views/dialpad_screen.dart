import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/io.dart';
import '../services/contact_service.dart';
import '../services/network_discovery_service.dart';
import 'chat_detail_screen.dart';

class DialpadScreen extends StatefulWidget {
  final List<DiscoveredService> activeDevices;

  const DialpadScreen({Key? key, required this.activeDevices}) : super(key: key);

  @override
  State<DialpadScreen> createState() => _DialpadScreenState();
}

class _DialpadScreenState extends State<DialpadScreen> {
  String _enteredNumber = '';

  void _onKeyPress(String value) {
    if (_enteredNumber.length < 6) {
      setState(() {
        _enteredNumber += value;
      });
    }
  }

  void _onBackspace() {
    if (_enteredNumber.isNotEmpty) {
      setState(() {
        _enteredNumber = _enteredNumber.substring(0, _enteredNumber.length - 1);
      });
    }
  }

  Future<void> _makeCall() async {
    if (_enteredNumber.isEmpty) return;

    // 1. البحث عن الرقم اللاسلكي في الدفتر المحفوظ محلياً
    ContactModel? contact = await ContactService.getContactByExtension(_enteredNumber);

    // 2. إذا وجد في جهات الاتصال، نبحث عن الجهاز في قائمة الأجهزة المتاحة P2P
    if (contact != null) {
      DiscoveredService? targetDevice;
      try {
        targetDevice = widget.activeDevices.firstWhere(
          (device) => device.name == contact.deviceId || device.host == contact.deviceId,
        );
      } catch (_) {}

      if (targetDevice != null && targetDevice.host != null) {
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatDetailScreen(
                targetDeviceId: contact.deviceId,
                targetHost: targetDevice!.host!,
                targetPort: targetDevice.port ?? 4040,
              ),
            ),
          );
        }
        return;
      }
    }

    // 3. إذا لم يوجد بجهة اتصال أو كان جهاز P2P غير مكتشف، نحاول الاتصال به عبر السيرفر المحلي (PBX Routing)
    final prefs = await SharedPreferences.getInstance();
    String? serverIp = prefs.getString('server_ip');

    if (serverIp != null && serverIp.isNotEmpty) {
      if (mounted) {
        // فتح شاشة التحدث المباشر مع تحويل الاتصال عبر السيرفر المركزي/المدمج
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatDetailScreen(
              targetDeviceId: 'ext_$_enteredNumber',
              targetHost: serverIp,
              targetPort: 4040,
            ),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(contact != null
                ? 'الجهاز (${contact.name}) غير متصل بالشبكة حالياً'
                : 'الرقم الداخلي $_enteredNumber غير متصل بالسيرفر المحلي'),
          ),
        );
      }
    }
  }

  Widget _buildDialButton(String label) {
    return InkWell(
      onTap: () => _onKeyPress(label),
      borderRadius: BorderRadius.circular(40),
      child: Container(
        width: 70,
        height: 70,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.grey.shade200,
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة الأرقام اللاسلكية'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          const SizedBox(height: 30),
          // شاشة عرض الرقم المدخل
          Text(
            _enteredNumber.isEmpty ? 'أدخل الرقم المختصر' : _enteredNumber,
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: _enteredNumber.isEmpty ? Colors.grey : Colors.black,
            ),
          ),
          const Spacer(),
          // صفوف لوحة الأرقام
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [_buildDialButton('1'), _buildDialButton('2'), _buildDialButton('3')],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [_buildDialButton('4'), _buildDialButton('5'), _buildDialButton('6')],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [_buildDialButton('7'), _buildDialButton('8'), _buildDialButton('9')],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              const SizedBox(width: 70),
              _buildDialButton('0'),
              IconButton(
                iconSize: 32,
                icon: const Icon(Icons.backspace, color: Colors.grey),
                onPressed: _onBackspace,
              ),
            ],
          ),
          const SizedBox(height: 30),
          // زر الاتصال اللاسلكي الأخضر
          FloatingActionButton.large(
            onPressed: _makeCall,
            backgroundColor: Colors.green,
            child: const Icon(Icons.phone, size: 36, color: Colors.white),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
