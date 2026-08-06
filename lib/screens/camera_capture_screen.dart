import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class CameraCaptureResult {
  const CameraCaptureResult({
    required this.temporaryPath,
    required this.offsetMs,
    required this.capturedAt,
  });
  final String temporaryPath;
  final int offsetMs;
  final DateTime capturedAt;
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
  List<CameraDescription> _cameras = [];
  int _cameraIndex = 0;
  FlashMode _flashMode = FlashMode.off;
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
      _cameras = await availableCameras();
      if (_cameras.isEmpty) throw StateError('设备没有可用相机');
      await _initializeCamera(_cameras[_cameraIndex]);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _initializeCamera(CameraDescription camera) async {
    final previous = _controller;
    _controller = null;
    await previous?.dispose();
    try {
      final controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      try {
        await controller.setFlashMode(_flashMode);
      } catch (_) {
        _flashMode = FlashMode.off;
      }
      if (!mounted) return controller.dispose();
      setState(() {
        _controller = controller;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _toggleFlash() async {
    final controller = _controller;
    if (controller == null) return;
    final next = _flashMode == FlashMode.off ? FlashMode.auto : FlashMode.off;
    try {
      await controller.setFlashMode(next);
      if (mounted) setState(() => _flashMode = next);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('无法切换闪光灯：$error')));
      }
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _capturing) return;
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    await _initializeCamera(_cameras[_cameraIndex]);
  }

  Future<void> _focus(
    TapDownDetails details,
    BoxConstraints constraints,
  ) async {
    final controller = _controller;
    if (controller == null) return;
    final point = Offset(
      (details.localPosition.dx / constraints.maxWidth).clamp(0, 1),
      (details.localPosition.dy / constraints.maxHeight).clamp(0, 1),
    );
    try {
      await controller.setFocusPoint(point);
      await controller.setExposurePoint(point);
    } catch (_) {
      // Some devices do not expose manual focus; capture remains available.
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
      final capturedAt = DateTime.now();
      final file = await controller.takePicture();
      if (mounted) {
        Navigator.pop(
          context,
          CameraCaptureResult(
            temporaryPath: file.path,
            offsetMs: offset,
            capturedAt: capturedAt,
          ),
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
                LayoutBuilder(
                  builder: (context, constraints) => GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (details) => _focus(details, constraints),
                    child: Center(child: CameraPreview(controller)),
                  ),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  top: 12,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton.filledTonal(
                        onPressed: _toggleFlash,
                        tooltip: _flashMode == FlashMode.off
                            ? '开启自动闪光'
                            : '关闭闪光灯',
                        icon: Icon(
                          _flashMode == FlashMode.off
                              ? Icons.flash_off_rounded
                              : Icons.flash_auto_rounded,
                        ),
                      ),
                      if (_cameras.length > 1)
                        IconButton.filledTonal(
                          onPressed: _switchCamera,
                          tooltip: '切换前后摄像头',
                          icon: const Icon(Icons.cameraswitch_rounded),
                        ),
                    ],
                  ),
                ),
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
