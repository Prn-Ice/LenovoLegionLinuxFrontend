import 'dart:convert';
import 'dart:io';

enum BuildCheckStatus { pass, fail, evidence }

class BuildCheckResult {
  const BuildCheckResult(this.name, this.status, this.detail);

  final String name;
  final BuildCheckStatus status;
  final String detail;

  Map<String, String> toJson() => {
    'name': name,
    'status': status.name,
    'detail': detail,
  };
}

String combineCommandOutput(ProcessResult result) {
  final stdoutText = result.stdout.toString().trim();
  final stderrText = result.stderr.toString().trim();
  if (stdoutText.isEmpty) {
    return stderrText;
  }
  if (stderrText.isEmpty) {
    return stdoutText;
  }
  return '$stdoutText\n$stderrText';
}

Future<BuildCheckResult> checkExecutableFormat(String executable) async {
  final result = await Process.run(
    'readelf',
    ['-hW', executable],
    environment: {'LC_ALL': 'C'},
  );
  if (result.exitCode != 0) {
    return BuildCheckResult(
      '64-bit x86 Linux executable (ELF)',
      BuildCheckStatus.fail,
      'readelf failed: ${combineCommandOutput(result)}',
    );
  }
  final output = combineCommandOutput(result);
  final isElf =
      RegExp(r'Class:\s+ELF64').hasMatch(output) &&
      output.contains('Type:') &&
      RegExp(r'Machine:\s+Advanced Micro Devices X86-64').hasMatch(output);
  return BuildCheckResult(
    '64-bit x86 Linux executable (ELF)',
    isElf ? BuildCheckStatus.pass : BuildCheckStatus.fail,
    output,
  );
}

Future<BuildCheckResult> checkProgramLoader(String executable) async {
  final result = await Process.run(
    'readelf',
    ['-lW', executable],
    environment: {'LC_ALL': 'C'},
  );
  if (result.exitCode != 0) {
    return BuildCheckResult(
      'External program loader',
      BuildCheckStatus.fail,
      'readelf failed: ${combineCommandOutput(result)}',
    );
  }
  final output = combineCommandOutput(result);
  final hasProgramLoader = output
      .split('\n')
      .any((line) => RegExp(r'^\s*INTERP(?:\s|$)').hasMatch(line));
  final line = output
      .split('\n')
      .firstWhere(
        (line) => line.contains('Requesting program interpreter'),
        orElse: () => hasProgramLoader
            ? 'PT_INTERP segment present'
            : 'No PT_INTERP segment',
      );
  // PT_INTERP names an external program loader.
  // The AppImage helper must not need one.
  return BuildCheckResult(
    'No external program loader',
    hasProgramLoader ? BuildCheckStatus.fail : BuildCheckStatus.pass,
    line,
  );
}

BuildCheckResult checkRequiredLibraries(ProcessResult result) {
  if (result.exitCode != 0) {
    return BuildCheckResult(
      'Required system libraries',
      BuildCheckStatus.fail,
      'readelf failed: ${combineCommandOutput(result)}',
    );
  }
  final requiredLibraries = combineCommandOutput(result)
      .split('\n')
      .where((line) => line.contains('(NEEDED)'))
      .toList();
  // NEEDED lists separate libraries.
  // The AppImage helper must include its libraries.
  return BuildCheckResult(
    'No separate system libraries required',
    requiredLibraries.isEmpty ? BuildCheckStatus.pass : BuildCheckStatus.fail,
    requiredLibraries.isEmpty
        ? 'No DT_NEEDED entries'
        : requiredLibraries.join('\n'),
  );
}

BuildCheckResult checkLibrarySearchPaths(ProcessResult result) {
  if (result.exitCode != 0) {
    return BuildCheckResult(
      'No embedded library search path',
      BuildCheckStatus.fail,
      'readelf failed: ${combineCommandOutput(result)}',
    );
  }
  final paths = combineCommandOutput(result)
      .split('\n')
      .where((line) => line.contains('(RPATH)') || line.contains('(RUNPATH)'))
      .toList();
  return BuildCheckResult(
    'No embedded library search path',
    paths.isEmpty ? BuildCheckStatus.pass : BuildCheckStatus.fail,
    paths.isEmpty ? 'No DT_RPATH or DT_RUNPATH entries' : paths.join('\n'),
  );
}

Future<void> main() async {
  final executable = File(Platform.resolvedExecutable).absolute.path;
  final stat = await File(executable).stat();
  final dynamicSection = await Process.run(
    'readelf',
    ['-dW', executable],
    environment: {'LC_ALL': 'C'},
  );
  final results = <BuildCheckResult>[
    await checkExecutableFormat(executable),
    await checkProgramLoader(executable),
    checkRequiredLibraries(dynamicSection),
    checkLibrarySearchPaths(dynamicSection),
    const BuildCheckResult(
      'Dart installation requirement',
      BuildCheckStatus.evidence,
      'dart compile exe includes the Dart runtime. The program can still need system libraries.',
    ),
    const BuildCheckResult(
      'Helper startup checks',
      BuildCheckStatus.evidence,
      'This tool inspects the compiled file. It does not start the helper or test administrator approval, messaging, process tracking, or cleanup.',
    ),
  ];
  final report = <String, Object>{
    'executable': executable,
    'bytes': stat.size,
    'dartVersion': Platform.version,
    'results': results.map((result) => result.toJson()).toList(),
  };
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
  if (results.any((result) => result.status == BuildCheckStatus.fail)) {
    exitCode = 1;
  }
}
