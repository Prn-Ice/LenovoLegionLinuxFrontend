import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../../../core/widgets/app_shell_components.dart';
import '../../../core/widgets/privileged_action_notice.dart';
import '../bloc/display_bloc.dart';
import '../bloc/display_event.dart';
import '../providers/display_provider.dart';

class DisplayPage extends ConsumerWidget {
  const DisplayPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(displayBlocProvider);
    final bloc = ref.read(displayBlocProvider.bloc);

    if (state.isLoading && !state.hasLoaded) {
      return const Center(child: YaruCircularProgressIndicator());
    }

    return AppPageBody(
      title: 'Display',
      errorMessage: state.errorMessage,
      noticeMessage: state.noticeMessage,
      children: [
        AppControlCard(
          icon: YaruIcons.monitor,
          title: 'Overdrive',
          description: 'Reduces display response time',
          children: [
            AppSwitchTile(
              value: state.overdriveEnabled ?? false,
              onChanged: (state.overdriveSupported && !state.isApplying)
                  ? (enabled) async {
                      final confirmed = await confirmPrivilegedAction(
                        context,
                        title: 'Toggle overdrive',
                        message:
                            'Changing overdrive uses privileged access and may prompt for authentication.',
                        confirmLabel: 'Apply',
                      );
                      if (!context.mounted || !confirmed) {
                        return;
                      }
                      _setOverdriveMode(bloc, enabled);
                    }
                  : null,
              title: 'Overdrive',
              subtitle: state.overdriveSupported
                  ? boolEnabledLabel(state.overdriveEnabled)
                  : 'Not supported on this device',
            ),
          ],
        ),
        const SizedBox(height: 16),
        AppControlCard(
          icon: YaruIcons.refresh,
          title: 'Refresh Rate',
          children: [
            if (state.availableRefreshRates == null ||
                state.availableRefreshRates!.isEmpty)
              const ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Refresh rate switching'),
                subtitle: Text(
                  'Unavailable — xrandr not accessible on this session.',
                ),
              )
            else
              YaruChoiceChipBar(
                labels: state.availableRefreshRates!
                    .map((r) => Text('${r.round()} Hz'))
                    .toList(growable: false),
                isSelected: state.availableRefreshRates!
                    .map((r) => r == state.currentRefreshRate)
                    .toList(growable: false),
                onSelected: state.isApplying
                    ? null
                    : (i) => _setRefreshRate(
                          bloc,
                          state.availableRefreshRates![i],
                        ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        AppRefreshButton(
          isBusy: state.isLoading,
          onPressed: state.isApplying
              ? null
              : () => bloc.add(const DisplayRefreshRequested()),
        ),
      ],
    );
  }

  void _setOverdriveMode(DisplayBloc bloc, bool enabled) {
    bloc.add(OverdriveModeSetRequested(enabled));
  }

  void _setRefreshRate(DisplayBloc bloc, double rate) {
    bloc.add(RefreshRateSetRequested(rate));
  }
}
