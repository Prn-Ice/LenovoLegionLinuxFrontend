@Tags(['tooling'])
library;

import 'package:flutter_test/flutter_test.dart';

import '../../tool/ci/check_commits.dart';

void main() {
  test('accepts conventional subjects with scopes and breaking markers', () {
    for (final subject in [
      'fix: save the curve',
      'feat(fans)!: replace presets',
      'chore!: require the new compiler',
      'revert: restore the previous preset',
    ]) {
      expect(conventionalSubject.hasMatch(subject), isTrue, reason: subject);
    }
  });

  test('rejects malformed commit subjects', () {
    for (final subject in [
      'update: save the curve',
      'Fix: save the curve',
      'fix(): save the curve',
      'fix:no space',
      'fix: ',
      'fix:  ',
      'fix: description\nsecond line',
    ]) {
      expect(conventionalSubject.hasMatch(subject), isFalse, reason: subject);
    }
  });
}
