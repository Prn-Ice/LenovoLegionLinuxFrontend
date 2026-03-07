import '../../../core/services/legion_frontend_bridge_service.dart';
import '../models/boot_logo_snapshot.dart';
import '../models/boot_logo_status.dart';

class BootLogoRepositoryException implements Exception {
  const BootLogoRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BootLogoRepository {
  const BootLogoRepository({required LegionFrontendBridgeService bridgeService})
    : _bridgeService = bridgeService;

  final LegionFrontendBridgeService _bridgeService;

  Future<BootLogoSnapshot> loadSnapshot() async {
    try {
      final result = await _bridgeService.runCommand(
        method: 'boot-logo.status',
        args: ['boot-logo', 'status'],
        privileged: false,
        detectUnavailableResponse: false,
      );

      if (!result.ok) {
        return const BootLogoSnapshot(status: null);
      }

      final status = BootLogoStatus.parseStatusOutput(result.stdout);
      return BootLogoSnapshot(status: status);
    } catch (_) {
      return const BootLogoSnapshot(status: null);
    }
  }

  Future<void> enableBootLogo(String imagePath) async {
    await _runPrivilegedCommand(
      ['boot-logo', 'enable', imagePath],
      method: 'boot-logo.enable',
      failurePrefix: 'Failed to enable boot logo',
    );
  }

  Future<void> restoreBootLogo() async {
    await _runPrivilegedCommand(
      ['boot-logo', 'restore'],
      method: 'boot-logo.restore',
      failurePrefix: 'Failed to restore boot logo',
    );
  }

  Future<void> _runPrivilegedCommand(
    List<String> args, {
    required String method,
    required String failurePrefix,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    try {
      await _bridgeService.runPrivilegedCommand(
        method: method,
        args: args,
        timeout: timeout,
      );
    } on LegionBridgeException catch (error) {
      final details = error.details;
      final message = details.isEmpty
          ? '$failurePrefix.'
          : '$failurePrefix: $details';
      throw BootLogoRepositoryException(message);
    }
  }
}
