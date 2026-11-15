import 'package:flutter_test/flutter_test.dart';

import '../../tool/package_deb.dart';

void main() {
  test('maps app versions to Debian release and prerelease ordering', () {
    expect(debianVersion('1.0.0+1'), '1.0.0+1-1');
    expect(debianVersion('1.1.0-rc.1+2'), '1.1.0~rc.1+2-1');
    expect(debianVersion('2.0.0'), '2.0.0-1');
    for (final version in [
      'v1.0.0',
      '1.0',
      '../1.0.0',
      '1.0.0+1/2',
      '1.0.0;id',
    ]) {
      expect(() => debianVersion(version), throwsFormatException);
    }
  });
}
