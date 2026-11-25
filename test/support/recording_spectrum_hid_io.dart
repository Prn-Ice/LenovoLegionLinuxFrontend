import 'dart:typed_data';

import 'package:legion_frontend/features/lighting/services/spectrum_hid_io.dart';

/// Deterministic HID I/O for service and native integration journeys.
final class RecordingSpectrumHidIo implements SpectrumHidIo {
  RecordingSpectrumHidIo({
    this.openResult = 41,
    this.ioctlResult = 0,
    this.getFeatureResult = 0,
  });

  final int openResult;
  final int ioctlResult;
  final int getFeatureResult;
  final reports = <Uint8List>[];
  var closeCount = 0;
  var openCount = 0;

  @override
  int open(String path, int flags) {
    openCount++;
    return openResult;
  }

  @override
  int ioctl(int fd, int request, Uint8List buffer) {
    reports.add(Uint8List.fromList(buffer));
    // Linux HIDIOCGFEATURE uses request number 0x07.
    if ((request & 0xff) == 0x07 &&
        getFeatureResult >= 0 &&
        buffer.length > 4) {
      buffer[4] = 2;
      return getFeatureResult;
    }
    return ioctlResult;
  }

  @override
  int close(int fd) {
    closeCount++;
    return 0;
  }
}
