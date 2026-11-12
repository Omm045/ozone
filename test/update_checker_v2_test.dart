// v2.0.0 release: the update checker must offer v2.0.0 to 1.x installs and
// treat a 2.0.0+N build as up to date.
import 'package:flutter_test/flutter_test.dart';
import 'package:ozone/core/utils/update_checker.dart';

void main() {
  test('v2.0.0 is newer than v1.5.0 and v1.1.0', () {
    expect(UpdateChecker.isVersionNewer('v2.0.0', '1.5.0'), isTrue);
    expect(UpdateChecker.isVersionNewer('v2.0.0', '1.5.0+5'), isTrue);
    expect(UpdateChecker.isVersionNewer('v2.0.0', '1.1.0+3'), isTrue);
  });

  test('v2.0.0 equals a 2.0.0+N app version (no prompt)', () {
    expect(UpdateChecker.isVersionNewer('v2.0.0', '2.0.0+7'), isFalse);
    expect(UpdateChecker.isVersionNewer('v2.0.0', '2.0.0'), isFalse);
    expect(UpdateChecker.normalizeVersion('2.0.0+7'), UpdateChecker.normalizeVersion('v2.0.0'));
  });

  test('older tags never prompt a 2.0.0 install', () {
    expect(UpdateChecker.isVersionNewer('v1.5.0', '2.0.0+7'), isFalse);
  });
}
