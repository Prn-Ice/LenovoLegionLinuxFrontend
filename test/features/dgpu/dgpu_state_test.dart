import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/dgpu/bloc/dgpu_state.dart';
import 'package:legion_frontend/features/dgpu/models/dgpu_process.dart';

const _proc = DgpuProcess(pid: 1234, name: 'Xorg', usedMemoryMib: 4);

void main() {
  group('DgpuState.initial', () {
    test('isActive is null', () {
      expect(DgpuState.initial().isActive, isNull);
    });

    test('processes is empty', () {
      expect(DgpuState.initial().processes, isEmpty);
    });

    test('isLoading and isApplying are false', () {
      final s = DgpuState.initial();
      expect(s.isLoading, isFalse);
      expect(s.isApplying, isFalse);
    });

    test('errorMessage and noticeMessage are null', () {
      final s = DgpuState.initial();
      expect(s.errorMessage, isNull);
      expect(s.noticeMessage, isNull);
    });
  });

  group('DgpuState.isAvailable', () {
    test('false when isActive is null', () {
      expect(DgpuState.initial().isAvailable, isFalse);
    });

    test('true when isActive is set (even false)', () {
      final s = DgpuState.initial().copyWith(isActive: false);
      expect(s.isAvailable, isTrue);
    });

    test('true when isActive is true', () {
      final s = DgpuState.initial().copyWith(isActive: true);
      expect(s.isAvailable, isTrue);
    });
  });

  group('DgpuState.copyWith sentinel', () {
    test('copyWith with no args returns equal state', () {
      expect(DgpuState.initial().copyWith(), equals(DgpuState.initial()));
    });

    test('copyWith(isActive: null) clears it', () {
      final s = DgpuState.initial()
          .copyWith(isActive: true)
          .copyWith(isActive: null);
      expect(s.isActive, isNull);
    });

    test('copyWith omitting isActive preserves it', () {
      final s = DgpuState.initial()
          .copyWith(isActive: true)
          .copyWith(isLoading: true);
      expect(s.isActive, isTrue);
    });

    test('copyWith(errorMessage: null) clears it', () {
      final s = DgpuState.initial()
          .copyWith(errorMessage: 'oops')
          .copyWith(errorMessage: null);
      expect(s.errorMessage, isNull);
    });

    test('copyWith(processes: ...) sets list', () {
      final s = DgpuState.initial().copyWith(processes: [_proc]);
      expect(s.processes, hasLength(1));
    });

    test('copyWith(pciAddress: null) clears it', () {
      final s = DgpuState.initial()
          .copyWith(pciAddress: '0000:01:00.0')
          .copyWith(pciAddress: null);
      expect(s.pciAddress, isNull);
    });
  });

  group('DgpuState props', () {
    test('identical initial states are equal', () {
      expect(DgpuState.initial(), equals(DgpuState.initial()));
    });

    test('differ when isActive differs', () {
      final a = DgpuState.initial().copyWith(isActive: true);
      final b = DgpuState.initial().copyWith(isActive: false);
      expect(a, isNot(equals(b)));
    });

    test('differ when processes differ', () {
      final a = DgpuState.initial().copyWith(processes: [_proc]);
      final b = DgpuState.initial();
      expect(a, isNot(equals(b)));
    });
  });
}
