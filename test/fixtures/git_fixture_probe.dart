// Runs under an inherited hook environment; all repositories are disposable.
import 'dart:io';

import '../../tool/check_commits.dart';
import '../../tool/release_source/source_files.dart';
import '../../tool/release_source/source_inputs.dart';
import '../../tool/release_workflow.dart';
import '../support/git_fixture.dart';

Future<void> main(List<String> arguments) async {
  final workspace = Directory(arguments.single);
  final root = Directory('${workspace.path}/fixture');
  final repository = GitFixture(root);
  try {
    repository.initialize();
    File('${root.path}/README.md').writeAsStringSync('fixture source\n');
    File('${root.path}/pubspec.lock').writeAsStringSync('lock\n');
    File('${root.path}/.gitignore').writeAsStringSync('.dart_tool/\n');
    Directory('${root.path}/.dart_tool').createSync();
    File('${root.path}/.dart_tool/package_config.json')
        .writeAsStringSync('{"packages":[{"name":"app","rootUri":"../"}]}');
    File('${root.path}/.dart_tool/package_graph.json').writeAsStringSync(
      '{"roots":["app"],"packages":[{"name":"app","version":"1.0.0","dependencies":[]}]}',
    );
    repository.git(['add', '.']);
    repository.git(['commit', '-qm', 'Existing fixture history']);
    final base = repository.git(['rev-parse', 'HEAD']);
    repository.git(['checkout', '-qb', 'feature']);
    repository.git(['commit', '--allow-empty', '-qm', 'fix: fixture change']);
    repository.git(['checkout', 'main']);
    repository.git(['merge', '--no-ff', 'feature', '-m', 'Merge fixture']);
    repository.git(['tag', '-a', 'v1.0.0', '-m', 'Fixture tag']);
    final head = repository.git(['rev-parse', 'HEAD']);
    if (invalidCommitSubjects(root, base, head).isNotEmpty ||
        releaseGit(root, ['rev-parse', 'HEAD']) != head ||
        (await captureReleaseInputs(root)).commit != head) {
      throw StateError('A tool read the inherited repository instead.');
    }
    final destination = Directory('${workspace.path}/extracted');
    await extractApplicationSource(root, destination, head);
    if (File('${destination.path}/README.md').readAsStringSync() !=
        'fixture source\n') {
      throw StateError('The archive came from the inherited repository.');
    }
    if (repository.git(['log', '-1', '--format=%an']) != 'Fixture test') {
      throw StateError('The fixture inherited the author identity.');
    }
  } finally {
    repository.dispose();
  }
}
