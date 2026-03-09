import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:legion_frontend/features/devices/bloc/devices_bloc.dart';
import 'package:legion_frontend/features/devices/bloc/devices_event.dart';
import 'package:legion_frontend/features/devices/bloc/devices_state.dart';
import 'package:legion_frontend/features/devices/models/devices_snapshot.dart';
import 'package:legion_frontend/features/devices/repository/devices_repository.dart';

class MockDevicesRepository extends Mock implements DevicesRepository {}

void main() {
  late MockDevicesRepository repo;
  setUp(() => repo = MockDevicesRepository());

  const snapshot = DevicesSnapshot(
    touchpadEnabled: null,
    touchpadSupported: false,
    winKeyEnabled: null,
    winKeySupported: false,
    fnLockEnabled: null,
    fnLockSupported: false,
    alwaysOnUsbEnabled: null,
    alwaysOnUsbSupported: false,
    cameraEnabled: null,
    cameraSupported: false,
  );

  const snapshotWithData = DevicesSnapshot(
    touchpadEnabled: true,
    touchpadSupported: true,
    winKeyEnabled: false,
    winKeySupported: true,
    fnLockEnabled: null,
    fnLockSupported: false,
    alwaysOnUsbEnabled: null,
    alwaysOnUsbSupported: false,
    cameraEnabled: null,
    cameraSupported: false,
  );

  blocTest<DevicesBloc, DevicesState>(
    'emits loading then loaded state on DevicesStarted',
    build: () {
      when(() => repo.loadSnapshot()).thenAnswer((_) async => snapshotWithData);
      return DevicesBloc(
        repository: repo,
        pollInterval: const Duration(seconds: 60),
      );
    },
    act: (bloc) => bloc.add(const DevicesStarted()),
    wait: const Duration(milliseconds: 100),
    expect: () => [
      isA<DevicesState>().having((s) => s.isLoading, 'isLoading', true),
      isA<DevicesState>().having(
        (s) => s.touchpadEnabled,
        'touchpadEnabled',
        true,
      ),
    ],
  );

  blocTest<DevicesBloc, DevicesState>(
    'emits loading then error on repository failure',
    build: () {
      when(() => repo.loadSnapshot()).thenThrow(Exception('sysfs error'));
      return DevicesBloc(
        repository: repo,
        pollInterval: const Duration(seconds: 60),
      );
    },
    act: (bloc) => bloc.add(const DevicesStarted()),
    wait: const Duration(milliseconds: 100),
    expect: () => [
      isA<DevicesState>().having((s) => s.isLoading, 'isLoading', true),
      isA<DevicesState>().having((s) => s.errorMessage, 'error', isNotNull),
    ],
  );

  group('DevicesBloc DevicesTicked', () {
    blocTest<DevicesBloc, DevicesState>(
      'DevicesTicked reloads silently when not applying',
      build: () {
        when(() => repo.loadSnapshot()).thenAnswer(
          (_) async => snapshotWithData,
        );
        return DevicesBloc(
          repository: repo,
          pollInterval: const Duration(seconds: 60),
        );
      },
      seed: () => DevicesState.initial(),
      act: (bloc) => bloc.add(const DevicesTicked()),
      expect: () => [
        isA<DevicesState>().having((s) => s.isLoading, 'isLoading', false),
      ],
    );

    blocTest<DevicesBloc, DevicesState>(
      'DevicesTicked is skipped when isApplying',
      build: () {
        when(() => repo.loadSnapshot()).thenAnswer((_) async => snapshot);
        return DevicesBloc(
          repository: repo,
          pollInterval: const Duration(seconds: 60),
        );
      },
      seed: () => DevicesState.initial().copyWith(isApplying: true),
      act: (bloc) => bloc.add(const DevicesTicked()),
      expect: () => isEmpty,
    );
  });
}
