abstract class DgpuEvent {
  const DgpuEvent();
}

final class DgpuStarted extends DgpuEvent {
  const DgpuStarted();
}

final class DgpuRefreshRequested extends DgpuEvent {
  const DgpuRefreshRequested();
}

/// Kill all compute processes using the GPU (privileged).
final class DgpuKillProcessesRequested extends DgpuEvent {
  const DgpuKillProcessesRequested();
}

/// Remove the GPU from the PCI tree and rescan to reinitialise (privileged).
final class DgpuRestartPciRequested extends DgpuEvent {
  const DgpuRestartPciRequested();
}
