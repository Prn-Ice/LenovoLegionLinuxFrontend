import 'dart:convert';
import 'dart:io';

import '../models/automation_config.dart';

/// Stores keyboard assignments in the existing file, replacing obsolete rules
/// on the next save. No legacy rule has an execution path in the application.
class AutomationRepository {
  AutomationRepository({File? configFile})
    : _configFile =
          configFile ??
          File(
            '${Platform.environment['XDG_CONFIG_HOME'] ?? '${Platform.environment['HOME']}/.config'}/legion_frontend/automation_rules.json',
          );

  final File _configFile;

  Future<AutomationConfig> loadConfig() async {
    if (!await _configFile.exists()) return AutomationConfig.defaults();
    final parsed = jsonDecode(await _configFile.readAsString());
    if (parsed is! Map<String, dynamic>) {
      throw const FormatException(
        'Keyboard assignments must be a JSON object.',
      );
    }
    return AutomationConfig.fromJson(parsed);
  }

  Future<void> saveConfig(AutomationConfig config) async {
    await _configFile.parent.create(recursive: true);
    final pending = File('${_configFile.path}.pending');
    await pending.writeAsString(
      const JsonEncoder.withIndent('  ').convert(config.toJson()),
      flush: true,
    );
    await pending.rename(_configFile.path);
  }
}
