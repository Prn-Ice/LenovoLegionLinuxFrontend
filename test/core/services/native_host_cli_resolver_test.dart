import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/core/services/native_host_cli_resolver.dart';
import 'package:legion_frontend/core/services/legion_control_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('io.github.prnice.legion/portable_control');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('resolves only fixed host locations without starting control', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return '/nix/store/host-cli/bin/legion_cli';
    });
    expect(await resolveNativeHostCli(), '/nix/store/host-cli/bin/legion_cli');
    expect(calls.single.method, 'findHostCli');
    expect(calls.single.arguments, isNull);
  });

  test('rejects missing or malformed host CLI without PATH fallback', () async {
    for (final value in [null, '', 'legion_cli', '/tmp/cli\u0000bad']) {
      messenger.setMockMethodCallHandler(channel, (_) async => value);
      await expectLater(
        resolveNativeHostCli(),
        throwsA(isA<LegionControlPortableSetupException>()),
      );
    }
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'setup', message: 'Unsafe CLI selector');
    });
    await expectLater(
      resolveNativeHostCli(),
      throwsA(isA<LegionControlPortableSetupException>()),
    );
  });
}
