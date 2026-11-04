import 'package:equatable/equatable.dart';

enum KeyboardPowerMode {
  quiet('Quiet'),
  balanced('Balanced'),
  performance('Performance'),
  custom('Custom');

  const KeyboardPowerMode(this.label);
  final String label;

  static KeyboardPowerMode? fromPlatformProfile(String? value) =>
      switch (value) {
        'quiet' || 'low-power' || 'power-saver' => quiet,
        'balanced' => balanced,
        'performance' => performance,
        'custom' || 'balanced-performance' => custom,
        _ => null,
      };
}

/// Only named keyboard profiles are read. Legacy fan, charge and command rules
/// are deliberately ignored, including their old enabled flags.
class AutomationConfig extends Equatable {
  AutomationConfig({Map<KeyboardPowerMode, String> profiles = const {}})
    : profiles = Map.unmodifiable(profiles);

  factory AutomationConfig.defaults() => AutomationConfig();

  factory AutomationConfig.fromJson(Map<String, dynamic> json) {
    final raw = json['keyboardProfiles'];
    return AutomationConfig(
      profiles: {
        if (raw is Map)
          for (final mode in KeyboardPowerMode.values)
            if (raw[mode.name] case final String name
                when name.trim().isNotEmpty)
              mode: name,
      },
    );
  }

  final Map<KeyboardPowerMode, String> profiles;

  AutomationConfig assign(KeyboardPowerMode mode, String? profile) =>
      AutomationConfig(
        profiles: {
          for (final entry in profiles.entries)
            if (entry.key != mode) entry.key: entry.value,
          if (profile != null && profile.trim().isNotEmpty) mode: profile,
        },
      );

  Map<String, dynamic> toJson() => {
    'version': 2,
    'keyboardProfiles': {
      for (final entry in profiles.entries) entry.key.name: entry.value,
    },
  };

  @override
  List<Object?> get props => [profiles];
}
