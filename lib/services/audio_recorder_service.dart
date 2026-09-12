import 'dart:io';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

class AudioRecorderService {
  final AudioRecorder _audioRecorder = AudioRecorder();
  String? _currentRecordingPath;

  /// بدء تسجيل مقطع صوتی
  Future<void> startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final Directory tempDir = await getTemporaryDirectory();
        _currentRecordingPath = '${tempDir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';

        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc),
          path: _currentRecordingPath!,
        );
      }
    } catch (e) {
      print('خطأ في بدء تسجيل الصوت: $e');
    }
  }

  /// إيقاف التسجيل وإرجاع المسار
  Future<String?> stopRecording() async {
    try {
      final path = await _audioRecorder.stop();
      return path;
    } catch (e) {
      print('خطأ في إيقاف تسجيل الصوت: $e');
      return null;
    }
  }

  Future<bool> isRecording() async {
    return await _audioRecorder.isRecording();
  }
}
