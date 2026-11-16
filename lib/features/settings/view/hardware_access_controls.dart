import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../../../core/providers/system_services_provider.dart';

class HardwareAccessControls extends ConsumerWidget {
  const HardwareAccessControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final available = ref.watch(portableControlAvailableProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Permission to change settings',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Text(
          available
              ? 'A temporary helper requests administrator approval when you first change a hardware setting. Reading settings does not need approval.'
              : 'The temporary helper is missing from the app files. Hardware readings remain available. Reinstall a complete app build to change hardware settings.',
        ),
        const SizedBox(height: 8),
        const Text(
          'The helper stops when you close the app or after 15 minutes without a request. Stopping it does not undo changes already made. '
          'It cannot manage background services or graphics changes scheduled for the next boot.',
        ),
        const SizedBox(height: 12),
        YaruExpandable(
          isExpanded: false,
          expandIconSemanticLabel: 'Toggle other hardware permissions',
          expandButtonPosition: YaruExpandableButtonPosition.end,
          header: const Text('Other hardware permissions'),
          child: const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Keyboard lighting and CPU power readings need separate device permissions or services. Helper approval does not grant that access.',
            ),
          ),
        ),
      ],
    );
  }
}
