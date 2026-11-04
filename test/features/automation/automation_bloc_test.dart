import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/automation/bloc/automation_bloc.dart';
import 'package:legion_frontend/features/automation/bloc/automation_event.dart';
import 'package:legion_frontend/features/automation/models/automation_config.dart';
import 'package:legion_frontend/features/automation/repository/automation_repository.dart';

class _Repository extends AutomationRepository {
  final loaded = Completer<AutomationConfig>();
  final writes = <AutomationConfig>[];
  bool fail = false;
  @override
  Future<AutomationConfig> loadConfig() => loaded.future;
  @override
  Future<void> saveConfig(AutomationConfig config) async {
    if (fail) throw StateError('disk full');
    writes.add(config);
  }
}

void main() {
  test(
    'initial read and rapid assignments are ordered; failed saves retain prior choices',
    () async {
      final repository = _Repository();
      final bloc = AutomationBloc(repository: repository);
      addTearDown(bloc.close);
      bloc.add(const AutomationStarted());
      bloc.add(const KeyboardProfileAssigned(KeyboardPowerMode.quiet, 'Night'));
      bloc.add(
        const KeyboardProfileAssigned(KeyboardPowerMode.custom, 'Studio'),
      );
      final saved = bloc.stream.firstWhere(
        (s) => s.config.profiles.length == 2,
      );
      repository.loaded.complete(AutomationConfig.defaults());
      await saved;
      expect(repository.writes.last.profiles, {
        KeyboardPowerMode.quiet: 'Night',
        KeyboardPowerMode.custom: 'Studio',
      });
      repository.fail = true;
      final failure = bloc.stream.firstWhere((s) => s.errorMessage != null);
      bloc.add(const KeyboardProfileAssigned(KeyboardPowerMode.quiet, null));
      expect((await failure).config.profiles[KeyboardPowerMode.quiet], 'Night');
      repository.fail = false;
      final retry = bloc.stream.firstWhere(
        (s) => !s.isSaving && s.config.profiles.length == 1,
      );
      bloc.add(const KeyboardProfileAssigned(KeyboardPowerMode.quiet, null));
      expect((await retry).errorMessage, isNull);
    },
  );

  test('closing during load prevents queued saves', () async {
    final repository = _Repository();
    final bloc = AutomationBloc(repository: repository);
    final loading = bloc.stream.firstWhere((s) => s.isLoading);
    bloc.add(const AutomationStarted());
    await loading;
    bloc.add(const KeyboardProfileAssigned(KeyboardPowerMode.quiet, 'Night'));
    final closed = bloc.close();
    repository.loaded.complete(AutomationConfig.defaults());
    await closed;
    expect(repository.writes, isEmpty);
  });
}
