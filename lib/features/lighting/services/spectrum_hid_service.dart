import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/spectrum_keyboard_profile.dart';
import '../models/spectrum_hid_discovery.dart';
import 'spectrum_hid_io.dart';
import 'spectrum_protocol.dart';

const int _oRdwr = 2;

/// Drives the Legion Spectrum keyboard (Gen 7/8) over `/dev/hidraw*` via libc
/// `ioctl(HIDIOCSFEATURE/HIDIOCGFEATURE)` — no libhidapi. Real-time: a full
/// per-key frame is one direct-mode enable + one frame write.
///
/// Frame bytes come from `spectrum_protocol.dart`. Discovery reads Linux's
/// hidraw device files; tests supply directories containing sample uevents.
class SpectrumHidService {
  SpectrumHidService({
    this.vendorId = kSpectrumVendorId,
    this.productId = kSpectrumC987ProductId,
    this.sysfsHidrawRoot = '/sys/class/hidraw',
    this.devRoot = '/dev',
    SpectrumHidIo? io,
  }) : _io = io ?? NativeSpectrumHidIo.instance;

  final int vendorId;
  final int productId;
  final String sysfsHidrawRoot;
  final String devRoot;
  final SpectrumHidIo _io;

  SpectrumKeyboardProfile? get keyboardProfile =>
      spectrumKeyboardProfile(vendorId, productId);

  int _fd = -1;
  bool _directEnabled = false;

  bool get isOpen => _fd >= 0;

  /// The `/dev/hidraw*` node whose HID_ID matches [vendorId]:[productId], or
  /// null when the keyboard isn't present.
  String? findHidrawPath() {
    return inspectHidraw().selectedHidrawPath;
  }

  /// Reads HID identity and uevent files without opening a hidraw device.
  SpectrumHidDiscovery inspectHidraw() {
    final profile = keyboardProfile;
    final dir = Directory(sysfsHidrawRoot);
    List<FileSystemEntity> entries;
    try {
      entries = dir.listSync()..sort((a, b) => a.path.compareTo(b.path));
    } on FileSystemException catch (error) {
      return SpectrumHidDiscovery(
        outcome: switch (error.osError?.errorCode) {
          2 => SpectrumHidDiscoveryOutcome.rootMissing,
          1 || 13 || 20 => SpectrumHidDiscoveryOutcome.rootUnreadable,
          _ => SpectrumHidDiscoveryOutcome.unknown,
        },
      );
    } on Object {
      return const SpectrumHidDiscovery(
        outcome: SpectrumHidDiscoveryOutcome.unknown,
      );
    }
    final attempts = <SpectrumHidAttempt>[];
    var sawUnreadable = false;
    var sawUnknown = false;
    var sawMalformed = false;
    var sawMalformedUtf8 = false;
    for (final entry in entries) {
      final name = entry.path.split('/').last;
      if (!RegExp(r'^hidraw[0-9]+$').hasMatch(name)) continue;
      try {
        final uevent = utf8.decode(
          File('${entry.path}/device/uevent').readAsBytesSync(),
        );
        final identity = spectrumHidIdentityFromUevent(uevent);
        if (identity == null) {
          attempts.add(
            SpectrumHidAttempt(
              hidrawName: name,
              outcome: SpectrumHidDiscoveryOutcome.malformed,
            ),
          );
          sawMalformed = true;
          continue;
        }
        final found = spectrumKeyboardProfile(
          identity.vendorId,
          identity.productId,
        );
        if (found == null) {
          attempts.add(
            SpectrumHidAttempt(
              hidrawName: name,
              outcome: SpectrumHidDiscoveryOutcome.unsupported,
              vendorId: identity.vendorId,
              productId: identity.productId,
            ),
          );
          continue;
        }
        if (found.protocol == SpectrumProtocol.gen7And8 && found == profile) {
          return SpectrumHidDiscovery(
            outcome: SpectrumHidDiscoveryOutcome.supported,
            vendorId: identity.vendorId,
            productId: identity.productId,
            selectedHidrawPath: '$devRoot/$name',
            profile: found,
            attempts: [
              ...attempts,
              SpectrumHidAttempt(
                hidrawName: name,
                outcome: SpectrumHidDiscoveryOutcome.supported,
                vendorId: identity.vendorId,
                productId: identity.productId,
              ),
            ],
          );
        }
        attempts.add(
          SpectrumHidAttempt(
            hidrawName: name,
            outcome: SpectrumHidDiscoveryOutcome.supported,
            vendorId: identity.vendorId,
            productId: identity.productId,
          ),
        );
      } on FormatException {
        attempts.add(
          SpectrumHidAttempt(
            hidrawName: name,
            outcome: SpectrumHidDiscoveryOutcome.malformedUtf8,
          ),
        );
        sawMalformedUtf8 = true;
      } on FileSystemException {
        attempts.add(
          SpectrumHidAttempt(
            hidrawName: name,
            outcome: SpectrumHidDiscoveryOutcome.unreadable,
          ),
        );
        sawUnreadable = true;
      } on Object {
        attempts.add(
          SpectrumHidAttempt(
            hidrawName: name,
            outcome: SpectrumHidDiscoveryOutcome.unknown,
          ),
        );
        sawUnknown = true;
      }
    }
    if (profile == null) {
      return SpectrumHidDiscovery(
        outcome: SpectrumHidDiscoveryOutcome.unsupported,
        vendorId: vendorId,
        productId: productId,
        attempts: attempts,
      );
    }
    if (sawUnknown) {
      return SpectrumHidDiscovery(
        outcome: SpectrumHidDiscoveryOutcome.unknown,
        attempts: List.unmodifiable(attempts),
      );
    }
    if (sawUnreadable) {
      return SpectrumHidDiscovery(
        outcome: SpectrumHidDiscoveryOutcome.unreadable,
        attempts: attempts,
      );
    }
    if (sawMalformedUtf8) {
      return SpectrumHidDiscovery(
        outcome: SpectrumHidDiscoveryOutcome.malformedUtf8,
        attempts: attempts,
      );
    }
    if (sawMalformed) {
      return SpectrumHidDiscovery(
        outcome: SpectrumHidDiscoveryOutcome.malformed,
        attempts: attempts,
      );
    }
    return SpectrumHidDiscovery(
      outcome: SpectrumHidDiscoveryOutcome.missing,
      attempts: attempts,
    );
  }

