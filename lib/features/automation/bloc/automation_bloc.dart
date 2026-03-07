import 'dart:async';

import 'package:riverbloc/riverbloc.dart';

import '../models/automation_config.dart';
import '../models/automation_trigger_snapshot.dart';
import '../repository/automation_repository.dart';
import 'automation_event.dart';
import 'automation_state.dart';

class AutomationBloc extends Bloc<AutomationEvent, AutomationState> {
  AutomationBloc({required AutomationRepository repository})
    : _repository = repository,
      super(AutomationState.initial()) {
    on<AutomationStarted>(_onStarted);
    on<AutomationRunnerToggled>(_onRunnerToggled);
    on<AutomationPollIntervalUpdated>(_onPollIntervalUpdated);
    on<AutomationFanPresetRuleToggled>(_onFanPresetRuleToggled);
    on<AutomationTriggerOnProfileChangeToggled>(
      _onTriggerOnProfileChangeToggled,
    );
    on<AutomationTriggerOnPowerSourceChangeToggled>(
      _onTriggerOnPowerSourceChangeToggled,
    );
    on<AutomationConservationRuleToggled>(_onConservationRuleToggled);
    on<AutomationRapidChargingPolicyToggled>(_onRapidChargingPolicyToggled);
    on<AutomationRapidChargingTargetsUpdated>(_onRapidChargingTargetsUpdated);
    on<AutomationConservationLimitsUpdated>(_onConservationLimitsUpdated);
    on<AutomationExternalCommandRuleToggled>(_onExternalCommandRuleToggled);
    on<AutomationExternalCommandUpdated>(_onExternalCommandUpdated);
    on<AutomationExternalCommandTriggerUpdated>(
      _onExternalCommandTriggerUpdated,
    );
    on<AutomationRunNowRequested>(_onRunNowRequested);
    on<AutomationTicked>(_onTicked);
  }

  final AutomationRepository _repository;

  Timer? _timer;
  AutomationTriggerSnapshot? _lastSnapshot;
  bool _runInFlight = false;

