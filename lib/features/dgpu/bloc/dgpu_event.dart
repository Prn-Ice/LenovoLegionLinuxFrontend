import 'package:equatable/equatable.dart';

sealed class DgpuEvent extends Equatable {
  const DgpuEvent();

  @override
  List<Object?> get props => const [];
}

final class DgpuStarted extends DgpuEvent {
  const DgpuStarted();
}

final class DgpuRefreshRequested extends DgpuEvent {
  const DgpuRefreshRequested();
}

final class DgpuTicked extends DgpuEvent {
  const DgpuTicked();
}

/// Kill all compute processes using the GPU (privileged).
final class DgpuKillProcessesRequested extends DgpuEvent {
  const DgpuKillProcessesRequested();
}

/// Remove the GPU from the PCI tree and re-scan to re-initialize (privileged).
final class DgpuRestartPciRequested extends DgpuEvent {
  const DgpuRestartPciRequested();
}

/// Enable or disable hybrid mode (privileged). Reboot required.
final class HybridModeSetRequested extends DgpuEvent {
  const HybridModeSetRequested(this.enabled);

  final bool enabled;

  @override
  List<Object?> get props => [enabled];
}
