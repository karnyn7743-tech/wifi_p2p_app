import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'p2p_socket_server.dart';

class FileTransferService {
  static const int chunkSize = 64 * 1024; // تقسيم الملف لأجزاء بحجم 64 كيلوبايت

  /// 📤 1. إرسال ملف إلى جهاز محدد
  static Future<bool> sendFile({
    required String targetHost,
    required int targetPort,
    required File file,
    required Function(double progress) onProgress,
  }) async {
    Socket? socket;
    try {
      final fileName = file.path.split('/').last;
      final fileSize = await file.length();

      // فتح اتصال مباشر لنقل الملف
      socket = await Socket.connect(targetHost, targetPort, timeout: const Duration(seconds: 5));
      
      // إرسال الترويسة الأولى (اسم الملف وحجمه)
      String header = "FILE_HEADER|$fileName|$fileSize\n";
      socket.add(utf8.encode(header));
      await socket.flush();

      // قراءة وإرسال أجزاء الملف
      final RandomAccessFile raf = await file.open(mode: FileMode.read);
      int bytesSent = 0;

      while (bytesSent < fileSize) {
        final List<int> buffer = await raf.read(chunkSize);
        if (buffer.isEmpty) break;

        socket.add(buffer);
        await socket.flush();

        bytesSent += buffer.length;
        onProgress(bytesSent / fileSize); // تحديث نسبة التقدم
      }

      await raf.close();
      await socket.close();
      return true;
    } catch (e) {
      print("خطأ في إرسال الملف: $e");
      socket?.destroy();
      return false;
    }
  }

  /// 📥 2. استقبال وحفظ الملف الوارد
  static Future<File?> receiveFile(
    Socket clientSocket, {
    required String fileName,
    required int fileSize,
    required Function(double progress) onProgress,
  }) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final savePath = "${appDir.path}/$fileName";
      final File receivedFile = File(savePath);
      final IOSink sink = receivedFile.openWrite();

      int bytesReceived = 0;

      await for (var chunk in clientSocket) {
        sink.add(chunk);
        bytesReceived += chunk.length;
        onProgress(bytesReceived / fileSize);

        if (bytesReceived >= fileSize) break;
      }

      await sink.flush();
      await sink.close();
      return receivedFile;
    } catch (e) {
      print("خطأ في استقبال الملف: $e");
      return null;
    }
  }
}
