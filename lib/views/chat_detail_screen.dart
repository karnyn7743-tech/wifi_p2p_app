import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/p2p_socket_server.dart';
import '../services/webrtc_service.dart';
import '../services/contact_service.dart';
import '../services/encryption_service.dart';

class ChatDetailScreen extends StatefulWidget {
  final String targetDeviceId;
  final String targetHost;
  final int targetPort;

  const ChatDetailScreen({
    Key? key,
    required this.targetDeviceId,
    required this.targetHost,
    required this.targetPort,
  }) : super(key: key);

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final TextEditingController _msgController = TextEditingController();
  final List<Map<String, String>> _messages = [];
  final WebRTCService _webrtcService = WebRTCService();
  
  // ⚡ اشتراك الستريم لمنع التسريب والخلط بين الجلسات
  StreamSubscription<String>? _messageSubscription;

  String _displayName = '';
  bool _inCall = false;
  bool _isVideoCall = false;

  @override
  void initState() {
    super.initState();
    // إظهار ID الجهاز كاسم افتراضي
    _displayName = widget.targetDeviceId;
    _loadSavedContactName();

    // ربط الستريم مع حفظ المرجع لإغلاقه عند الخروج
    _messageSubscription = P2PSocketServer.messageStream.listen((data) {
      _handleIncomingData(data);
    });
  }

  Future<void> _loadSavedContactName() async {
    // جلب الاسم المحفوظ باستخدام DeviceID حصراً مع إزالة أي مسافات
    String? savedName = await ContactService.getContactName(widget.targetDeviceId.trim());

    if (savedName != null && savedName.isNotEmpty) {
      if (mounted) {
        setState(() {
          _displayName = savedName;
        });
      }
    }
  }

  void _handleIncomingData(String rawData) async {
    if (!mounted) return;

    try {
      final decoded = jsonDecode(rawData);

      if (decoded is Map<String, dynamic> && decoded.containsKey('type')) {
        String type = decoded['type'];

        if (type == 'offer') {
          P2PSocketServer.playRingtone(loop: true);
          _showIncomingCallDialog(
            isVideo: decoded['isVideo'] ?? false,
            sdp: decoded['sdp'],
          );
          return;
        } else if (type == 'answer') {
          P2PSocketServer.stopRingtone();
          await _webrtcService.handleAnswer(decoded['sdp']);
          if (mounted) setState(() {});
          return;
        } else if (type == 'candidate') {
          await _webrtcService.handleCandidate(decoded['candidate']);
          return;
        } else if (type == 'hangup') {
          P2PSocketServer.stopRingtone();
          await _webrtcService.dispose();
          if (mounted) {
            setState(() {
              _inCall = false;
            });
          }
          return;
        }
      }
    } catch (_) {}

    if (rawData != "CONNECT_ACCEPTED" && rawData.isNotEmpty) {
      // 🔓 فك تشفير الرسالة النصية الواردة فور استلامها
      String decryptedText = EncryptionService.decryptText(rawData);

      P2PSocketServer.playRingtone(loop: false);

      if (mounted) {
        setState(() {
          _messages.add({
            'sender': _displayName, // يعرض الاسم المحفوظ الخاص بهذه الشاشة حصراً
            'text': decryptedText,
          });
        });
      }
    }
  }