  /// Opens the keyboard's hidraw node. False when absent or permission-denied.
  bool open() {
    final profile = keyboardProfile;
    if (profile == null || profile.protocol != SpectrumProtocol.gen7And8) {
      return false;
    }
    if (_fd >= 0) return true;
    final path = findHidrawPath();
    if (path == null) return false;
    _fd = _io.open(path, _oRdwr);
    _directEnabled = false;
    return _fd >= 0;
  }

  void close() {
    if (_fd >= 0) {
      _io.close(_fd);
      _fd = -1;
      _directEnabled = false;
    }
  }

  /// Pushes a full per-key frame ([leds] carry hardware uint16 LED values),
  /// enabling direct mode on the active profile first. True if all writes ok.
  bool sendDirectFrame(List<SpectrumLed> leds) {
    if (!open()) return false;
    if (!_directEnabled) {
      final profile = _activeProfile();
      final on = spectrumDirectModePacket(enable: true, profile: profile);
      if (!_setFeature(on)) return false;
      final directProfile = spectrumDirectProfilePacket(
        profile: profile,
        leds: leds,
      );
      if (!_setFeature(directProfile)) return false;
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
    final request = spectrumGetActiveProfilePacket();
    if (!_setFeature(request)) return 1;
    final response = _getFeature(request);
    return (response != null && response.length > 4) ? response[4] : 1;
  }

  bool _setFeature(Uint8List packet) {
    if (_fd < 0) return false;
    return _io.ioctl(_fd, hidiocSetFeature(packet.length), packet) >= 0;
  }

  Uint8List? _getFeature(Uint8List request) {
    if (_fd < 0) return null;
    final response = Uint8List.fromList(request);
    if (_io.ioctl(_fd, hidiocGetFeature(response.length), response) < 0) {
      return null;
    }
    return response;
  }
}