  Future<void> _onStarted(
    AutomationStarted event,
    Emitter<AutomationState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, errorMessage: null));

    final config = await _repository.loadConfig();
    final snapshot = await _repository.readTriggerSnapshot();
    _lastSnapshot = snapshot;

    emit(
      state.copyWith(
        config: config,
        currentSnapshot: snapshot,
        isLoading: false,
        errorMessage: null,
      ),
    );

    _restartTimerIfNeeded(config);
  }

  Future<void> _onRunnerToggled(
    AutomationRunnerToggled event,
    Emitter<AutomationState> emit,
  ) async {
    final updatedConfig = state.config.copyWith(runnerEnabled: event.enabled);
    await _persistConfig(updatedConfig, emit);
  }

  Future<void> _onTriggerOnProfileChangeToggled(
    AutomationTriggerOnProfileChangeToggled event,
    Emitter<AutomationState> emit,
  ) async {
    final updatedConfig = state.config.copyWith(
      triggerOnProfileChange: event.enabled,
    );
    await _persistConfig(updatedConfig, emit);
  }

  Future<void> _onTriggerOnPowerSourceChangeToggled(
    AutomationTriggerOnPowerSourceChangeToggled event,
    Emitter<AutomationState> emit,
  ) async {
    final updatedConfig = state.config.copyWith(
      triggerOnPowerSourceChange: event.enabled,
    );
    await _persistConfig(updatedConfig, emit);
  }

  Future<void> _onRapidChargingPolicyToggled(
    AutomationRapidChargingPolicyToggled event,
    Emitter<AutomationState> emit,
  ) async {
    final updatedConfig = state.config.copyWith(
      applyRapidChargingPolicy: event.enabled,
    );
    await _persistConfig(updatedConfig, emit);
  }

  Future<void> _onRapidChargingTargetsUpdated(
    AutomationRapidChargingTargetsUpdated event,
    Emitter<AutomationState> emit,
  ) async {
    final updatedConfig = state.config.copyWith(
      rapidChargingOnAc: event.onAc,
      rapidChargingOnBattery: event.onBattery,
    );
    await _persistConfig(updatedConfig, emit);
  }

  Future<void> _onPollIntervalUpdated(
    AutomationPollIntervalUpdated event,
    Emitter<AutomationState> emit,
  ) async {
    final updatedConfig = state.config.copyWith(
      pollIntervalSeconds: event.seconds,
    );
    await _persistConfig(updatedConfig, emit);
  }

  Future<void> _onFanPresetRuleToggled(
    AutomationFanPresetRuleToggled event,
    Emitter<AutomationState> emit,
  ) async {
    final updatedConfig = state.config.copyWith(
      applyFanPresetOnContextChange: event.enabled,
    );
    await _persistConfig(updatedConfig, emit);
  }

  Future<void> _onConservationRuleToggled(
    AutomationConservationRuleToggled event,
    Emitter<AutomationState> emit,
  ) async {
    final updatedConfig = state.config.copyWith(
      applyCustomConservation: event.enabled,
    );
    await _persistConfig(updatedConfig, emit);
  }

  Future<void> _onConservationLimitsUpdated(
    AutomationConservationLimitsUpdated event,
    Emitter<AutomationState> emit,
  ) async {
    final updatedConfig = state.config.copyWith(
      conservationLowerLimit: event.lower,
      conservationUpperLimit: event.upper,
    );
    await _persistConfig(updatedConfig, emit);
  }

  Future<void> _onExternalCommandRuleToggled(
    AutomationExternalCommandRuleToggled event,
    Emitter<AutomationState> emit,
  ) async {
    final updatedConfig = state.config.copyWith(
      runExternalCommand: event.enabled,
    );
    await _persistConfig(updatedConfig, emit);
  }

  Future<void> _onExternalCommandUpdated(
    AutomationExternalCommandUpdated event,
    Emitter<AutomationState> emit,
  ) async {
    final updatedConfig = state.config.copyWith(externalCommand: event.command);
    await _persistConfig(updatedConfig, emit);
  }

  Future<void> _onExternalCommandTriggerUpdated(
    AutomationExternalCommandTriggerUpdated event,
    Emitter<AutomationState> emit,
  ) async {
    final updatedConfig = state.config.copyWith(
      externalCommandOnContextChange: event.onContextChange,
    );
    await _persistConfig(updatedConfig, emit);
  }

  Future<void> _onRunNowRequested(
    AutomationRunNowRequested event,
    Emitter<AutomationState> emit,
  ) async {
    await _executeCycle(emit, forceFanPreset: true);
  }

  Future<void> _onTicked(
    AutomationTicked event,
    Emitter<AutomationState> emit,
  ) async {
    await _executeCycle(emit, forceFanPreset: false);
  }

  Future<void> _persistConfig(
    AutomationConfig config,
    Emitter<AutomationState> emit,
  ) async {
    await _repository.saveConfig(config);
    emit(state.copyWith(config: config, errorMessage: null));
    _restartTimerIfNeeded(config);
  }

  void _restartTimerIfNeeded(AutomationConfig config) {
    _timer?.cancel();

    if (!config.runnerEnabled) {
      return;
    }

    _timer = Timer.periodic(
      Duration(seconds: config.pollIntervalSeconds),
      (_) => add(const AutomationTicked()),
    );
  }

  Future<void> _executeCycle(
    Emitter<AutomationState> emit, {
    required bool forceFanPreset,
  }) async {
    if (_runInFlight) {
      return;
    }

    _runInFlight = true;
    emit(state.copyWith(isExecuting: true, errorMessage: null));

    try {
      final snapshot = await _repository.readTriggerSnapshot();
      final actions = <String>[];

      final previousSnapshot = _lastSnapshot;
      final profileChanged =
          previousSnapshot != null &&
          previousSnapshot.platformProfile != snapshot.platformProfile;
      final powerSourceChanged =
          previousSnapshot != null &&
          previousSnapshot.onPowerSupply != snapshot.onPowerSupply;
      final hasSelectedContextChange =
          (state.config.triggerOnProfileChange && profileChanged) ||
          (state.config.triggerOnPowerSourceChange && powerSourceChanged);
      final shouldRunContextActions =
          forceFanPreset || hasSelectedContextChange;

      if (state.config.applyFanPresetOnContextChange &&
          shouldRunContextActions) {
        await _repository.applyFanPresetForCurrentContext();
        actions.add('Applied fan preset for current power context');
      }

      if (state.config.applyCustomConservation) {
        if (!state.config.hasValidConservationRange) {
          throw AutomationRepositoryException(
            'Invalid conservation limits: lower limit is above upper limit.',
          );
        }

        await _repository.applyCustomConservation(
          lowerLimit: state.config.conservationLowerLimit,
          upperLimit: state.config.conservationUpperLimit,
        );
        actions.add(
          'Applied conservation policy (${state.config.conservationLowerLimit}-${state.config.conservationUpperLimit}%)',
        );
      }

      if (state.config.applyRapidChargingPolicy && shouldRunContextActions) {
        final onPowerSupply = snapshot.onPowerSupply;
        if (onPowerSupply == null) {
          actions.add(
            'Skipped rapid charging policy (power source unavailable)',
          );
        } else {
          final enableRapidCharging = onPowerSupply
              ? state.config.rapidChargingOnAc
              : state.config.rapidChargingOnBattery;
          await _repository.setRapidChargingEnabled(enableRapidCharging);
          actions.add(
            'Set rapid charging to ${enableRapidCharging ? 'enabled' : 'disabled'} for ${onPowerSupply ? 'AC' : 'battery'}',
          );
        }
      }

      if (state.config.runExternalCommand &&
          state.config.externalCommand.trim().isNotEmpty) {
        final runThisCycle =
            !state.config.externalCommandOnContextChange ||
            shouldRunContextActions;
        if (runThisCycle) {
          try {
            await _repository.runShellCommand(state.config.externalCommand);
            actions.add('Ran external command: ${state.config.externalCommand}');
          } on AutomationRepositoryException catch (e) {
            // Keep cycle non-fatal if user script fails.
            actions.add('External command failed: $e');
          }
        }
      }

      _lastSnapshot = snapshot;

      final summary = actions.isEmpty
          ? 'No actions triggered.'
          : actions.join(' | ');

      emit(
        state.copyWith(
          isExecuting: false,
          currentSnapshot: snapshot,
          lastRunAt: DateTime.now(),
          lastRunSummary: summary,
          errorMessage: null,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          isExecuting: false,
          errorMessage: '$error',
          lastRunAt: DateTime.now(),
        ),
      );
    } finally {
      _runInFlight = false;
    }
  }

  @override
  Future<void> close() {
    _timer?.cancel();
    return super.close();
  }
}
