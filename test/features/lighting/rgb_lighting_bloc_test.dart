import 'dart:ui' show Color;

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/lighting/bloc/rgb_lighting_bloc.dart';
import 'package:legion_frontend/features/lighting/bloc/rgb_lighting_event.dart';
import 'package:legion_frontend/features/lighting/bloc/rgb_lighting_state.dart';
import 'package:legion_frontend/features/lighting/models/openrgb_device.dart';
import 'package:legion_frontend/features/lighting/models/rgb_lighting_snapshot.dart';
import 'package:legion_frontend/features/lighting/repository/rgb_lighting_repository.dart';
import 'package:legion_frontend/features/lighting/repository/rgb_lighting_store.dart';
import 'package:legion_frontend/features/lighting/services/spectrum_effects.dart';

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

class _FakeStore extends RgbLightingStore {
  _FakeStore([this.snapshot]) : super(null);

  final RgbLightingSnapshot? snapshot;
  RgbLightingSnapshot? saved;

  @override
  RgbLightingSnapshot? load() => snapshot;

  @override
  Future<void> save(RgbLightingSnapshot snapshot) async => saved = snapshot;
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

    blocTest<RgbLightingBloc, RgbLightingState>(
      'KeyErased turns a painted LED off',
      build: () => RgbLightingBloc(repository: repo),
      act: (b) => _startThen(b, () {
        b.add(const RgbColorSelected(Color(0xFFFF0000)));
        b.add(const RgbKeyPainted(1));
        b.add(const RgbKeyErased(1));
      }),
      verify: (b) {
        expect(b.state.keyColors[1], const Color(0xFF000000));
        expect(repo.lastDirect?[1], const Color(0xFF000000));
      },
    );

    blocTest<RgbLightingBloc, RgbLightingState>(
      'KeyPicked copies an LED color into the selected color',
      build: () => RgbLightingBloc(repository: repo),
      act: (b) => _startThen(b, () {
        b.add(const RgbColorSelected(Color(0xFF00FF00)));
        b.add(const RgbKeyPainted(2));
        b.add(const RgbColorSelected(Color(0xFFFF0000)));
        b.add(const RgbKeyPicked(2));
      }),
      verify: (b) => expect(b.state.selectedColor, const Color(0xFF00FF00)),
    );

    blocTest<RgbLightingBloc, RgbLightingState>(
      'RegionFilled paints only the given LEDs',
      build: () => RgbLightingBloc(repository: repo),
      act: (b) => _startThen(b, () {
        b.add(const RgbColorSelected(Color(0xFF0000FF)));
        b.add(const RgbRegionFilled([0, 2]));
      }),
      verify: (b) {
        expect(b.state.keyColors[0], const Color(0xFF0000FF));
        expect(b.state.keyColors[1], const Color(0xFF000000));
        expect(b.state.keyColors[2], const Color(0xFF0000FF));
      },
    );

    blocTest<RgbLightingBloc, RgbLightingState>(
      'Static fills the keyboard, saving the Direct buffer; Direct restores it',
      build: () => RgbLightingBloc(repository: repo),
      act: (b) => _startThen(b, () {
        b.add(const RgbColorSelected(Color(0xFFFF0000)));
        b.add(const RgbKeyPainted(0));
        b.add(const RgbColorSelected(Color(0xFF00FF00)));
        b.add(const RgbModeSelected('Static'));
        b.add(const RgbModeSelected('Direct'));
      }),
      verify: (b) {
        expect(b.state.activeMode, 'Direct');
        expect(b.state.keyColors[0], const Color(0xFFFF0000));
        expect(b.state.keyColors[1], const Color(0xFF000000));
      },
    );

    blocTest<RgbLightingBloc, RgbLightingState>(
      'Static applies color changes immediately as a uniform fill',
      build: () => RgbLightingBloc(repository: repo),
      act: (b) => _startThen(b, () {
        b.add(const RgbModeSelected('Static'));
        b.add(const RgbColorSelected(Color(0xFF123456)));
      }),
      verify: (b) {
        expect(b.state.activeMode, 'Static');
        expect(b.state.keyColors, everyElement(const Color(0xFF123456)));
      },
    );

    blocTest<RgbLightingBloc, RgbLightingState>(
      'EffectAssigned adds a region effect tinted by the selected color',
      build: () => RgbLightingBloc(repository: repo),
      act: (b) => _startThen(b, () {
        b.add(const RgbColorSelected(Color(0xFFFF0000)));
        b.add(const RgbEffectAssigned('Numpad', [1, 2], SpectrumEffect.pulse));
      }),
      verify: (b) {
        expect(b.state.effects.single.label, 'Numpad');
        expect(b.state.effects.single.ledIndices, [1, 2]);
        expect(b.state.effects.single.effect, SpectrumEffect.pulse);
        expect(b.state.effects.single.color, const Color(0xFFFF0000));
      },
    );

    blocTest<RgbLightingBloc, RgbLightingState>(
      'EffectAssigned replaces the effect already on that scope',
      build: () => RgbLightingBloc(repository: repo),
      act: (b) => _startThen(b, () {
        b.add(const RgbEffectAssigned('Numpad', [1], SpectrumEffect.pulse));
        b.add(const RgbEffectAssigned('Numpad', [1], SpectrumEffect.wave));
      }),
      verify: (b) {
        expect(b.state.effects.length, 1);
        expect(b.state.effects.single.effect, SpectrumEffect.wave);
      },
    );

    blocTest<RgbLightingBloc, RgbLightingState>(
      'EffectsCleared removes every effect',
      build: () => RgbLightingBloc(repository: repo),
      act: (b) => _startThen(b, () {
        b.add(
          const RgbEffectAssigned('All', [0, 1, 2], SpectrumEffect.rainbow),
        );
        b.add(const RgbEffectsCleared());
      }),
      verify: (b) => expect(b.state.effects, isEmpty),
    );

    blocTest<RgbLightingBloc, RgbLightingState>(
      'Started restores and re-applies a saved snapshot that fits the device',
      build: () => RgbLightingBloc(
        repository: repo,
        store: _FakeStore(
          const RgbLightingSnapshot(
            keyColors: [
              Color(0xFFFF0000),
              Color(0xFF00FF00),
              Color(0xFF0000FF),
            ],
            selectedColor: Color(0xFF00FF00),
            brightness: 55,
            activeMode: 'Direct',
            effects: [],
          ),
        ),
      ),
      act: (b) => b.add(const RgbLightingStarted()),
      verify: (b) {
        expect(b.state.keyColors, [
          const Color(0xFFFF0000),
          const Color(0xFF00FF00),
          const Color(0xFF0000FF),
        ]);
        expect(b.state.brightness, 55);
        expect(b.state.selectedColor, const Color(0xFF00FF00));
        expect(repo.lastDirect, isNotNull); // re-applied (native absent → CLI)
      },
    );

    test('persists the painting whenever it changes', () async {
      final store = _FakeStore();
      final bloc = RgbLightingBloc(repository: repo, store: store);
      await _startThen(bloc, () {
        bloc.add(const RgbColorSelected(Color(0xFFAABBCC)));
        bloc.add(const RgbKeyPainted(0));
      });
      await Future<void>.delayed(Duration.zero);
      expect(store.saved, isNotNull);
      expect(store.saved!.keyColors[0], const Color(0xFFAABBCC));
      await bloc.close();
    });
  });
}
