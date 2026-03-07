import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/settings/bloc/settings_state.dart';
import 'package:legion_frontend/features/settings/models/service_control.dart';

ServiceControl _service() => const ServiceControl(
  id: 'tlp',
  label: 'TLP',
  units: ['tlp.service'],
  supported: true,
  active: true,
  enabled: true,
);

void main() {
  group('SettingsState.initial', () {
    test('services is empty', () {
      expect(SettingsState.initial().services, isEmpty);
    });

    test('hasLoaded is false', () {
      expect(SettingsState.initial().hasLoaded, isFalse);
    });

    test('errorMessage and noticeMessage are null', () {
      final s = SettingsState.initial();
      expect(s.errorMessage, isNull);
      expect(s.noticeMessage, isNull);
    });
  });

  group('SettingsState.hasLoaded', () {
    test('true when services list is non-empty', () {
      final s = SettingsState.initial().copyWith(services: [_service()]);
      expect(s.hasLoaded, isTrue);
    });
  });

  group('SettingsState.copyWith sentinel', () {
    test('copyWith with no args returns equal state', () {
      expect(SettingsState.initial().copyWith(), equals(SettingsState.initial()));
    });

    test('copyWith(errorMessage: null) clears it', () {
      final s = SettingsState.initial().copyWith(errorMessage: 'err').copyWith(
        errorMessage: null,
      );
      expect(s.errorMessage, isNull);
    });

    test('copyWith omitting errorMessage preserves it', () {
      final s = SettingsState.initial()
          .copyWith(errorMessage: 'msg')
          .copyWith(isLoading: true);
      expect(s.errorMessage, equals('msg'));
    });

    test('copyWith(noticeMessage: null) clears it', () {
      final s = SettingsState.initial().copyWith(noticeMessage: 'done').copyWith(
        noticeMessage: null,
      );
      expect(s.noticeMessage, isNull);
    });
  });

  group('SettingsState props', () {
    test('identical states are equal', () {
      expect(SettingsState.initial(), equals(SettingsState.initial()));
    });

    test('differ when isApplying differs', () {
      final a = SettingsState.initial();
      final b = a.copyWith(isApplying: true);
      expect(a, isNot(equals(b)));
    });
  });
}
