import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/webrtc_signaling_service.dart';

class CallScreen extends StatefulWidget {
  final WebRTCSignalingService signalingService;
  final String targetHost;
  final int targetPort;
  final String callerName;
  final bool isVideo;

  const CallScreen({
    Key? key,
    required this.signalingService,
    required this.targetHost,
    required this.targetPort,
    required this.callerName,
    required this.isVideo,
  }) : super(key: key);

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  bool _isMuted = false;
  bool _isSpeakerOn = true;

  @override
  void initState() {
    super.initState();
    _initRenderersAndStart();
  }

  Future<void> _initRenderersAndStart() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    await widget.signalingService.initialize(
      onLocalStream: (stream) {
        if (mounted) {
          setState(() {
            _localRenderer.srcObject = stream;
          });
        }
      },
      onRemoteStream: (stream) {
        if (mounted) {
          setState(() {
            _remoteRenderer.srcObject = stream;
          });
        }
      },
    );

    // بدء طلب الاتصال
    await widget.signalingService.createAndSendOffer(
      widget.targetHost,
      widget.targetPort,
    );
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
    });

    final localStream = _localRenderer.srcObject;
    if (localStream != null) {
      for (var track in localStream.getAudioTracks()) {
        track.enabled = !_isMuted;
      }
    }
  }

  void _toggleSpeaker() {
    setState(() {
      _isSpeakerOn = !_isSpeakerOn;
    });

    final remoteStream = _remoteRenderer.srcObject;
    if (remoteStream != null) {
      for (var track in remoteStream.getAudioTracks()) {
        track.enableSpeakerphone(_isSpeakerOn);
      }
    }
  }

  Future<void> _endCall() async {
    try {
      await widget.signalingService.dispose();
    } catch (_) {}

    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.callerName),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // عرض فيديو الطرف الآخر أو واجهة المكالمة الصوتية
          Positioned.fill(
            child: widget.isVideo
                ? (_remoteRenderer.srcObject != null
                    ? RTCVideoView(_remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                    : const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ))
                : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircleAvatar(
                          radius: 55,
                          backgroundColor: Colors.blueAccent,
                          child: Icon(Icons.person, size: 60, color: Colors.white),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          widget.callerName,
                          style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'مكالمة صوتية جارية...',
                          style: TextStyle(color: Colors.white70, fontSize: 16),
                        ),
                      ],
                    ),
                  ),
          ),

          // عرض فيديو الكاميرا المحلية عند اختيار فيديو
          if (widget.isVideo)
            Positioned(
              right: 16,
              top: 16,
              width: 100,
              height: 150,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  border: Border.all(color: Colors.white24, width: 2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: RTCVideoView(_localRenderer, mirror: true),
              ),
            ),

          // أزرار التحكم في أسفل الشاشة
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                FloatingActionButton(
                  heroTag: 'btn_mute',
                  backgroundColor: _isMuted ? Colors.orange : Colors.white24,
                  onPressed: _toggleMute,
                  child: Icon(_isMuted ? Icons.mic_off : Icons.mic, color: Colors.white),
                ),
                FloatingActionButton(
                  heroTag: 'btn_speaker',
                  backgroundColor: _isSpeakerOn ? Colors.blue : Colors.white24,
                  onPressed: _toggleSpeaker,
                  child: Icon(_isSpeakerOn ? Icons.volume_up : Icons.volume_off, color: Colors.white),
                ),
                FloatingActionButton(
                  heroTag: 'btn_hangup',
                  backgroundColor: Colors.red,
                  onPressed: _endCall,
                  child: const Icon(Icons.call_end, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
