import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/dashboard/models/device_identity_snapshot.dart';

void main() {
  group('DeviceIdentitySnapshot', () {
    test('displayName returns family+name when both available', () {
      const s = DeviceIdentitySnapshot(
        productFamily: 'Legion Slim 7',
        productName: '16APH8',
        serial: 'PF3ABC12',
        biosVersion: 'LPCN41WW',
      );
      expect(s.displayName, 'Legion Slim 7 16APH8');
    });

    test('displayName returns family alone when no product name', () {
      const s = DeviceIdentitySnapshot(
        productFamily: 'Legion Slim 7',
        productName: null,
        serial: null,
        biosVersion: null,
      );
      expect(s.displayName, 'Legion Slim 7');
    });

    test('displayName returns Unknown when both null', () {
      const s = DeviceIdentitySnapshot(
        productFamily: null,
        productName: null,
        serial: null,
        biosVersion: null,
      );
      expect(s.displayName, 'Unknown Device');
    });

    test('equality', () {
      const a = DeviceIdentitySnapshot(
        productFamily: 'Legion',
        productName: 'Slim 7',
        serial: 'ABC',
        biosVersion: '1.0',
      );
      const b = DeviceIdentitySnapshot(
        productFamily: 'Legion',
        productName: 'Slim 7',
        serial: 'ABC',
        biosVersion: '1.0',
      );
      expect(a, equals(b));
    });
  });
}
