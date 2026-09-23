import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

class QrCodeDialog extends StatelessWidget {
  final String ip;
  final int port;
  final String phoneNumber;
  final String deviceName;

  const QrCodeDialog({
    Key? key,
    required this.ip,
    required this.port,
    required this.phoneNumber,
    required this.deviceName,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // تجهيز حمولة الـ JSON التي ستقرأها كاميرا الجهاز الآخر
    final Map<String, dynamic> qrPayload = {
      'type': 'LANPHONE_PAIR',
      'ip': ip,
      'port': port,
      'phone': phoneNumber,
      'name': deviceName,
    };

    final String qrData = jsonEncode(qrPayload);

    return AlertDialog(
      title: const Center(
        child: Text(
          'رمز الاقتران المباشر',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 8,
                ),
              ],
            ),
            child: QrImageView(
              data: qrData,
              version: QrVersions.auto,
              size: 220.0,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'الرقم اللاسلكي: $phoneNumber',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.indigo,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'IP: $ip:$port',
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
        ],
      ),
      actions: [
        Center(
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق', style: TextStyle(fontSize: 16)),
          ),
        ),
      ],
    );
  }
}
