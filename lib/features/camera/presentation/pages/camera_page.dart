import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import 'package:flutter_food_recog/core/providers/camera_provider.dart';
import 'package:flutter_food_recog/core/routes/app_router.dart';
import 'package:flutter_food_recog/core/utils/snackbar_utils.dart';

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  late final CameraProvider _cameraProvider;

  String _detectedFoodLabel = "";

  @override
  void initState() {
    super.initState();
    _cameraProvider = context.read<CameraProvider>();
  }

  @override
  void dispose() {
    if (_cameraProvider.controller != null &&
        _cameraProvider.controller!.value.isStreamingImages) {
      _cameraProvider.controller!.stopImageStream();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cameraProvider = context.watch<CameraProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Take Photo'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (cameraProvider.isInitialized &&
              cameraProvider.controller!.value.isInitialized)
            CameraPreview(cameraProvider.controller!)
          else
            const Center(child: CircularProgressIndicator()),
          if (_detectedFoodLabel.isNotEmpty)
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.greenAccent, width: 2),
                ),
                child: Text(
                  _detectedFoodLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          if (cameraProvider.isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: cameraProvider.isProcessing
            ? null
            : () => _captureAndProcess(context),
        child: const Icon(Icons.camera),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  // ** FUNGSI DIPERBAIKI UNTUK MENGEMBALIKAN CROP **
  Future<void> _captureAndProcess(BuildContext context) async {
    final cameraProvider = context.read<CameraProvider>();

    if (!cameraProvider.isInitialized || cameraProvider.isProcessing) return;

    try {
      // 1. Ambil gambar dari kamera
      final imagePath = await cameraProvider.captureImage();
      if (imagePath == null || !context.mounted) return;

      // 2. Lakukan proses crop pada gambar yang diambil
      final croppedPath = await cameraProvider.cropImage(imagePath);
      if (croppedPath == null || !context.mounted) return;

      // 3. Navigasi ke halaman hasil dengan gambar yang sudah di-crop
      Navigator.pushReplacementNamed(
        context,
        AppRouter.result,
        arguments: croppedPath,
      );
    } catch (e) {
      if (!context.mounted) return;
      SnackbarUtils(
        text: 'Error processing image: $e',
        backgroundColor: Colors.red,
      ).showErrorSnackBar(context);
    }
  }
}
