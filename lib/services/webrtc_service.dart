import 'dart:async';
import 'dart:convert';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'p2p_socket_server.dart';

class WebRTCService {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  bool _isRenderersInitialized = false;

  Future<void> initializeRenderers() async {
    if (!_isRenderersInitialized) {
      await localRenderer.initialize();
      await remoteRenderer.initialize();
      _isRenderersInitialized = true;
    }
  }

  Future<void> createPeerConnectionConfig(String targetHost, int targetPort) async {
    await _closePeerConnection();

    Map<String, dynamic> configuration = {
      'iceServers': [],
      'sdpSemantics': 'unified-plan'
    };

    _peerConnection = await createPeerConnection(configuration);

    // ربط مسار الفيديو الوارد بالرندر الخاص بالطرف البعيد فور استقباله
    _peerConnection?.onTrack = (RTCTrackEvent event) {
      if (event.track.kind == 'video' && event.streams.isNotEmpty) {
        remoteRenderer.srcObject = event.streams[0];
      }
    };

    _peerConnection?.onIceCandidate = (candidate) {
      if (candidate != null && candidate.candidate != null) {
        final msg = jsonEncode({
          'type': 'candidate',
          'candidate': candidate.toMap(),
        });
        P2PSocketServer.sendMessageToHost(targetHost, targetPort, msg);
      }
    };
  }

  Future<void> makeCall(String targetHost, int targetPort, bool isVideo) async {
    await initializeRenderers();
    await createPeerConnectionConfig(targetHost, targetPort);

    // ⚡ خيارات الوسائط المحسنة لإلغاء الصدى وتصفية الضوضاء
    Map<String, dynamic> mediaConstraints = {
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
        'sampleRate': 44100,
        'sampleSize': 16,
        'channelCount': 1,
      },
      'video': isVideo ? {'facingMode': 'user', 'width': 640, 'height': 480} : false,
    };

    _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    localRenderer.srcObject = _localStream;

    _localStream?.getTracks().forEach((track) {
      if (_peerConnection != null && _localStream != null) {
        _peerConnection?.addTrack(track, _localStream!);
      }
    });

    RTCSessionDescription offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);

    final msg = jsonEncode({
      'type': 'offer',
      'sdp': offer.sdp,
      'isVideo': isVideo,
    });

    await P2PSocketServer.sendMessageToHost(targetHost, targetPort, msg);
  }

  Future<void> handleOfferAndAnswer(
      String sdp, String targetHost, int targetPort, bool isVideo) async {
    await initializeRenderers();
    await createPeerConnectionConfig(targetHost, targetPort);

    // ⚡ خيارات الوسائط المحسنة لإلغاء الصدى وتصفية الضوضاء
    Map<String, dynamic> mediaConstraints = {
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
        'sampleRate': 44100,
        'sampleSize': 16,
        'channelCount': 1,
      },
      'video': isVideo ? {'facingMode': 'user', 'width': 640, 'height': 480} : false,
    };

    _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    localRenderer.srcObject = _localStream;

    _localStream?.getTracks().forEach((track) {
      if (_peerConnection != null && _localStream != null) {
        _peerConnection?.addTrack(track, _localStream!);
      }
    });

    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(sdp, 'offer'),
    );

    RTCSessionDescription answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    final msg = jsonEncode({
      'type': 'answer',
      'sdp': answer.sdp,
    });

    await P2PSocketServer.sendMessageToHost(targetHost, targetPort, msg);
  }

  Future<void> handleAnswer(String sdp) async {
    if (_peerConnection != null) {
      await _peerConnection?.setRemoteDescription(
        RTCSessionDescription(sdp, 'answer'),
      );
    }
  }

  Future<void> handleCandidate(Map<String, dynamic> candidateMap) async {
    if (_peerConnection != null && candidateMap['candidate'] != null) {
      RTCIceCandidate candidate = RTCIceCandidate(
        candidateMap['candidate'],
        candidateMap['sdpMid'],
        candidateMap['sdpMLineIndex'],
      );
      await _peerConnection?.addCandidate(candidate);
    }
  }

  Future<void> hangup(String targetHost, int targetPort) async {
    try {
      final msg = jsonEncode({'type': 'hangup'});
      await P2PSocketServer.sendMessageToHost(targetHost, targetPort, msg);
    } catch (_) {}
    await dispose();
  }

  Future<void> _closePeerConnection() async {
    try {
      _localStream?.getTracks().forEach((track) => track.stop());
      await _localStream?.dispose();
      _localStream = null;

      localRenderer.srcObject = null;
      remoteRenderer.srcObject = null;

      await _peerConnection?.close();
      _peerConnection = null;
    } catch (e) {
      print("خطأ أثناء إغلاق PeerConnection: $e");
    }
  }

  Future<void> dispose() async {
    await _closePeerConnection();
    if (_isRenderersInitialized) {
      await localRenderer.dispose();
      await remoteRenderer.dispose();
      _isRenderersInitialized = false;
    }
  }
}
