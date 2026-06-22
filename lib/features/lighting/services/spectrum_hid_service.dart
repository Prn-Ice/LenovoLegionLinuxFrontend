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

/// Drives the Legion Spectrum keyboard over `/dev/hidraw*` via libc
/// `ioctl(HIDIOCSFEATURE)` — no libhidapi dependency. Real-time: a full per-key
/// frame is ~4 ioctls (software-mode once, then 1–3 direct packets).
///
/// The frame bytes come from [spectrumDirectPackets]; this class is the thin
/// (untestable) I/O layer.
class SpectrumHidService {
  SpectrumHidService({this.vendorId = 0x048D, this.productId = 0xC987});

  final int vendorId;
  final int productId;

  static final DynamicLibrary _libc = DynamicLibrary.process();
  static final _open = _libc.lookupFunction<_OpenNative, _OpenDart>('open');
  static final _ioctl = _libc.lookupFunction<_IoctlNative, _IoctlDart>('ioctl');
  static final _close = _libc.lookupFunction<_CloseNative, _CloseDart>('close');

  int _fd = -1;
  bool _softwareMode = false;

  bool get isOpen => _fd >= 0;

  /// The `/dev/hidraw*` node whose HID_ID matches [vendorId]:[productId], or
  /// null if the keyboard isn't present.
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

  /// Opens the keyboard's hidraw node. Returns true on success (false when the
  /// device is absent or permission is denied).
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
    _softwareMode = false;
    return _fd >= 0;
  }

  void close() {
    if (_fd >= 0) {
      _close(_fd);
      _fd = -1;
      _softwareMode = false;
    }
  }

  /// Pushes a full per-key frame ([leds] carry hardware LED numbers), entering
  /// software mode first if needed. Returns true when every write succeeds.
  bool sendDirectFrame(List<SpectrumLed> leds, {int zone = 0}) {
    if (!open()) return false;
    if (!_softwareMode) {
      if (!_sendFeature(spectrumSoftwareModePacket())) return false;
      _softwareMode = true;
    }
    for (final packet in spectrumDirectPackets(leds, zone: zone)) {
      if (!_sendFeature(packet)) return false;
    }
    return true;
  }

  /// Releases the keyboard back to its onboard controller.
  bool restoreHardwareMode() {
    if (!open()) return false;
    final ok = _sendFeature(spectrumHardwareModePacket());
    _softwareMode = false;
    return ok;
  }

  bool _sendFeature(Uint8List packet) {
    if (_fd < 0) return false;
    final pointer = malloc<Uint8>(packet.length);
    try {
      pointer.asTypedList(packet.length).setAll(0, packet);
      return _ioctl(_fd, hidiocSetFeature(packet.length), pointer) >= 0;
    } finally {
      malloc.free(pointer);
    }
  }
}
