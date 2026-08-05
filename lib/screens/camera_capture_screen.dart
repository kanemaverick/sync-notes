import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class CameraCaptureResult {
  const CameraCaptureResult({
    required this.temporaryPath,
    required this.offsetMs,
  });
  final String temporaryPath;
  final int offsetMs;
}

class CameraCaptureScreen extends StatefulWidget {
  const CameraCaptureScreen({required this.offsetProvider, super.key});
  final Future<int> Function() offsetProvider;

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  Object? _error;
  bool _capturing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw StateError('设备没有可用相机');
      final controller = CameraController(
        cameras.first,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      if (!mounted) return controller.dispose();
      setState(() => _controller = controller);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed && _controller == null) {
      _initialize();
    }
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || _capturing) return;
    setState(() => _capturing = true);
    try {
      final offset = await widget.offsetProvider();
      final file = await controller.takePicture();
      if (mounted) {
        Navigator.pop(
          context,
          CameraCaptureResult(temporaryPath: file.path, offsetMs: offset),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('拍照失败：$error')));
        setState(() => _capturing = false);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('拍照 · 录音继续中'),
      ),
      body: _error != null
          ? Center(
              child: Text(
                '无法启动相机\n$_error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            )
          : controller == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              fit: StackFit.expand,
              children: [
                Center(child: CameraPreview(controller)),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 32,
                  child: Center(
                    child: Semantics(
                      button: true,
                      label: '拍照',
                      child: IconButton.filled(
                        onPressed: _capturing ? null : _capture,
                        iconSize: 48,
                        padding: const EdgeInsets.all(18),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                        ),
                        icon: _capturing
                            ? const CircularProgressIndicator()
                            : const Icon(Icons.camera_alt),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
