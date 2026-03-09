import 'package:flutter/material.dart';
import 'package:yaru/yaru.dart';
import '../models/device_identity_snapshot.dart';

class DeviceIdentityCard extends StatelessWidget {
  const DeviceIdentityCard({super.key, required this.identity});

  final DeviceIdentitySnapshot identity;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    final metaItems = [
      if (identity.serial != null) 'Serial: ${identity.serial}',
      if (identity.productName != null) 'Product: ${identity.productName}',
      if (identity.biosVersion != null) 'BIOS: ${identity.biosVersion}',
    ].join('  ·  ');

    return YaruSection(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(identity.displayName, style: textTheme.headlineSmall),
            if (metaItems.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                metaItems,
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
