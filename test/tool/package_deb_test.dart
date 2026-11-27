@Tags(['tooling'])
library;

import 'package:flutter_test/flutter_test.dart';

import '../../tool/packaging/packaging_versions.dart';

void main() {
  test('maps app versions to Debian release and prerelease ordering', () {
    expect(debianVersion('1.0.0+1'), '1.0.0+1-1');
    expect(debianVersion('1.1.0-rc.1+2'), '1.1.0~rc.1+2-1');
    expect(debianVersion('0.1.0-alpha.2+1'), '0.1.0~alpha.2+1-1');
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

  test('download names preserve prerelease labels without upload renaming', () {
    expect(
      debianFileName('0.1.0-alpha.2+1'),
      'legion-linux-frontend_0.1.0-alpha.2+1-1_amd64.deb',
    );
    expect(
      debianFileName('1.0.0+1'),
      'legion-linux-frontend_1.0.0+1-1_amd64.deb',
    );
  });
}
