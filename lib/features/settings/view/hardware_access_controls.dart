import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../../../core/providers/system_services_provider.dart';

class HardwareAccessControls extends ConsumerWidget {
  const HardwareAccessControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final helperExists = ref.watch(privilegedControlHelperExistsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Administrator access',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Text(
          helperExists
              ? 'You will be asked to approve hardware changes that require administrator access. Reading settings does not need approval.'
              : 'Administrator access is unavailable because the app is missing its privileged control helper. Hardware readings remain available. Reinstall a complete app build to change hardware settings.',
        ),
        const SizedBox(height: 8),
        const Text(
          'Administrator access ends when you close the app or after 15 minutes without a request. Ending access does not undo changes already made. '
          'The app cannot manage background services or graphics changes scheduled for the next boot.',
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
              'Keyboard lighting and CPU power readings need separate device permissions or services. This approval does not grant that access.',
            ),
          ),
        ),
      ],
    );
  }
}
