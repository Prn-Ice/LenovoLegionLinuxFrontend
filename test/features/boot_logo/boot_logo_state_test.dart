import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/boot_logo/bloc/boot_logo_state.dart';
import 'package:legion_frontend/features/boot_logo/models/boot_logo_status.dart';

const _status1920 = BootLogoStatus(
  isCustomEnabled: false,
  requiredWidth: 1920,
  requiredHeight: 1080,
);

void main() {
  group('BootLogoState.initial', () {
    test('status is null', () {
      expect(BootLogoState.initial().status, isNull);
    });

    test('selectedImagePath is null', () {
      expect(BootLogoState.initial().selectedImagePath, isNull);
    });

    test('validationError is null', () {
      expect(BootLogoState.initial().validationError, isNull);
    });

    test('isLoading and isApplying are false', () {
      final s = BootLogoState.initial();
      expect(s.isLoading, isFalse);
      expect(s.isApplying, isFalse);
    });

    test('canApply is false when no image selected', () {
      expect(BootLogoState.initial().canApply, isFalse);
    });
  });

  group('BootLogoState.canApply', () {
    test('true when image selected, no validation error, not applying', () {
      final s = BootLogoState.initial().copyWith(
        selectedImagePath: '/tmp/logo.png',
        validationError: null,
        isApplying: false,
      );
      expect(s.canApply, isTrue);
    });

    test('false when validationError is set', () {
      final s = BootLogoState.initial().copyWith(
        selectedImagePath: '/tmp/logo.txt',
        validationError: 'Unsupported format',
      );
      expect(s.canApply, isFalse);
    });

    test('false when isApplying is true', () {
      final s = BootLogoState.initial().copyWith(
        selectedImagePath: '/tmp/logo.png',
        isApplying: true,
      );
      expect(s.canApply, isFalse);
    });
  });

  group('BootLogoState.copyWith sentinel', () {
    test('copyWith with no args returns equal state', () {
      expect(BootLogoState.initial().copyWith(), equals(BootLogoState.initial()));
    });

    test('copyWith(status: null) clears it', () {
      final s = BootLogoState.initial().copyWith(status: _status1920).copyWith(
        status: null,
      );
      expect(s.status, isNull);
    });

    test('copyWith omitting status preserves it', () {
      final s = BootLogoState.initial()
          .copyWith(status: _status1920)
          .copyWith(isLoading: true);
      expect(s.status, equals(_status1920));
    });

    test('copyWith(errorMessage: null) clears it', () {
      final s = BootLogoState.initial().copyWith(errorMessage: 'oops').copyWith(
        errorMessage: null,
      );
      expect(s.errorMessage, isNull);
    });

    test('copyWith(selectedImagePath: null) clears it', () {
      final s = BootLogoState.initial()
          .copyWith(selectedImagePath: '/tmp/x.png')
          .copyWith(selectedImagePath: null);
      expect(s.selectedImagePath, isNull);
    });
  });

  group('BootLogoState props', () {
    test('identical initial states are equal', () {
      expect(BootLogoState.initial(), equals(BootLogoState.initial()));
    });

    test('differ when status differs', () {
      final a = BootLogoState.initial();
      final b = a.copyWith(status: _status1920);
      expect(a, isNot(equals(b)));
    });

    test('differ when selectedImagePath differs', () {
      final a = BootLogoState.initial().copyWith(selectedImagePath: '/a.png');
      final b = BootLogoState.initial().copyWith(selectedImagePath: '/b.png');
      expect(a, isNot(equals(b)));
    });
  });
}
