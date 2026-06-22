import 'dart:ui' show Color;

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/lighting/bloc/rgb_lighting_bloc.dart';
import 'package:legion_frontend/features/lighting/bloc/rgb_lighting_event.dart';
import 'package:legion_frontend/features/lighting/bloc/rgb_lighting_state.dart';
import 'package:legion_frontend/features/lighting/models/openrgb_device.dart';
import 'package:legion_frontend/features/lighting/repository/rgb_lighting_repository.dart';

const _kbd = OpenRgbDevice(
  index: 0,
  name: 'Legion KB',
  type: 'Keyboard',
  modes: ['Static', 'Direct'],
  leds: ['a', 'b', 'c'],
);

class _FakeRepo extends RgbLightingRepository {
  _FakeRepo({this.device = _kbd}) : super();

  final OpenRgbDevice? device;

  String? lastMode;
  Color? lastModeColor;
  List<Color>? lastDirect;
  int? lastBrightness;

  @override
  Future<OpenRgbDevice?> loadKeyboard() async => device;

  @override
  Future<void> applyMode(
    OpenRgbDevice device,
    String mode, {
    Color? color,
    int? brightness,
  }) async {
    lastMode = mode;
    lastModeColor = color;
    lastBrightness = brightness;
  }

  @override
  Future<void> applyDirect(
    OpenRgbDevice device,
    List<Color> colors, {
    int? brightness,
  }) async {
    lastDirect = colors;
    lastBrightness = brightness;
  }

  @override
  Future<void> setBrightness(OpenRgbDevice device, int percent) async {
    lastBrightness = percent;
  }
}

/// act() that loads the device, then runs [more].
Future<void> _startThen(RgbLightingBloc bloc, void Function() more) async {
  bloc.add(const RgbLightingStarted());
  await Future<void>.delayed(Duration.zero);
  more();
}

void main() {
  group('RgbLightingBloc', () {
    late _FakeRepo repo;
    setUp(() => repo = _FakeRepo());

    blocTest<RgbLightingBloc, RgbLightingState>(
      'Started loads the keyboard and sizes the key buffer',
      build: () => RgbLightingBloc(repository: repo),
      act: (b) => b.add(const RgbLightingStarted()),
      verify: (b) {
        expect(b.state.available, isTrue);
        expect(b.state.device?.name, 'Legion KB');
        expect(b.state.keyColors.length, 3);
      },
    );

    blocTest<RgbLightingBloc, RgbLightingState>(
      'Started with no device marks unavailable',
      build: () => RgbLightingBloc(repository: _FakeRepo(device: null)),
      act: (b) => b.add(const RgbLightingStarted()),
      verify: (b) => expect(b.state.available, isFalse),
    );

    blocTest<RgbLightingBloc, RgbLightingState>(
      'ModeSelected applies the mode with the selected color',
      build: () => RgbLightingBloc(repository: repo),
      act: (b) => _startThen(b, () => b.add(const RgbModeSelected('Static'))),
      verify: (b) {
        expect(repo.lastMode, 'Static');
        expect(repo.lastModeColor, b.state.selectedColor);
        expect(b.state.activeMode, 'Static');
      },
    );

    blocTest<RgbLightingBloc, RgbLightingState>(
      'ColorSelected updates the paint color without touching the device',
      build: () => RgbLightingBloc(repository: repo),
      act: (b) =>
          _startThen(b, () => b.add(const RgbColorSelected(Color(0xFF00FF00)))),
      verify: (b) {
        expect(b.state.selectedColor, const Color(0xFF00FF00));
        expect(repo.lastMode, isNull);
        expect(repo.lastDirect, isNull);
      },
    );

    blocTest<RgbLightingBloc, RgbLightingState>(
      'BrightnessChanged applies brightness',
      build: () => RgbLightingBloc(repository: repo),
      act: (b) => _startThen(b, () => b.add(const RgbBrightnessChanged(40))),
      verify: (b) {
        expect(repo.lastBrightness, 40);
        expect(b.state.brightness, 40);
      },
    );

    blocTest<RgbLightingBloc, RgbLightingState>(
      'KeyPainted paints one LED via Direct and records it in the buffer',
      build: () => RgbLightingBloc(repository: repo),
      act: (b) => _startThen(b, () {
        b.add(const RgbColorSelected(Color(0xFFFF0000)));
        b.add(const RgbKeyPainted(1));
      }),
      verify: (b) {
        expect(b.state.activeMode, 'Direct');
        expect(b.state.keyColors[1], const Color(0xFFFF0000));
        expect(repo.lastDirect?[1], const Color(0xFFFF0000));
        expect(repo.lastDirect?.length, 3);
      },
    );

    blocTest<RgbLightingBloc, RgbLightingState>(
      'AllKeysFilled fills every LED via Direct',
      build: () => RgbLightingBloc(repository: repo),
      act: (b) =>
          _startThen(b, () => b.add(const RgbAllKeysFilled(Color(0xFF0000FF)))),
      verify: (b) {
        expect(b.state.keyColors, everyElement(const Color(0xFF0000FF)));
        expect(repo.lastDirect?.length, 3);
      },
    );
  });
}
