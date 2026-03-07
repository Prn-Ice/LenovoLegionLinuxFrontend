abstract class BootLogoEvent {
  const BootLogoEvent();
}

final class BootLogoStarted extends BootLogoEvent {
  const BootLogoStarted();
}

final class BootLogoFileSelected extends BootLogoEvent {
  const BootLogoFileSelected(this.imagePath);

  final String imagePath;
}

final class BootLogoApplyRequested extends BootLogoEvent {
  const BootLogoApplyRequested();
}

final class BootLogoRestoreRequested extends BootLogoEvent {
  const BootLogoRestoreRequested();
}

final class BootLogoRefreshRequested extends BootLogoEvent {
  const BootLogoRefreshRequested();
}
