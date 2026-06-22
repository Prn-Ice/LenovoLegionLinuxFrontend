import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'spectrum_protocol.dart';

typedef _OpenNative = Int32 Function(Pointer<Utf8>, Int32);
typedef _OpenDart = int Function(Pointer<Utf8>, int);
typedef _IoctlNative = Int32 Function(Int32, UnsignedLong, Pointer<Uint8>);
typedef _IoctlDart = int Function(int, int, Pointer<Uint8>);
typedef _CloseNative = Int32 Function(Int32);
typedef _CloseDart = int Function(int);

const int _oRdwr = 2;

/// Drives the Legion Spectrum keyboard (Gen 7/8) over `/dev/hidraw*` via libc
/// `ioctl(HIDIOCSFEATURE/HIDIOCGFEATURE)` — no libhidapi. Real-time: a full
/// per-key frame is one direct-mode enable + one frame write.
///
/// Frame bytes come from `spectrum_protocol.dart`; this is the thin (untestable)
/// I/O layer.
class SpectrumHidService {
  SpectrumHidService({this.vendorId = 0x048D, this.productId = 0xC987});

  final int vendorId;
  final int productId;

  static final DynamicLibrary _libc = DynamicLibrary.process();
  static final _open = _libc.lookupFunction<_OpenNative, _OpenDart>('open');
  static final _ioctl = _libc.lookupFunction<_IoctlNative, _IoctlDart>('ioctl');
  static final _close = _libc.lookupFunction<_CloseNative, _CloseDart>('close');

  int _fd = -1;
  bool _directEnabled = false;

  bool get isOpen => _fd >= 0;

  /// The `/dev/hidraw*` node whose HID_ID matches [vendorId]:[productId], or
  /// null when the keyboard isn't present.
  String? findHidrawPath() {
    final dir = Directory('/sys/class/hidraw');
    if (!dir.existsSync()) return null;
    for (final entry in dir.listSync()) {
      final name = entry.path.split('/').last;
      try {
        final uevent = File('${entry.path}/device/uevent').readAsStringSync();
        final match = RegExp(
          r'HID_ID=[0-9A-Fa-f]+:([0-9A-Fa-f]+):([0-9A-Fa-f]+)',
        ).firstMatch(uevent);
        if (match != null &&
            int.parse(match.group(1)!, radix: 16) == vendorId &&
            int.parse(match.group(2)!, radix: 16) == productId) {
          return '/dev/$name';
        }
      } on FileSystemException {
        // hidraw without a readable uevent — skip.
      }
    }
    return null;
  }

  /// Opens the keyboard's hidraw node. False when absent or permission-denied.
  bool open() {
    if (_fd >= 0) return true;
    final path = findHidrawPath();
    if (path == null) return false;
    final cPath = path.toNativeUtf8();
    try {
      _fd = _open(cPath, _oRdwr);
    } finally {
      malloc.free(cPath);
    }
    _directEnabled = false;
    return _fd >= 0;
  }

  void close() {
    if (_fd >= 0) {
      _close(_fd);
      _fd = -1;
      _directEnabled = false;
    }
  }

  /// Pushes a full per-key frame ([leds] carry hardware uint16 LED values),
  /// enabling direct mode on the active profile first. True if all writes ok.
  bool sendDirectFrame(List<SpectrumLed> leds) {
    if (!open()) return false;
    if (!_directEnabled) {
      final on = spectrumDirectModePacket(
        enable: true,
        profile: _activeProfile(),
      );
      if (!_setFeature(on)) return false;
      _directEnabled = true;
    }
    return _setFeature(spectrumDirectFramePacket(leds));
  }

  /// Sets keyboard brightness (device range 0–9).
  bool setBrightness(int brightness) {
    if (!open()) return false;
    return _setFeature(spectrumBrightnessPacket(brightness));
  }

  /// Releases the keyboard back to its onboard controller.
  bool restoreHardwareMode() {
    if (!open()) return false;
    final off = spectrumDirectModePacket(
      enable: false,
      profile: _activeProfile(),
    );
    final ok = _setFeature(off);
    _directEnabled = false;
    return ok;
  }

  int _activeProfile() {
    final response = _getFeature(spectrumGetActiveProfilePacket());
    return (response != null && response.length > 4) ? response[4] : 1;
  }

  bool _setFeature(Uint8List packet) {
    if (_fd < 0) return false;
    final pointer = malloc<Uint8>(packet.length);
    try {
      pointer.asTypedList(packet.length).setAll(0, packet);
      return _ioctl(_fd, hidiocSetFeature(packet.length), pointer) >= 0;
    } finally {
      malloc.free(pointer);
    }
  }

  Uint8List? _getFeature(Uint8List request) {
    if (_fd < 0) return null;
    final pointer = malloc<Uint8>(request.length);
    try {
      pointer.asTypedList(request.length).setAll(0, request);
      if (_ioctl(_fd, hidiocGetFeature(request.length), pointer) < 0) {
        return null;
      }
      return Uint8List.fromList(pointer.asTypedList(request.length));
    } finally {
      malloc.free(pointer);
    }
  }
}
