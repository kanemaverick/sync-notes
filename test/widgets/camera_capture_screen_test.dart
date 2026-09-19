import 'dart:async';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_notes/screens/camera_capture_screen.dart';

class FakeStillCamera extends CameraPlatform {
  bool? audioEnabled;
  ResolutionPreset? resolution;
  int captures = 0;
  final errors = StreamController<CameraErrorEvent>.broadcast();
  @override
  Future<List<CameraDescription>> availableCameras() async => const [
    CameraDescription(
      name: 'back',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 90,
    ),
  ];
  @override
  Future<int> createCamera(
    CameraDescription cameraDescription,
    ResolutionPreset? resolutionPreset, {
    bool enableAudio = false,
  }) async {
    audioEnabled = enableAudio;
    resolution = resolutionPreset;
    return 1;
  }

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {}
  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream.value(
        const CameraInitializedEvent(
          1,
          640,
          480,
          ExposureMode.auto,
          true,
          FocusMode.auto,
          true,
        ),
      );
  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) => errors.stream;
  @override
  Stream<CameraResolutionChangedEvent> onCameraResolutionChanged(
    int cameraId,
  ) => const Stream.empty();
  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();
  @override
  Future<void> setFlashMode(int cameraId, FlashMode mode) async {}
  @override
  Future<double> getMinZoomLevel(int cameraId) async => 1;
  @override
  Future<double> getMaxZoomLevel(int cameraId) async => 5;
  @override
  Future<void> setZoomLevel(int cameraId, double zoom) async {}
  @override
  Widget buildPreview(int cameraId) => const ColoredBox(color: Colors.grey);
  @override
  Future<XFile> takePicture(int cameraId) async =>
      XFile('/tmp/test-shot-${++captures}.jpg');
  @override
  Future<void> dispose(int cameraId) async {
    errors.add(CameraErrorEvent(cameraId, 'disposed'));
    await errors.close();
  }
}

void main() {
  testWidgets('连续拍两张不退出相机、不打开麦克风，分别保留快门时间', (tester) async {
    final previous = CameraPlatform.instance;
    final camera = FakeStillCamera();
    CameraPlatform.instance = camera;
    addTearDown(() => CameraPlatform.instance = previous);
    final saved = <CameraCaptureResult>[];
    var offset = 1000;
    await tester.pumpWidget(
      MaterialApp(
        home: CameraCaptureScreen(
          offsetProvider: () async => offset,
          onCapture: (result) async => saved.add(result),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(camera.audioEnabled, isFalse);
    expect(camera.resolution, ResolutionPreset.max);
    await tester.tap(find.byIcon(Icons.camera_alt));
    await tester.pumpAndSettle();
    offset = 2500;
    await tester.tap(find.byIcon(Icons.camera_alt));
    await tester.pumpAndSettle();
    expect(saved.map((e) => e.offsetMs), [1000, 2500]);
    expect(find.textContaining('已保存 2 张'), findsOneWidget);
    expect(find.byType(CameraCaptureScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
