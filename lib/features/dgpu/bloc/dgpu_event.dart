import 'package:equatable/equatable.dart';

import '../models/graphics_mode.dart';

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

final class DgpuGraphicsModeSetRequested extends DgpuEvent {
  const DgpuGraphicsModeSetRequested(this.mode);

  final GraphicsMode mode;

  @override
  List<Object?> get props => [mode];
}

/// Kill all compute processes using the GPU (privileged).
final class DgpuKillProcessesRequested extends DgpuEvent {
  const DgpuKillProcessesRequested(this.expectedPids);

  final List<int> expectedPids;

  @override
  List<Object?> get props => [expectedPids];
}

/// Remove the GPU from the PCI tree and re-scan to re-initialize (privileged).
final class DgpuRestartPciRequested extends DgpuEvent {
  const DgpuRestartPciRequested(this.expectedPciAddress);

  final String expectedPciAddress;

  @override
  List<Object?> get props => [expectedPciAddress];
}
