import 'package:riverbloc/riverbloc.dart';

import '../../../core/models/app_failure.dart';
import '../../../core/providers/system_services_provider.dart';
import '../../../core/services/legion_control_client.dart';
import '../../../core/services/package_power_telemetry_service.dart';

enum PackagePowerState { off, enabling, on, disabling }

final packagePowerProvider = BlocProvider<PackagePowerCubit, PackagePowerState>(
  (ref) => PackagePowerCubit(ref.watch(packagePowerTelemetryClientProvider)),
);

class PackagePowerCubit extends Cubit<PackagePowerState> {
  PackagePowerCubit(this._client) : super(PackagePowerState.off);

  final PackagePowerTelemetryClient _client;

  Future<void> setEnabled(bool enabled) async {
    final expected = enabled ? PackagePowerState.off : PackagePowerState.on;
    if (state != expected || isClosed) return;

    emit(enabled ? PackagePowerState.enabling : PackagePowerState.disabling);
    try {
      if (enabled) {
        await _client.enable();
      } else {
        await _client.disable();
      }
      if (!isClosed) {
        emit(enabled ? PackagePowerState.on : PackagePowerState.off);
      }
    } catch (error) {
      if (isClosed) return;
      emit(PackagePowerState.off);
      final message = switch (error) {
        LegionControlStartupDeniedException() => 'CPU power readings are off. To try again, turn them on in Settings and approve the authentication prompt.',
        _ when enabled => 'Could not enable CPU power readings. Reopen the app before trying again.',
        _ => 'CPU power readings stopped. Reopen the app to make sure the helper has closed.',
      };
      throw AppFailure(message, details: error.toString());
    }
  }
}
