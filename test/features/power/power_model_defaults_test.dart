import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/power/models/power_model_defaults.dart';

void main() {
  test('exact identity retains display references but no unresolved PPAB', () {
    final values = powerReferenceLimitsFor(
      productName: '82Y4',
      biosVersion: 'M1CN48WW',
    );

    expect(values['cpu_longterm'], 54);
    expect(values['gpu_ppab'], isNull);
  });

  test('unknown and near-match identities do not inherit reference values', () {
    for (final (product, bios) in <(String?, String?)>[
      (null, 'M1CN48WW'),
      ('82Y4', null),
      ('83F5', 'M1CN48WW'),
      ('82Y4', 'M1CN49WW'),
      ('82Y4', 'M1CN48WW-extra'),
      ('82y4', 'M1CN48WW'),
    ]) {
      expect(
        powerReferenceLimitsFor(productName: product, biosVersion: bios),
        isEmpty,
        reason: '$product / $bios has no recorded reference values',
      );
    }
  });
}
