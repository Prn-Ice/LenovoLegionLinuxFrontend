import '../../../core/models/app_failure.dart';
import '../../../core/data/privileged_repository.dart';
import '../models/boot_logo_snapshot.dart';
import '../models/boot_logo_status.dart';

class BootLogoRepositoryException extends AppFailure {
  const BootLogoRepositoryException(super.message, {super.kind, super.details});
}

class BootLogoRepository extends PrivilegedRepository {
  const BootLogoRepository({required super.bridgeService});

  @override
  Exception wrapBridgeError(AppFailure failure) => BootLogoRepositoryException(
    failure.message,
    kind: failure.kind,
    details: failure.details,
  );

  Future<BootLogoSnapshot> loadSnapshot() async {
    try {
      final result = await bridgeService.runCommand(
        method: 'boot-logo.status',
        args: ['boot-logo', 'status'],
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
    await runPrivilegedCommand(
      ['boot-logo', 'enable', imagePath],
      method: 'boot-logo.enable',
      failurePrefix: 'Failed to enable boot logo',
      timeout: const Duration(seconds: 30),
    );
  }

  Future<void> restoreBootLogo() async {
    await runPrivilegedCommand(
      ['boot-logo', 'restore'],
      method: 'boot-logo.restore',
      failurePrefix: 'Failed to restore boot logo',
      timeout: const Duration(seconds: 30),
    );
  }
}
