import 'package:flutter/material.dart';

import '../../../core/widgets/metric_format.dart';
import '../../../core/widgets/surface_card.dart';
import '../models/device_identity_snapshot.dart';

/// The product-information header: device name + product/BIOS/CPU meta on the
/// left, with kernel / legion-module / uptime stat columns on the right.
class DeviceIdentityCard extends StatelessWidget {
  const DeviceIdentityCard({
    super.key,
    required this.identity,
    required this.accent,
  });

  final DeviceIdentitySnapshot identity;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final meta = <String>[
      if (identity.productName != null) 'Product ${identity.productName}',
      if (identity.biosVersion != null) 'BIOS ${identity.biosVersion}',
      if (identity.cpuName != null) _shortCpu(identity.cpuName!),
    ].join('  ·  ');

    final stats = <(String, String)>[
      if (identity.kernelRelease != null)
        (identity.kernelRelease!.split('-').first, 'Kernel'),
      (identity.legionModuleVersion ?? '—', 'legion module'),
      if (identity.uptimeLabel != null) (identity.uptimeLabel!, 'Uptime'),
    ];

    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.memory_outlined, color: accent, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  identity.displayName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: kMonoFontFamily,
                      package: kMonoFontPackage,
                      fontSize: 12,
                      color: scheme.onSurface.withValues(alpha: 0.56),
                    ),
                  ),
                ],
              ],
            ),
          ),
          for (final stat in stats) ...[
            const SizedBox(width: 24),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  stat.$1,
                  style: const TextStyle(
                    fontFamily: kMonoFontFamily,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  stat.$2,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Trims a /proc/cpuinfo model name to the marketing name, e.g.
  /// "AMD Ryzen 7 7840HS w/ Radeon 780M Graphics" -> "Ryzen 7 7840HS".
  String _shortCpu(String name) => name
      .replaceAll(RegExp(r'\((R|TM)\)'), '')
      .replaceFirst('AMD ', '')
      .replaceFirst('Intel ', '')
      .split(' w/')
      .first
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
