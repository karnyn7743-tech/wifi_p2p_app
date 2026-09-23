import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart'; // 🎙️ حزمة تسجيل الصوت
import 'package:audioplayers/audioplayers.dart'; // 🔊 حزمة تشغيل الصوت
import 'package:path_provider/path_provider.dart';
import '../services/p2p_socket_server.dart';
import '../services/webrtc_service.dart';
import '../services/contact_service.dart';
import '../services/encryption_service.dart';
import '../services/file_transfer_service.dart';
import '../services/chat_storage_service.dart'; // 💾 خدمة التخزين المحلي للرسائل
import '../services/block_service.dart'; // 🚫 خدمة حظر الأجهزة

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
  final ScrollController _scrollController = ScrollController();
  
  StreamSubscription<String>? _messageSubscription;

  String _displayName = '';
  String _displayExtension = '';
  bool _inCall = false;
  bool _isVideoCall = false;
  bool _isBlocked = false; // 🚫 حالة حظر الجهاز الحالي

  double _uploadProgress = 0.0;
  bool _isUploading = false;

  // 🎙️ أدوات الرسائل الصوتية
  late final AudioRecorder _audioRecorder;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isRecording = false;
  int _recordDuration = 0;
  Timer? _recordTimer;
  String? _currentlyPlayingPath;
  bool _isPlayingAudio = false;

  @override
  void initState() {
    super.initState();
    _audioRecorder = AudioRecorder();

    _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isPlayingAudio = false;
          _currentlyPlayingPath = null;
        });
      }
    });
    
    // التعامل مع الأرقام الداخليّة المقدمة من السيرفر المدمج
    if (widget.targetDeviceId.startsWith('ext_')) {
      _displayExtension = widget.targetDeviceId.replaceFirst('ext_', '');
      _displayName = 'رقم داخلي: $_displayExtension';
    } else {
      _displayName = widget.targetDeviceId;
    }
    
    _loadSavedContactName();
    _checkBlockStatus(); // 🚫 التحقق من حالة الحظر
    _loadChatHistory(); // 💾 استرجاع الرسائل المحفوظة مسبقاً

    _messageSubscription = P2PSocketServer.messageStream.listen((data) {
      _handleIncomingData(data);
    });
  }

  /// 🚫 فحص ما إذا كان الجهاز محظوراً
  Future<void> _checkBlockStatus() async {
    bool blocked = await BlockService.isBlocked(widget.targetDeviceId) ||
                   await BlockService.isBlocked(widget.targetHost);
    if (mounted) {
      setState(() {
        _isBlocked = blocked;
      });
    }
  }

  /// 🚫 تبديل حالة الحظر
  Future<void> _toggleBlockDevice() async {
    if (_isBlocked) {
      await BlockService.unblockDevice(widget.targetDeviceId);
      await BlockService.unblockDevice(widget.targetHost);
      setState(() {
        _isBlocked = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إلغاء حظر الجهاز بنجاح')),
        );
      }
    } else {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('تأكيد الحظر'),
          content: Text('هل أنت متأكد من حظر $_displayName؟ لن تتمكن من مراسلته أو تلقي مكالمات ورسائل منه.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                Navigator.pop(ctx);
                await BlockService.blockDevice(widget.targetDeviceId);
                await BlockService.blockDevice(widget.targetHost);
                setState(() {
                  _isBlocked = true;
                });
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم حظر هذا الجهاز')),
                  );
                }
              },
              child: const Text('حظر', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }
  }

  /// 💾 تحميل السجل المخزن محلياً
  Future<void> _loadChatHistory() async {
    final history = await ChatStorageService.getMessages(widget.targetDeviceId);
    if (mounted) {
      setState(() {
        _messages.clear();
        _messages.addAll(history);
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _loadSavedContactName() async {
    List<ContactModel> allContacts = await ContactService.getAllContacts();
    try {
      final contact = allContacts.firstWhere(
        (c) => c.deviceId.trim() == widget.targetDeviceId.trim() ||
               c.extension.trim() == _displayExtension.trim(),
      );
      if (mounted) {
        setState(() {
          if (contact.name.isNotEmpty) _displayName = contact.name;
          if (contact.extension.isNotEmpty) _displayExtension = contact.extension;
        });
      }
    } catch (_) {}
  }

  void _handleIncomingData(String rawData) async {
    if (!mounted || _isBlocked) return;

    try {
      final decoded = jsonDecode(rawData);

      if (decoded is Map<String, dynamic> && decoded.containsKey('type')) {
        String type = decoded['type'];

        // إيصال استلام وقراءة الرسالة (✓✓)
        if (type == 'ACK_DELIVERED') {
          String? msgId = decoded['msgId'];
          if (msgId != null) {
            setState(() {
              for (var msg in _messages) {
                if (msg['id'] == msgId) {
                  msg['status'] = 'read';
                }
              }
            });
          }
          return;
        } else if (type == 'offer' || type == 'call_offer') {
          P2PSocketServer.playRingtone(loop: true);
          _showIncomingCallDialog(
            isVideo: decoded['isVideo'] ?? false,
            sdp: decoded['sdp'] ?? '',
          );
          return;
        } else if (type == 'answer' || type == 'call_answer') {
          P2PSocketServer.stopRingtone();
          if (decoded.containsKey('sdp')) {
            await _webrtcService.handleAnswer(decoded['sdp']);
          }
          if (mounted) setState(() {});
          return;
        } else if (type == 'candidate' || type == 'ice_candidate') {
          if (decoded.containsKey('candidate')) {
            await _webrtcService.handleCandidate(decoded['candidate']);
          }
          return;
        } else if (type == 'hangup' || type == 'CALL_REJECTED') {
          P2PSocketServer.stopRingtone();
          await _cleanCallSession();
          return;
        } else if (type == 'CALL_ACCEPTED') {
          P2PSocketServer.stopRingtone();
          if (mounted) setState(() {});
          return;
        }
      }
    } catch (_) {}

    if (rawData != "CONNECT_ACCEPTED" && rawData.isNotEmpty) {
      String decryptedText = EncryptionService.decryptText(rawData);

      // استخراج معرّف الرسالة إن وجد لإرسال إيصال الاستلام
      String incomingMsg = decryptedText;
      String incomingId = DateTime.now().millisecondsSinceEpoch.toString();

      if (decryptedText.startsWith("MSG|")) {
        final parts = decryptedText.split("|");
        if (parts.length >= 3) {
          incomingId = parts[1];
          incomingMsg = parts.sublist(2).join("|");
        }
      }

      // إرسال إيصال الاستلام للطرف الآخر
      final ackPayload = jsonEncode({'type': 'ACK_DELIVERED', 'msgId': incomingId});
      P2PSocketServer.sendMessageToHost(widget.targetHost, widget.targetPort, ackPayload);

      P2PSocketServer.playRingtone(loop: false);

      final newMsg = {
        'id': incomingId,
        'sender': _displayName,
        'text': incomingMsg,
        'type': incomingMsg.startsWith('VOICE_NOTE:') ? 'voice' : 'text',
        'status': 'read',
        'time': "${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}",
      };

      await ChatStorageService.saveMessage(widget.targetDeviceId, newMsg);

      if (mounted) {
        setState(() {
          _messages.add(newMsg);
        });
        _scrollToBottom();
      }
    }
  }

  Future<void> _cleanCallSession() async {
    P2PSocketServer.stopRingtone();
    await _webrtcService.dispose();
    if (mounted) {
      setState(() {
        _inCall = false;
      });
    }
  }

  void _showIncomingCallDialog({required bool isVideo, required String sdp}) {
    if (_isBlocked) return;
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
                Navigator.of(context).pop();
                await _webrtcService.hangup(widget.targetHost, widget.targetPort);
                await _cleanCallSession();
              },
              child: const Text('رفض', style: TextStyle(color: Colors.redAccent, fontSize: 18)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              onPressed: () async {
                P2PSocketServer.stopRingtone();
                Navigator.of(context).pop();
                
                await _webrtcService.dispose();

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
                if (mounted) setState(() {});
              },
              child: const Text('رد', style: TextStyle(color: Colors.white, fontSize: 18)),
            ),
          ],
        );
      },
    );
  }

  void _showSaveContactDialog() async {
    ContactModel? existingContact;
    List<ContactModel> allContacts = await ContactService.getAllContacts();
    try {
      existingContact = allContacts.firstWhere(
        (c) => c.deviceId.trim() == widget.targetDeviceId.trim() ||
               (_displayExtension.isNotEmpty && c.extension.trim() == _displayExtension.trim()),
      );
    } catch (_) {}

    TextEditingController nameController = TextEditingController(
      text: existingContact?.name ?? (_displayName != widget.targetDeviceId ? _displayName : ''),
    );
    TextEditingController extController = TextEditingController(
      text: existingContact?.extension ?? _displayExtension,
    );

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حفظ جهة الاتصال'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'المعرف: ${widget.targetDeviceId}',
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
            const SizedBox(height: 12),
            TextField(
              controller: extController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'الرقم اللاسلكي المختصر',
                hintText: 'مثال: 101',
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
              String newExt = extController.text.trim();
              if (newName.isNotEmpty) {
                await ContactService.saveContact(
                  widget.targetDeviceId.trim(),
                  newName,
                  extension: newExt,
                );
                await _loadSavedContactName();
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
    if (_isBlocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يمكن الاتصال بجهاز محظور')),
      );
      return;
    }

    await _cleanCallSession();

    setState(() {
      _inCall = true;
      _isVideoCall = isVideo;
    });

    await _webrtcService.makeCall(widget.targetHost, widget.targetPort, isVideo);
    if (mounted) setState(() {});
  }

  void _endCall() async {
    await _webrtcService.hangup(widget.targetHost, widget.targetPort);
    await _cleanCallSession();
  }

  void _sendMessage() async {
    if (_isBlocked) return;

    final text = _msgController.text.trim();
    if (text.isEmpty) return;

    final String msgId = DateTime.now().millisecondsSinceEpoch.toString();
    final String timeStr = "${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}";

    final newMsg = {
      'id': msgId,
      'sender': 'me',
      'text': text,
      'type': 'text',
      'status': 'sent',
      'time': timeStr,
    };

    setState(() {
      _messages.add(newMsg);
    });

    _msgController.clear();
    _scrollToBottom();

    await ChatStorageService.saveMessage(widget.targetDeviceId, newMsg);

    String payload = "MSG|$msgId|$text";
    String encryptedText = EncryptionService.encryptText(payload);

    bool delivered = await P2PSocketServer.sendMessageToHost(
      widget.targetHost,
      widget.targetPort,
      encryptedText,
    );

    if (delivered && mounted) {
      setState(() {
        newMsg['status'] = 'delivered';
      });
    }
  }

  // 🎙️ بدء تسجيل الصوت
  Future<void> _startRecording() async {
    if (_isBlocked) return;
    try {
      if (await _audioRecorder.hasPermission()) {
        final directory = await getTemporaryDirectory();
        final filePath = '${directory.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc),
          path: filePath,
        );

        setState(() {
          _isRecording = true;
          _recordDuration = 0;
        });

        _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (mounted) {
            setState(() {
              _recordDuration++;
            });
          }
        });
      }
    } catch (e) {
      print("خطأ بدء التسجيل: $e");
    }
  }

  // 🛑 إيقاف التسجيل وإرساله فوراً عبر P2P
  Future<void> _stopAndSendRecording() async {
    _recordTimer?.cancel();
    try {
      final path = await _audioRecorder.stop();
      setState(() {
        _isRecording = false;
      });

      if (path != null && File(path).existsSync()) {
        File voiceFile = File(path);
        String fileName = path.split('/').last;

        setState(() {
          _isUploading = true;
          _uploadProgress = 0.0;
        });

        bool success = await FileTransferService.sendFile(
          targetHost: widget.targetHost,
          targetPort: widget.targetPort,
          file: voiceFile,
          onProgress: (progress) {
            if (mounted) {
              setState(() {
                _uploadProgress = progress;
              });
            }
          },
        );

        if (mounted) {
          setState(() {
            _isUploading = false;
          });

          if (success) {
            String voiceMarker = "VOICE_NOTE:$fileName";
            String encryptedMarker = EncryptionService.encryptText(voiceMarker);
            await P2PSocketServer.sendMessageToHost(
              widget.targetHost,
              widget.targetPort,
              encryptedMarker,
            );

            final newMsg = {
              'id': DateTime.now().millisecondsSinceEpoch.toString(),
              'sender': 'me',
              'text': path,
              'type': 'voice',
              'status': 'read',
              'time': "${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}",
            };

            await ChatStorageService.saveMessage(widget.targetDeviceId, newMsg);

            setState(() {
              _messages.add(newMsg);
            });
            _scrollToBottom();
          }
        }
      }
    } catch (e) {
      print("خطأ إيقاف التسجيل: $e");
    }
  }

  // ❌ إلغاء التسجيل دون إرسال
  Future<void> _cancelRecording() async {
    _recordTimer?.cancel();
    await _audioRecorder.stop();
    setState(() {
      _isRecording = false;
      _recordDuration = 0;
    });
  }

  // 🔊 تشغيل/إيقاف التسجيل الصوتي
  Future<void> _toggleAudioPlay(String path) async {
    if (_isPlayingAudio && _currentlyPlayingPath == path) {
      await _audioPlayer.stop();
      setState(() {
        _isPlayingAudio = false;
        _currentlyPlayingPath = null;
      });
    } else {
      await _audioPlayer.stop();
      if (File(path).existsSync()) {
        await _audioPlayer.play(DeviceFileSource(path));
        setState(() {
          _isPlayingAudio = true;
          _currentlyPlayingPath = path;
        });
      }
    }
  }

  Future<void> _pickAndSendFile() async {
    if (_isBlocked) return;
    FilePickerResult? result = await FilePicker.platform.pickFiles();

    if (result != null && result.files.single.path != null) {
      File selectedFile = File(result.files.single.path!);
      String fileName = result.files.single.name;

      setState(() {
        _isUploading = true;
        _uploadProgress = 0.0;
      });

      bool success = await FileTransferService.sendFile(
        targetHost: widget.targetHost,
        targetPort: widget.targetPort,
        file: selectedFile,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _uploadProgress = progress;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _isUploading = false;
        });

        if (success) {
          final newMsg = {
            'id': DateTime.now().millisecondsSinceEpoch.toString(),
            'sender': 'me',
            'text': '📁 تم إرسال الملف: $fileName',
            'type': 'text',
            'status': 'read',
            'time': "${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}",
          };

          await ChatStorageService.saveMessage(widget.targetDeviceId, newMsg);

          setState(() {
            _messages.add(newMsg);
          });
          _scrollToBottom();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم إرسال الملف بنجاح!')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('فشل في إرسال الملف')),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    _messageSubscription?.cancel();
    P2PSocketServer.stopRingtone();
    _webrtcService.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_displayName),
            if (_displayExtension.isNotEmpty)
              Text(
                'الرقم اللاسلكي: $_displayExtension',
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
          ],
        ),
        actions: [
          // 🚫 زر حظر / إلغاء حظر الجهاز
          IconButton(
            icon: Icon(
              _isBlocked ? Icons.block_flipped : Icons.block,
              color: _isBlocked ? Colors.red : Colors.white70,
            ),
            tooltip: _isBlocked ? 'إلغاء حظر الجهاز' : 'حظر هذا الجهاز',
            onPressed: _toggleBlockDevice,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep, color: Colors.white70),
            tooltip: 'مسح سجل المحادثة',
            onPressed: () async {
              await ChatStorageService.clearChat(widget.targetDeviceId);
              setState(() {
                _messages.clear();
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.bookmark_add, color: Colors.orange),
            onPressed: _showSaveContactDialog,
          ),
          IconButton(
            icon: Icon(Icons.phone, color: _isBlocked ? Colors.grey : Colors.green),
            onPressed: _isBlocked ? null : () => _startCall(isVideo: false),
          ),
          IconButton(
            icon: Icon(Icons.videocam, color: _isBlocked ? Colors.grey : Colors.blue),
            onPressed: _isBlocked ? null : () => _startCall(isVideo: true),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(12),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final msg = _messages[index];
                    final isMe = msg['sender'] == 'me';
                    final isVoice = msg['type'] == 'voice';
                    final status = msg['status'] ?? 'sent';
                    final time = msg['time'] ?? '';

                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isMe ? Colors.blue.shade100 : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isVoice)
                              _buildVoiceBubble(msg['text'] ?? '', isMe)
                            else
                              Text(
                                msg['text'] ?? '',
                                style: const TextStyle(fontSize: 16, color: Colors.black87),
                              ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (time.isNotEmpty)
                                  Text(
                                    time,
                                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                                  ),
                                if (isMe) ...[
                                  const SizedBox(width: 4),
                                  Icon(
                                    status == 'read'
                                        ? Icons.done_all
                                        : (status == 'delivered' ? Icons.done_all : Icons.done),
                                    size: 14,
                                    color: status == 'read' ? Colors.blue : Colors.grey.shade600,
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              // 🚫 إظهار شريط تنبيه الحظر أو حقل المراسلة العادي
              if (_isBlocked)
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.red.shade50,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.block, color: Colors.red, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'تم حظر هذا الجهاز. قم بإلغاء الحظر لإرسال الرسائل والمكالمات.',
                        style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.white,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isUploading)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8.0, left: 8.0, right: 8.0),
                          child: Row(
                            children: [
                              Expanded(
                                child: LinearProgressIndicator(
                                  value: _uploadProgress,
                                  backgroundColor: Colors.grey.shade300,
                                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text("${(_uploadProgress * 100).toStringAsFixed(0)}%"),
                            ],
                          ),
                        ),
                      if (_isRecording)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.fiber_manual_record, color: Colors.red),
                              const SizedBox(width: 8),
                              Text(
                                "جاري التسجيل: ${_recordDuration}s",
                                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                              ),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.grey),
                                onPressed: _cancelRecording,
                              ),
                              IconButton(
                                icon: const Icon(Icons.send, color: Colors.green),
                                onPressed: _stopAndSendRecording,
                              ),
                            ],
                          ),
                        )
                      else
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.attach_file, color: Colors.blue),
                              tooltip: 'إرفاق ملف',
                              onPressed: _isUploading ? null : _pickAndSendFile,
                            ),
                            Expanded(
                              child: TextField(
                                controller: _msgController,
                                decoration: const InputDecoration(
                                  hintText: 'اكتب رسالتك هنا...',
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.mic, color: Colors.teal),
                              tooltip: 'تسجيل رسالة صوتية',
                              onPressed: _startRecording,
                            ),
                            IconButton(
                              icon: const Icon(Icons.send, color: Colors.blue),
                              onPressed: _sendMessage,
                            ),
                          ],
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

  // 🎙️ بناء فقاعة الرسالة الصوتية
  Widget _buildVoiceBubble(String path, bool isMe) {
    bool isCurrentPlaying = _isPlayingAudio && _currentlyPlayingPath == path;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(
            isCurrentPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
            size: 32,
            color: isMe ? Colors.blue.shade800 : Colors.indigo,
          ),
          onPressed: () => _toggleAudioPlay(path),
        ),
        const SizedBox(width: 8),
        Text(
          isCurrentPlaying ? "جاري التشغيل..." : "رسالة صوتية 🎙️",
          style: TextStyle(
            color: isMe ? Colors.blue.shade900 : Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
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
