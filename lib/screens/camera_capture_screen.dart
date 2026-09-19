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
  const CameraCaptureScreen({
    required this.offsetProvider,
    this.onCapture,
    super.key,
  });
  final Future<int> Function() offsetProvider;
  final Future<void> Function(CameraCaptureResult)? onCapture;

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
  int _savedCount = 0;
  double _zoom = 1;
  double _minZoom = 1;
  double _maxZoom = 1;
  double _gestureZoom = 1;
  int _cameraGeneration = 0;

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
    final generation = ++_cameraGeneration;
    final previous = _controller;
    _controller = null;
    await previous?.dispose();
    try {
      final controller = CameraController(
        camera,
        ResolutionPreset.max,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      if (!mounted || generation != _cameraGeneration) {
        await controller.dispose();
        return;
      }
      _minZoom = await controller.getMinZoomLevel();
      _maxZoom = (await controller.getMaxZoomLevel()).clamp(_minZoom, 8.0);
      _zoom = 1.0.clamp(_minZoom, _maxZoom);
      await controller.setZoomLevel(_zoom);
      try {
        await controller.setFlashMode(_flashMode);
      } catch (_) {
        _flashMode = FlashMode.off;
      }
      if (!mounted || generation != _cameraGeneration) {
        return controller.dispose();
      }
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

  Future<void> _setZoom(double value) async {
    final controller = _controller;
    if (controller == null || _capturing) return;
    final zoom = value.clamp(_minZoom, _maxZoom);
    try {
      await controller.setZoomLevel(zoom);
      if (mounted) setState(() => _zoom = zoom);
    } catch (_) {
      // Optical/digital zoom support varies by camera; capture still works.
    }
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
      _cameraGeneration++;
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
      final result = CameraCaptureResult(
        temporaryPath: file.path,
        offsetMs: offset,
        capturedAt: capturedAt,
      );
      if (widget.onCapture != null) {
        // Persist before showing success. Leaving the camera never discards a shot.
        await widget.onCapture!(result);
        if (mounted) {
          setState(() {
            _savedCount++;
            _capturing = false;
          });
        }
        return;
      }
      if (mounted) {
        Navigator.pop(context, result);
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
    _cameraGeneration++;
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return PopScope(
      canPop: !_capturing,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: const Text('现场拍照'),
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
                      onScaleStart: (_) => _gestureZoom = _zoom,
                      onScaleUpdate: (details) {
                        if (details.pointerCount >= 2) {
                          _setZoom(_gestureZoom * details.scale);
                        }
                      },
                      child: Center(child: CameraPreview(controller)),
                    ),
                  ),
                  Positioned(
                    left: 24,
                    right: 24,
                    bottom: 145,
                    child: Column(
                      children: [
                        Text(
                          '已保存 $_savedCount 张 · ${_zoom.toStringAsFixed(1)}×',
                          style: const TextStyle(
                            color: Colors.white,
                            backgroundColor: Colors.black54,
                          ),
                        ),
                        if (_maxZoom > _minZoom)
                          Slider(
                            value: _zoom,
                            min: _minZoom,
                            max: _maxZoom,
                            label: '${_zoom.toStringAsFixed(1)}×',
                            onChanged: _capturing ? null : _setZoom,
                          ),
                        const Text(
                          '点按对焦 · 双指缩放 · 可连续拍摄',
                          style: TextStyle(
                            color: Colors.white,
                            backgroundColor: Colors.black54,
                          ),
                        ),
                      ],
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
      ),
    );
  }
}
