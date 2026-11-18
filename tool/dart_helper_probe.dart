import 'dart:convert';
import 'dart:io';

enum RequirementStatus { pass, fail, evidence }

class RequirementResult {
  const RequirementResult(this.name, this.status, this.detail);

  final String name;
  final RequirementStatus status;
  final String detail;

  Map<String, String> toJson() => {
    'name': name,
    'status': status.name,
    'detail': detail,
  };
}

String outputOf(ProcessResult result) {
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

Future<RequirementResult> inspectElfHeader(String executable) async {
  final result = await Process.run(
    'readelf',
    ['-hW', executable],
    environment: {'LC_ALL': 'C'},
  );
  if (result.exitCode != 0) {
    return RequirementResult(
      'ELF header',
      RequirementStatus.fail,
      'readelf failed: ${outputOf(result)}',
    );
  }
  final output = outputOf(result);
  final isElf =
      RegExp(r'Class:\s+ELF64').hasMatch(output) &&
      output.contains('Type:') &&
      RegExp(r'Machine:\s+Advanced Micro Devices X86-64').hasMatch(output);
  return RequirementResult(
    'ELF header',
    isElf ? RequirementStatus.pass : RequirementStatus.fail,
    output,
  );
}

Future<RequirementResult> inspectInterpreter(String executable) async {
  final result = await Process.run(
    'readelf',
    ['-lW', executable],
    environment: {'LC_ALL': 'C'},
  );
  if (result.exitCode != 0) {
    return RequirementResult(
      'ELF interpreter',
      RequirementStatus.fail,
      'readelf failed: ${outputOf(result)}',
    );
  }
  final output = outputOf(result);
  final hasInterpreter = output
      .split('\n')
      .any((line) => RegExp(r'^\s*INTERP(?:\s|$)').hasMatch(line));
  final line = output
      .split('\n')
      .firstWhere(
        (line) => line.contains('Requesting program interpreter'),
        orElse: () => hasInterpreter
            ? 'PT_INTERP segment present'
            : 'No PT_INTERP segment',
      );
  // The current AppImage helper contract requires no PT_INTERP segment.
  return RequirementResult(
    'No ELF interpreter',
    hasInterpreter ? RequirementStatus.fail : RequirementStatus.pass,
    line,
  );
}

RequirementResult inspectDynamicLibraries(ProcessResult result) {
  if (result.exitCode != 0) {
    return RequirementResult(
      'ELF shared-library dependencies',
      RequirementStatus.fail,
      'readelf failed: ${outputOf(result)}',
    );
  }
  final needed = outputOf(result)
      .split('\n')
      .where((line) => line.contains('(NEEDED)'))
      .toList();
  // The current AppImage helper is static and must have no NEEDED entries.
  return RequirementResult(
    'No ELF shared-library dependencies',
    needed.isEmpty ? RequirementStatus.pass : RequirementStatus.fail,
    needed.isEmpty ? 'No DT_NEEDED entries' : needed.join('\n'),
  );
}

RequirementResult inspectLoaderSearchPath(ProcessResult result) {
  if (result.exitCode != 0) {
    return RequirementResult(
      'No ELF library search path',
      RequirementStatus.fail,
      'readelf failed: ${outputOf(result)}',
    );
  }
  final paths = outputOf(result)
      .split('\n')
      .where((line) => line.contains('(RPATH)') || line.contains('(RUNPATH)'))
      .toList();
  return RequirementResult(
    'No ELF library search path',
    paths.isEmpty ? RequirementStatus.pass : RequirementStatus.fail,
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
  final results = <RequirementResult>[
    await inspectElfHeader(executable),
    await inspectInterpreter(executable),
    inspectDynamicLibraries(dynamicSection),
    inspectLoaderSearchPath(dynamicSection),
    const RequirementResult(
      'Dart runtime inclusion',
      RequirementStatus.evidence,
      'dart compile exe embeds the Dart runtime; this probe does not establish static linkage.',
    ),
    const RequirementResult(
      'Startup contract',
      RequirementStatus.evidence,
      'This probe performs no D-Bus, systemd, Polkit, pidfd, snapshot, or helper launch operation.',
    ),
  ];
  final report = <String, Object>{
    'executable': executable,
    'bytes': stat.size,
    'dartVersion': Platform.version,
    'results': results.map((result) => result.toJson()).toList(),
  };
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
  if (results.any((result) => result.status == RequirementStatus.fail)) {
    exitCode = 1;
  }
}
