import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/system_services_provider.dart';
import '../../core/widgets/app_shell_components.dart';
import '../../core/widgets/privileged_action_notice.dart';

class PackagePowerPrompt extends ConsumerStatefulWidget {
  const PackagePowerPrompt({required this.child, super.key});
  final Widget child;

  @override
  ConsumerState<PackagePowerPrompt> createState() => _PackagePowerPromptState();
}

class _PackagePowerPromptState extends ConsumerState<PackagePowerPrompt> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestPermission());
  }

  Future<void> _requestPermission() async {
    if (!mounted) return;
    final approved = await confirmPrivilegedAction(
      context,
      title: 'Show CPU power usage?',
      message: 'The app needs permission to read your CPU’s energy counter and show its power use in watts.',
      confirmLabel: 'Allow',
      cancelLabel: 'Skip',
    );
    if (!approved || !mounted) return;
    try {
      await ref.read(packagePowerTelemetryClientProvider).enable();
    } catch (error) {
      if (mounted) {
        await showAppErrorDialog(
          context,
          'CPU power is unavailable this session.\n\n$error',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
