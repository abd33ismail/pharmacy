import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

class BarcodeImageScreen extends StatefulWidget {
  const BarcodeImageScreen({super.key});

  @override
  State<BarcodeImageScreen> createState() => _BarcodeImageScreenState();
}

class _BarcodeImageScreenState extends State<BarcodeImageScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isFlashOn = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    _cameras = await availableCameras();
    if (_cameras != null && _cameras!.isNotEmpty) {
      _controller = CameraController(_cameras![0], ResolutionPreset.medium);
      await _controller!.initialize();
      if (!mounted) return;
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _toggleFlash() {
    if (_controller != null) {
      _isFlashOn = !_isFlashOn;
      _controller!.setFlashMode(_isFlashOn ? FlashMode.torch : FlashMode.off);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('scan_product'.tr()),
        actions: [
          IconButton(
            icon: Icon(_isFlashOn ? Icons.flash_on : Icons.flash_off),
            onPressed: _toggleFlash,
          ),
        ],
      ),
      body: Stack(
        children: [
          CameraPreview(_controller!),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 32.0),
              child: FloatingActionButton.large(
                onPressed: () {
                  // Implement scan/capture logic
                },
                child: const Icon(Icons.qr_code_scanner, size: 40),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
