import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:legion_frontend/features/boot_logo/models/boot_logo_snapshot.dart';
import 'package:legion_frontend/features/boot_logo/models/boot_logo_status.dart';
import 'package:legion_frontend/features/boot_logo/providers/boot_logo_provider.dart';
import 'package:legion_frontend/features/boot_logo/repository/boot_logo_repository.dart';
import 'package:legion_frontend/features/boot_logo/view/boot_logo_page.dart';
import 'package:mocktail/mocktail.dart';

class MockBootLogoRepository extends Mock implements BootLogoRepository {}

final class MockPlatformFile extends PlatformFile {
  @override
  Uri get uri => Uri.file('/tmp/logo.png');
  @override
  String get name => 'logo.png';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ControlledPicker extends FilePickerPlatform {
  final result = Completer<List<PlatformFile>>();
  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) => result.future;
}

void main() {
  testWidgets('picker result reaches replacement provider', (tester) async {
    final originalPicker = FilePickerPlatform.instance;
    final picker = ControlledPicker();
    FilePickerPlatform.instance = picker;
    addTearDown(() => FilePickerPlatform.instance = originalPicker);
    final first = MockBootLogoRepository();
    final replacement = MockBootLogoRepository();
    const snapshot = BootLogoSnapshot(
      status: BootLogoStatus(
        isCustomEnabled: true,
        requiredWidth: 0,
        requiredHeight: 0,
      ),
    );
    for (final repo in [first, replacement]) {
      when(repo.loadSnapshot).thenAnswer((_) async => snapshot);
    }
    final container = ProviderContainer.test(
      overrides: [bootLogoRepositoryProvider.overrideWithValue(first)],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: BootLogoPage())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Browse...'));
    await tester.pump();
    final old = container.read(bootLogoBlocProvider.bloc);
    container.updateOverrides([
      bootLogoRepositoryProvider.overrideWithValue(replacement),
    ]);
    await tester.pumpAndSettle();
    expect(old.isClosed, isTrue);
    final file = MockPlatformFile();
    picker.result.complete([file]);
    await tester.pumpAndSettle();
    expect(
      container.read(bootLogoBlocProvider).selectedImagePath,
      '/tmp/logo.png',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('confirmation after page disposal does not restore', (
    tester,
  ) async {
    final repo = MockBootLogoRepository();
    const snapshot = BootLogoSnapshot(
      status: BootLogoStatus(
        isCustomEnabled: true,
        requiredWidth: 0,
        requiredHeight: 0,
      ),
    );
    when(repo.loadSnapshot).thenAnswer((_) async => snapshot);
    when(repo.restoreBootLogo).thenAnswer((_) async {});
    final visible = ValueNotifier(true);
    addTearDown(visible.dispose);
    final container = ProviderContainer.test(
      overrides: [bootLogoRepositoryProvider.overrideWithValue(repo)],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: visible,
              builder: (_, show, _) =>
                  show ? const BootLogoPage() : const SizedBox(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore Default'));
    await tester.pumpAndSettle();
    visible.value = false;
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore').last);
    await tester.pumpAndSettle();
    verifyNever(repo.restoreBootLogo);
    expect(tester.takeException(), isNull);
  });

  testWidgets('restore confirmation targets replacement provider', (
    tester,
  ) async {
    final first = MockBootLogoRepository();
    final replacement = MockBootLogoRepository();
    const snapshot = BootLogoSnapshot(
      status: BootLogoStatus(
        isCustomEnabled: true,
        requiredWidth: 0,
        requiredHeight: 0,
      ),
    );
    for (final repository in [first, replacement]) {
      when(repository.loadSnapshot).thenAnswer((_) async => snapshot);
      when(repository.restoreBootLogo).thenAnswer((_) async {});
    }
    final container = ProviderContainer.test(
      overrides: [bootLogoRepositoryProvider.overrideWithValue(first)],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: BootLogoPage())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore Default'));
    await tester.pumpAndSettle();
    final oldBloc = container.read(bootLogoBlocProvider.bloc);
    container.updateOverrides([
      bootLogoRepositoryProvider.overrideWithValue(replacement),
    ]);
    await tester.pumpAndSettle();
    expect(oldBloc.isClosed, isTrue);
    await tester.tap(find.text('Restore').last);
    await tester.pumpAndSettle();
    verifyNever(first.restoreBootLogo);
    verify(replacement.restoreBootLogo).called(1);
    expect(tester.takeException(), isNull);
  });
}
