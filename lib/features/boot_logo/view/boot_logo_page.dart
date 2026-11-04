import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../../../core/widgets/app_shell_components.dart';
import '../bloc/boot_logo_event.dart';
import '../providers/boot_logo_provider.dart';
import 'boot_logo_controls.dart';

class BootLogoPage extends ConsumerWidget {
  const BootLogoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(bootLogoBlocProvider);

    return Visibility(
      visible: !state.isLoading || state.status != null,
      // A replacement provider can load while a picker or confirmation is open.
      maintainState: true,
      replacement: const Center(child: YaruCircularProgressIndicator()),
      child: AppPageBody(
        title: 'Boot Logo',
        errorMessage: state.errorMessage,
        children: [
          const AppSectionCard(
            title: 'Boot Logo',
            description:
                'Set a custom logo shown during boot, or restore the stock Lenovo logo.',
            children: [BootLogoControls()],
          ),
          const SizedBox(height: 16),
          AppRefreshButton(
            isBusy: state.isLoading,
            onPressed: state.isApplying
                ? null
                : () => ref
                      .read(bootLogoBlocProvider.bloc)
                      .add(const BootLogoRefreshRequested()),
          ),
        ],
      ),
    );
  }
}