  void _showIncomingCallDialog({required bool isVideo, required String sdp}) {
    HapticFeedback.vibrate();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.grey.shade900,
          title: Text(
            'مكالمة ${isVideo ? "فيديو" : "صوتية"} واردة',
            style: const TextStyle(color: Colors.white),
          ),
          content: Text(
            'يتصل بك: $_displayName',
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                P2PSocketServer.stopRingtone();
                Navigator.of(context).pop();
                await _webrtcService.hangup(widget.targetHost, widget.targetPort);
              },
              child: const Text('رفض', style: TextStyle(color: Colors.redAccent, fontSize: 18)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              onPressed: () async {
                P2PSocketServer.stopRingtone();
                Navigator.of(context).pop();
                setState(() {
                  _inCall = true;
                  _isVideoCall = isVideo;
                });
                await _webrtcService.handleOfferAndAnswer(
                  sdp,
                  widget.targetHost,
                  widget.targetPort,
                  isVideo,
                );
                setState(() {});
              },
              child: const Text('رد', style: TextStyle(color: Colors.white, fontSize: 18)),
            ),
          ],
        );
      },
    );
  }

  void _showSaveContactDialog() {
    TextEditingController nameController = TextEditingController(text: _displayName != widget.targetDeviceId ? _displayName : '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حفظ جهة الاتصال'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'المعرف (ID): ${widget.targetDeviceId}',
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'الاسم المخصص للجهاز',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              String newName = nameController.text.trim();
              if (newName.isNotEmpty) {
                // حفظ الاسم بربطه بالـ DeviceID بعد التنظيف
                await ContactService.saveContact(widget.targetDeviceId.trim(), newName);
                if (mounted) {
                  setState(() {
                    _displayName = newName;
                  });
                }
              }
              if (mounted) Navigator.pop(context);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  void _startCall({required bool isVideo}) async {
    setState(() {
      _inCall = true;
      _isVideoCall = isVideo;
    });
    await _webrtcService.makeCall(widget.targetHost, widget.targetPort, isVideo);
    setState(() {});
  }

  void _endCall() async {
    P2PSocketServer.stopRingtone();
    await _webrtcService.hangup(widget.targetHost, widget.targetPort);
    if (mounted) {
      setState(() {
        _inCall = false;
      });
    }
  }

  void _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add({'sender': 'me', 'text': text});
    });

    _msgController.clear();

    String encryptedText = EncryptionService.encryptText(text);

    await P2PSocketServer.sendMessageToHost(
      widget.targetHost,
      widget.targetPort,
      encryptedText,
    );
  }

  @override
  void dispose() {
    // 🛑 إلغاء اشتراك الستريم فور الخروج من الشاشة لمنع تداخل الأسماء مع الشاشات الأخرى
    _messageSubscription?.cancel();
    P2PSocketServer.stopRingtone();
    _webrtcService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_displayName),
        actions: [
          IconButton(
            icon: const Icon(Icons.bookmark_add, color: Colors.orange),
            onPressed: _showSaveContactDialog,
          ),
          IconButton(
            icon: const Icon(Icons.phone, color: Colors.green),
            onPressed: () => _startCall(isVideo: false),
          ),
          IconButton(
            icon: const Icon(Icons.videocam, color: Colors.blue),
            onPressed: () => _startCall(isVideo: true),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final msg = _messages[index];
                    final isMe = msg['sender'] == 'me';

                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isMe ? Colors.blue.shade200 : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          msg['text'] ?? '',
                          style: const TextStyle(fontSize: 16, color: Colors.black87),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                color: Colors.white,
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _msgController,
                        decoration: const InputDecoration(
                          hintText: 'اكتب رسالتك هنا...',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.send, color: Colors.blue),
                      onPressed: _sendMessage,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_inCall) _buildFullCallOverlay(),
        ],
      ),
    );
  }

  Widget _buildFullCallOverlay() {
    return Positioned.fill(
      child: Container(
        color: Colors.black,
        child: Stack(
          children: [
            if (_isVideoCall) ...[
              Positioned.fill(
                child: RTCVideoView(_webrtcService.remoteRenderer),
              ),
              Positioned(
                right: 20,
                top: 40,
                width: 110,
                height: 160,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: RTCVideoView(_webrtcService.localRenderer, mirror: true),
                ),
              ),
            ] else
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircleAvatar(
                      radius: 50,
                      backgroundColor: Colors.blueAccent,
                      child: Icon(Icons.person, size: 50, color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _displayName,
                      style: const TextStyle(color: Colors.white, fontSize: 22),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'مكالمة صوتية جارية...',
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                  ],
                ),
              ),
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Center(
                child: FloatingActionButton(
                  backgroundColor: Colors.red,
                  onPressed: _endCall,
                  child: const Icon(Icons.call_end, size: 32, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
