import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legion_frontend/features/lighting/bloc/lighting_bloc.dart';
import 'package:legion_frontend/features/lighting/bloc/lighting_state.dart';
import 'package:legion_frontend/features/lighting/repository/lighting_repository.dart';
import 'package:legion_frontend/features/lighting/view/lighting_page.dart';
import 'package:mocktail/mocktail.dart';
import 'package:yaru/yaru.dart';

class MockLightingPageRepository extends Mock implements LightingRepository {}

void main() {
  for (final backlightEnabled in [true, false]) {
    testWidgets(
      'Lighting shows readable keyboard backlight ${backlightEnabled ? 'on' : 'off'} read-only',
      (tester) async {
        final repository = MockLightingPageRepository();
        final bloc = LightingBloc(repository: repository);
        addTearDown(bloc.close);
        final state = LightingState.initial().copyWith(
          whiteKeyboardBacklightEnabled: backlightEnabled,
          whiteKeyboardBacklightSupported: true,
          whiteKeyboardBacklightWriteSupported: false,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: BacklightSection(state: state, bloc: bloc),
            ),
          ),
        );

        expect(find.text('Keyboard backlight'), findsOneWidget);
        expect(
          find.text('${backlightEnabled ? 'On' : 'Off'} (read-only)'),
          findsOneWidget,
        );
        expect(find.byType(YaruSwitch), findsOneWidget);
        expect(
          tester.widget<YaruSwitch>(find.byType(YaruSwitch)).onChanged,
          isNull,
        );
        verifyNever(() => repository.setWhiteKeyboardBacklight(any()));
      },
    );
  }

  testWidgets('Lighting hides an absent keyboard backlight', (tester) async {
    final repository = MockLightingPageRepository();
    final bloc = LightingBloc(repository: repository);
    addTearDown(bloc.close);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BacklightSection(state: LightingState.initial(), bloc: bloc),
        ),
      ),
    );

    expect(find.text('Keyboard backlight'), findsNothing);
    expect(find.text('Backlight'), findsNothing);
  });
}
