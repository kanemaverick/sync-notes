import 'package:flutter_test/flutter_test.dart';
import 'package:sync_notes/core/timeline_clock.dart';

void main() {
  final mapper = SegmentTimelineMapper([300000, 300000, 120000]);

  test('多音频分片表现为连续总时长', () {
    expect(mapper.totalDurationMs, 720000);
    expect(mapper.mapLocalPosition(index: 2, positionMs: 10000), 610000);
  });

  test('点击时间节点后映射到正确分片seek位置', () {
    final target = mapper.mapGlobalPosition(305500);
    expect(target.index, 1);
    expect(target.positionMs, 5500);
  });

  test('边界位置落到下一分片开头', () {
    final target = mapper.mapGlobalPosition(600000);
    expect(target.index, 2);
    expect(target.positionMs, 0);
  });
}
