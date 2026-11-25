// Configure the real frontend targets without building Flutter or host libraries.
@Tags(['tooling'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/packaging_files.dart';

void main() {
  final project = Directory.current;
  for (final oldCache in [false, true]) {
    test('frontend bundles only its helper with old cache: $oldCache', () {
      final root = Directory.systemTemp.createTempSync('helper-build-');
      addTearDown(() => root.deleteSync(recursive: true));
      final linux = Directory('${root.path}/linux');
      final flutter = Directory('${linux.path}/flutter')
        ..createSync(recursive: true);
      final runner = Directory('${linux.path}/runner')..createSync();
      final modules = Directory('${root.path}/modules')..createSync();
      for (final name in ['CMakeLists.txt', 'helper_install.cmake.in']) {
        File('${project.path}/linux/$name').copySync('${linux.path}/$name');
      }
      for (final name in ['control', 'packaging']) {
        Link('${root.path}/$name').createSync('${project.path}/$name');
      }
      // Stub only external dependencies; use real native target/install rules.
      File('${flutter.path}/CMakeLists.txt').writeAsStringSync(r'''
add_custom_target(flutter_assemble)
set(FLUTTER_ROOT "/unused-sdk")
set(FLUTTER_ICU_DATA_FILE "${CMAKE_CURRENT_LIST_FILE}" PARENT_SCOPE)
set(FLUTTER_LIBRARY "${CMAKE_CURRENT_LIST_FILE}" PARENT_SCOPE)
''');
      File('${flutter.path}/generated_plugins.cmake').writeAsStringSync('');
      File('${runner.path}/runner.cc')
          .writeAsStringSync('int main() { return 0; }\n');
      File('${runner.path}/CMakeLists.txt').writeAsStringSync(
        r'add_executable(${BINARY_NAME} runner.cc)'
        '\n',
      );
      File('${modules.path}/FindPkgConfig.cmake').writeAsStringSync(r'''
set(PkgConfig_FOUND TRUE)
function(pkg_check_modules prefix)
  add_library(PkgConfig::${prefix} INTERFACE IMPORTED GLOBAL)
endfunction()
''');
      final build = Directory('${root.path}/build');
      packagingCommand('cmake', [
        '-S',
        linux.path,
        '-B',
        build.path,
        '-DCMAKE_MODULE_PATH=${modules.path}',
        if (oldCache) ...[
          '-DBUILD_CONTROL_HELPER=OFF',
          '-DBUILD_LEGION_CONTROL_SERVICE=ON',
        ],
      ]);
      final targets = packagingCommand('cmake', [
        '--build',
        build.path,
        '--target',
        'help',
      ]);
      expect(targets, contains('legion_control_helper'));
      expect(targets, isNot(contains('legion_control_service')));
      final install = File('${build.path}/cmake_install.cmake')
          .readAsStringSync();
      expect(install, contains('/libexec/legion-control-helper'));
      expect(install, isNot(contains('legion-control.service')));
    });
  }
}
