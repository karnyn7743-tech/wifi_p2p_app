import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'chat_detail_screen.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({Key? key}) : super(key: key);

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _isProcessing = false;

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;

    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      final String? rawValue = barcode.rawValue;
      if (rawValue != null && rawValue.isNotEmpty) {
        try {
          final Map<String, dynamic> data = jsonDecode(rawValue);

          // التحقق من صيغة الرمز الخاصة بتطبيق LanPhone
          if (data['type'] == 'LANPHONE_PAIR' && data.containsKey('ip')) {
            _isProcessing = true;
            _controller.stop();

            final String targetIp = data['ip'];
            final int targetPort = data['port'] ?? 4040;
            final String targetPhone = data['phone'] ?? '10000';
            final String targetName = data['name'] ?? 'جهاز مقترن';

            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => ChatDetailScreen(
                  targetDeviceId: targetPhone,
                  targetHost: targetIp,
                  targetPort: targetPort,
                ),
              ),
            );
            break;
          }
        } catch (_) {
          // تجاهل الرموز غير المتوافقة
        }
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مسح رمز الاقتران'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.greenAccent, width: 3),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          const Positioned(
            bottom: 40,
            child: Text(
              'وجّه الكاميرا نحو رمز QR على الجهاز الآخر',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                backgroundColor: Colors.black54,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
