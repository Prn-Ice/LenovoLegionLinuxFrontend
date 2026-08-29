import 'package:dbus/dbus.dart';

abstract interface class PackagePowerTelemetryClient {
  Future<double?> readPackagePowerWatts();
}

class DBusPackagePowerTelemetryClient implements PackagePowerTelemetryClient {
  DBusPackagePowerTelemetryClient({DBusClient? client})
    : _client = client ?? DBusClient.system() {
    _object = DBusRemoteObject(
      _client,
      name: _busName,
      path: DBusObjectPath(_objectPath),
    );
  }

  static const _busName = 'io.github.prnice.LegionTelemetry1';
  static const _objectPath = '/io/github/prnice/LegionTelemetry1';
  static const _interface = 'io.github.prnice.LegionTelemetry1';

  final DBusClient _client;
  late final DBusRemoteObject _object;

  @override
  Future<double?> readPackagePowerWatts() async {
    try {
      final response = await _object
          .callMethod(
            _interface,
            'GetSnapshot',
            const [],
            replySignature: DBusSignature('a{sv}'),
          )
          .timeout(const Duration(seconds: 2));
      if (response.returnValues.length != 1) return null;
      return parseSnapshot(response.returnValues.single.asStringVariantDict());
    } catch (_) {
      return null;
    }
  }

  static double? parseSnapshot(Map<String, DBusValue> values) {
    final available = values['Available'];
    final watts = values['PackagePowerWatts'];
    final version = values['Version'];
    if (available is! DBusBoolean ||
        !available.value ||
        watts is! DBusDouble ||
        version is! DBusString ||
        version.value != '1' ||
        !watts.value.isFinite ||
        watts.value < 0) {
      return null;
    }
    return watts.value;
  }

  Future<void> close() => _client.close();
}
