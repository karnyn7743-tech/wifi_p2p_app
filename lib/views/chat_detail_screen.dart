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
  
  StreamSubscription<String>? _messageSubscription;

  String _displayName = '';
  String _displayExtension = '';
  bool _inCall = false;
  bool _isVideoCall = false;

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

    _messageSubscription = P2PSocketServer.messageStream.listen((data) {
      _handleIncomingData(data);
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
    if (!mounted) return;

    try {
      final decoded = jsonDecode(rawData);

      if (decoded is Map<String, dynamic> && decoded.containsKey('type')) {
        String type = decoded['type'];

        if (type == 'offer' || type == 'call_offer') {
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

      P2PSocketServer.playRingtone(loop: false);

      if (mounted) {
        setState(() {
          _messages.add({
            'sender': _displayName,
            'text': decryptedText,
            'type': decryptedText.startsWith('VOICE_NOTE:') ? 'voice' : 'text',
          });
        });
      }
    }
  }

  /// تنظيف آمن وشامل لجلسة الاتصال السابقة لإتاحة إعادة الاتصال بسهولة
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
    final text = _msgController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add({'sender': 'me', 'text': text, 'type': 'text'});
    });

    _msgController.clear();

    String encryptedText = EncryptionService.encryptText(text);

    await P2PSocketServer.sendMessageToHost(
      widget.targetHost,
      widget.targetPort,
      encryptedText,
    );
  }

  // 🎙️ بدء تسجيل الصوت
  Future<void> _startRecording() async {
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
            // إشعار المستلم بأن الملف المستلم هو رسالة صوتية
            String voiceMarker = "VOICE_NOTE:$fileName";
            String encryptedMarker = EncryptionService.encryptText(voiceMarker);
            await P2PSocketServer.sendMessageToHost(
              widget.targetHost,
              widget.targetPort,
              encryptedMarker,
            );

            setState(() {
              _messages.add({
                'sender': 'me',
                'text': path,
                'type': 'voice',
              });
            });
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
          setState(() {
            _messages.add({
              'sender': 'me',
              'text': '📁 تم إرسال الملف: $fileName',
              'type': 'text',
            });
          });
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
                    final isVoice = msg['type'] == 'voice';

                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isMe ? Colors.blue.shade100 : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: isVoice
                            ? _buildVoiceBubble(msg['text'] ?? '', isMe)
                            : Text(
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
                    // 🎙️ واجهة التسجيل عند التفعيل أو حقل الإدخال العادي
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
                          // زر الميكروفون للرسائل الصوتية
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
