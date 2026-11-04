import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/platform_surfaces/models/platform_event.dart';
import 'package:legion_frontend/features/platform_surfaces/osd/native_osd.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/native-osd');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late NativeOsd osd;

  setUp(() {
    calls = [];
    osd = NativeOsd(channel: channel);
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  Future<OsdDelivery> show(
    PlatformEvent event, {
    bool enabled = true,
    bool visible = false,
    Duration duration = const Duration(seconds: 2),
  }) => osd.showConfirmed(
    event,
    enabled: enabled,
    mainWindowVisible: visible,
    duration: duration,
  );

  test('forwards confirmed content with bounded native lifetime', () async {
    expect(await osd.isSupported(), isTrue);
    expect(
      await show(
        const KeyboardBrightnessChanged(fraction: 0.75),
        duration: const Duration(days: 1),
      ),
      OsdDelivery.shown,
    );
    expect(calls.last.arguments, {
      'title': 'Keyboard brightness',
      'value': '75%',
      'durationMs': 5000,
    });
    await show(const FanBoostChanged(enabled: false), duration: Duration.zero);
    expect(calls.last.arguments['durationMs'], 500);
    expect(calls.last.arguments['value'], 'Off');
  });

  test('preference, foreground and unknown values suppress delivery', () async {
    const event = PowerModeChanged(label: 'Balanced');
    expect(await show(event, enabled: false), OsdDelivery.suppressed);
    expect(await show(event, visible: true), OsdDelivery.suppressed);
    for (final event in <PlatformEvent>[
      const PowerModeChanged(label: null),
      const PowerModeChanged(label: '  '),
      const FanBoostChanged(enabled: null),
      const AutomationChanged(description: null),
      const KeyboardBrightnessChanged(fraction: double.nan),
      const KeyboardBrightnessChanged(fraction: 2),
    ]) {
      expect(await show(event), OsdDelivery.suppressed);
    }
    expect(calls, isEmpty);
  });

  test(
    'replacement sends no Dart timer and disposal hides exactly once',
    () async {
      await show(const PowerModeChanged(label: 'Quiet'));
      await show(const PowerModeChanged(label: 'Performance'));
      await osd.dispose();
      await osd.dispose();
      await osd.hide();
      expect(await osd.isSupported(), isFalse);
      expect(
        await show(const FanBoostChanged(enabled: true)),
        OsdDelivery.suppressed,
      );
      expect(calls.map((call) => call.method), ['show', 'show', 'hide']);
    },
  );

  test('missing channel and transport failures report unavailable', () async {
    for (final error in [
      MissingPluginException(),
      PlatformException(code: 'disconnected'),
    ]) {
      messenger.setMockMethodCallHandler(channel, (_) async => throw error);
      expect(await osd.isSupported(), isFalse);
      expect(
        await show(const FanBoostChanged(enabled: true)),
        OsdDelivery.unavailable,
      );
      await osd.hide();
    }
    await osd.dispose();
  });

  test(
    'unsupported native backend and long Unicode text remain truthful',
    () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return false;
      });
      expect(await osd.isSupported(), isFalse);
      expect(
        await show(AutomationChanged(description: '💡' * 300)),
        OsdDelivery.unavailable,
      );
      expect((calls.last.arguments['value'] as String).runes.length, 240);
    },
  );
}
