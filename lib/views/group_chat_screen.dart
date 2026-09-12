import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../services/group_service.dart';
import '../services/p2p_socket_server.dart';
import '../services/encryption_service.dart';
import '../services/audio_recorder_service.dart';

class GroupChatScreen extends StatefulWidget {
  final GroupModel group;
  final Map<String, String> activeDeviceIps; // قائمة الأجهزة المتصلة حالياً بالشبكة [deviceId : IP]

  const GroupChatScreen({
    Key? key,
    required this.group,
    required this.activeDeviceIps,
  }) : super(key: key);

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final TextEditingController _msgController = TextEditingController();
  final List<Map<String, String>> _groupMessages = [];
  final AudioRecorderService _recorderService = AudioRecorderService();
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    // الاستماع للرسائل الواردة الموجهة للمجموعة
    P2PSocketServer.messageStream.listen((rawData) {
      _handleIncomingGroupData(rawData);
    });
  }

  void _handleIncomingGroupData(String rawData) {
    try {
      final decoded = jsonDecode(rawData);
      if (decoded is Map<String, dynamic> && decoded['groupId'] == widget.group.groupId) {
        if (mounted) {
          setState(() {
            _groupMessages.add({
              'sender': decoded['senderName'] ?? 'عضو',
              'text': decoded['message'] ?? '',
              'type': decoded['type'] ?? 'text',
            });
          });
        }
      }
    } catch (_) {}
  }

  /// إرسال رسالة نصية لجميع أعضاء المجموعة المتصلين حالياً بالشبكة المحلية
  void _sendGroupMessage() async {
    String text = _msgController.text.trim();
    if (text.isEmpty) return;

    _msgController.clear();

    setState(() {
      _groupMessages.add({'sender': 'أنا', 'text': text, 'type': 'text'});
    });

    String encryptedMessage = EncryptionService.encryptText(text);

    Map<String, dynamic> payload = {
      'groupId': widget.group.groupId,
      'senderName': 'عضو',
      'message': encryptedMessage,
      'type': 'text',
    };

    String dataToSend = jsonEncode(payload);

    // البث الجماعي (Multi-unicast) للأعضاء الموجودين على شبكة الواي فاي
    for (String deviceId in widget.group.memberDeviceIds) {
      if (widget.activeDeviceIps.containsKey(deviceId)) {
        String ip = widget.activeDeviceIps[deviceId]!;
        await P2PSocketServer.sendMessageToHost(ip, 4040, dataToSend);
      }
    }
  }

  /// التعامل مع تسجيل وإرسال المقاطع الصوتية
  void _toggleAudioRecording() async {
    if (!_isRecording) {
      await _recorderService.startRecording();
      setState(() => _isRecording = true);
    } else {
      String? path = await _recorderService.stopRecording();
      setState(() => _isRecording = false);

      if (path != null) {
        File audioFile = File(path);
        List<int> bytes = await audioFile.readAsBytes();
        String base64Audio = base64Encode(bytes);

        // إرسال المقطع المرمز
        Map<String, dynamic> payload = {
          'groupId': widget.group.groupId,
          'senderName': 'أنا',
          'message': base64Audio,
          'type': 'audio',
        };

        String dataToSend = jsonEncode(payload);

        for (String deviceId in widget.group.memberDeviceIds) {
          if (widget.activeDeviceIps.containsKey(deviceId)) {
            String ip = widget.activeDeviceIps[deviceId]!;
            await P2PSocketServer.sendMessageToHost(ip, 4040, dataToSend);
          }
        }

        setState(() {
          _groupMessages.add({'sender': 'أنا', 'text': 'مقطع صوتي 🎵', 'type': 'audio'});
        });
      }
    }
  }

  /// بدء بث مباشر / مكالمة فيديو جماعية بشرط عدم تجاوز 5 أعضاء
  void _startGroupVideoCall() {
    int activeMembersCount = widget.group.memberDeviceIds
        .where((id) => widget.activeDeviceIps.containsKey(id))
        .length;

    if (activeMembersCount > 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('عذراً، البث المباشر والمكالمات الجماعية متاحة لـ 5 أعضاء أو أقل فقط.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    // الانتقال لشاشة البث الجماعي
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('جاري بدء البث المباشر/المكالمة الجماعية...')),
    );
  }

  @override
  Widget build(BuildContext context) {
    int onlineCount = widget.group.memberDeviceIds
        .where((id) => widget.activeDeviceIps.containsKey(id))
        .length;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.group.groupName),
            Text(
              'الأعضاء: ${widget.group.memberDeviceIds.length} | المتصلون الآن: $onlineCount',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          // إظهار زر الفيديو الجماعي
          IconButton(
            icon: Icon(
              Icons.videocam,
              color: onlineCount <= 5 ? Colors.greenAccent : Colors.grey,
            ),
            tooltip: 'بث مباشر / مكالمة جماعية (حتى 5 أعضاء)',
            onPressed: _startGroupVideoCall,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _groupMessages.length,
              itemBuilder: (context, index) {
                final msg = _groupMessages[index];
                bool isMe = msg['sender'] == 'أنا';

                return Align(
                  alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isMe ? Colors.blue.shade100 : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment:
                          isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      children: [
                        Text(
                          msg['sender']!,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          msg['text']!,
                          style: const TextStyle(fontSize: 15),
                        ),
                      ],
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
                IconButton(
                  icon: Icon(
                    _isRecording ? Icons.stop_circle : Icons.mic,
                    color: _isRecording ? Colors.red : Colors.blue,
                  ),
                  onPressed: _toggleAudioRecording,
                ),
                Expanded(
                  child: TextField(
                    controller: _msgController,
                    decoration: const InputDecoration(
                      hintText: 'اكتب رسالة للمجموعة...',
                      border: InputBorder.none,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.blue),
                  onPressed: _sendGroupMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
