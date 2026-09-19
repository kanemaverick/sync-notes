import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sync_notes/core/user_facing_error.dart';

void main() {
  test('平台异常不把native堆栈放进提示条', () {
    expect(
      userFacingError(
        PlatformException(
          code: 'scanner_unavailable',
          message: '扫描不可用',
          details: 'native stack secret details',
        ),
      ),
      '扫描不可用',
    );
    expect(userFacingError(PlatformException(code: 'busy')), 'busy');
  });
  test('普通错误仅显示首行且有长度上限', () {
    expect(userFacingError('错误\nstack frame'), '错误');
    expect(userFacingError('x' * 200).length, 121);
  });
}
