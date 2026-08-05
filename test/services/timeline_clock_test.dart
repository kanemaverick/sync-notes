import 'package:flutter_test/flutter_test.dart';
import 'package:sync_notes/core/timeline_clock.dart';

class FakeMonotonicClock implements MonotonicClock {
  int value = 1000;
  void advance(int milliseconds) => value += milliseconds;
  @override
  Future<int> nowMs() async => value;
}

void main() {
  test('offsetMs使用单调时钟计算', () async {
    final source = FakeMonotonicClock();
    final clock = TimelineClock(source);
    await clock.start();
    source.advance(1234);
    expect(await clock.offsetMs(), 1234);
  });

  test('暂停区间不会进入可播放时间轴', () async {
    final source = FakeMonotonicClock();
    final clock = TimelineClock(source);
    await clock.start();
    source.advance(5000);
    expect(await clock.pause(), 5000);
    source.advance(9000);
    expect(await clock.offsetMs(), 5000);
    await clock.resume();
    source.advance(3000);
    expect(await clock.offsetMs(), 8000);
  });

  test('恢复时可从已保存的offset继续', () async {
    final source = FakeMonotonicClock();
    final clock = TimelineClock(source);
    await clock.start(initialOffsetMs: 42000);
    source.advance(1500);
    expect(await clock.offsetMs(), 43500);
  });
}
