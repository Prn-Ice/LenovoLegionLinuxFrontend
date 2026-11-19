cmake_minimum_required(VERSION 3.13)
project(legion_telemetry LANGUAGES CXX)

option(BUILD_PORTABLE_CONTROL_STATIC "Link the AppImage helper without host libraries" OFF)
if(BUILD_PORTABLE_CONTROL_STATIC)
  set(CMAKE_FIND_LIBRARY_SUFFIXES .a)
  set(PKG_CONFIG_ARGN --static)
  add_compile_options(-ffunction-sections -fdata-sections)
endif()

find_package(PkgConfig REQUIRED)
pkg_check_modules(GIO REQUIRED IMPORTED_TARGET gio-2.0)
pkg_check_modules(GIO_UNIX REQUIRED IMPORTED_TARGET gio-unix-2.0)
add_library(portable_peer STATIC ../control/portable_peer.cc)
target_compile_features(portable_peer PUBLIC cxx_std_14)
target_compile_options(portable_peer PRIVATE -Wall -Wextra -Werror)
target_include_directories(portable_peer PUBLIC ../control)
target_link_libraries(portable_peer PUBLIC PkgConfig::GIO PkgConfig::GIO_UNIX)
add_library(trusted_executable STATIC ../control/trusted_executable.cc)
target_compile_features(trusted_executable PUBLIC cxx_std_14)
target_compile_options(trusted_executable PRIVATE -Wall -Wextra -Werror)
target_include_directories(trusted_executable PUBLIC ../control)
option(BUILD_LEGION_CONTROL_SERVICE "Build the privileged Legion control service" OFF)
option(BUILD_PORTABLE_CONTROL_HELPER "Build the privileged hardware control helper" OFF)
option(BUILD_PORTABLE_CONTROL_PROTOTYPE "Build the hardware-free private-peer control probe" OFF)
option(BUILD_PORTABLE_BOOTSTRAP_PROTOTYPE "Build the VM-only administrator-startup probe" OFF)
option(BUILD_BUNDLED_DART_PROTOTYPE
       "Build the VM-only bundled Dart runtime startup probe" OFF)
set(PORTABLE_CONTROL_TEST_CLI "" CACHE FILEPATH "Fixed synthetic CLI for the VM-only portable control test")
set(BUNDLED_DART_DIRECTORY "" CACHE PATH
     "Directory containing the bundled Dart runtime and its fixed libraries")
set(DART_BUNDLE_DIRECTORY "" CACHE PATH
    "Prebuilt Dart helper bundle containing bundle.o and its manifest")
set(DART_HELPER_SOURCE "${CMAKE_CURRENT_SOURCE_DIR}/../control/dart/run_control_helper.dart"
    CACHE FILEPATH "Dart entrypoint for the privileged control helper")
set(DART_SDK "" CACHE PATH "Dart SDK used to compile the control helper")

if(BUILD_LEGION_CONTROL_SERVICE OR BUILD_PORTABLE_CONTROL_HELPER OR
   BUILD_PORTABLE_BOOTSTRAP_PROTOTYPE OR BUILD_BUNDLED_DART_PROTOTYPE)
  add_library(executable_snapshot STATIC ../control/executable_snapshot.cc)
  target_compile_features(executable_snapshot PUBLIC cxx_std_14)
  target_compile_options(executable_snapshot PRIVATE -Wall -Wextra -Werror)
  target_include_directories(executable_snapshot PUBLIC ../control)
  target_link_libraries(executable_snapshot PUBLIC trusted_executable)
  add_library(portable_lifetime STATIC ../control/portable_lifetime.cc)
  target_compile_features(portable_lifetime PUBLIC cxx_std_14)
  target_compile_options(portable_lifetime PRIVATE -Wall -Wextra -Werror)
  target_include_directories(portable_lifetime PUBLIC ../control)
  target_link_libraries(portable_lifetime PUBLIC PkgConfig::GIO)
endif()


add_library(package_power_sampler STATIC package_power_sampler.cc)
target_compile_features(package_power_sampler PUBLIC cxx_std_14)
target_compile_options(package_power_sampler PRIVATE -Wall -Wextra -Werror)
target_include_directories(package_power_sampler PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})

add_library(telemetry_snapshot STATIC telemetry_snapshot.cc)
target_compile_features(telemetry_snapshot PUBLIC cxx_std_14)
target_compile_options(telemetry_snapshot PRIVATE -Wall -Wextra -Werror)
target_include_directories(telemetry_snapshot PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(telemetry_snapshot
  PUBLIC package_power_sampler PkgConfig::GIO
)

add_executable(legion_telemetry_service legion_telemetry_service.cc)
set_target_properties(legion_telemetry_service PROPERTIES
  OUTPUT_NAME "legion-telemetry-service"
)
target_compile_features(legion_telemetry_service PRIVATE cxx_std_14)
target_compile_options(legion_telemetry_service PRIVATE -Wall -Wextra -Werror)
target_link_libraries(legion_telemetry_service
  PRIVATE telemetry_snapshot PkgConfig::GIO
)

if(BUILD_LEGION_CONTROL_SERVICE OR BUILD_PORTABLE_CONTROL_PROTOTYPE OR BUILD_PORTABLE_BOOTSTRAP_PROTOTYPE)
  pkg_check_modules(POLKIT REQUIRED IMPORTED_TARGET polkit-gobject-1)
  add_library(control_commands STATIC ../control/control_commands.cc)
  target_compile_features(control_commands PUBLIC cxx_std_14)
  target_compile_options(control_commands PRIVATE -Wall -Wextra -Werror)
  target_include_directories(control_commands PUBLIC ../control)
  add_library(managed_command STATIC ../control/managed_command.cc)
  target_compile_features(managed_command PUBLIC cxx_std_14)
  target_compile_options(managed_command PRIVATE -Wall -Wextra -Werror)
  target_include_directories(managed_command PUBLIC ../control)
  target_link_libraries(managed_command PUBLIC PkgConfig::GIO PkgConfig::GIO_UNIX)
  add_library(control_service_runtime STATIC ../control/control_service_runtime.cc)
  target_compile_features(control_service_runtime PUBLIC cxx_std_14)
  target_compile_options(control_service_runtime PRIVATE -Wall -Wextra -Werror)
  target_include_directories(control_service_runtime PUBLIC ../control)
  target_link_libraries(control_service_runtime PUBLIC control_commands managed_command PkgConfig::GIO PkgConfig::POLKIT)

endif()

if(BUILD_LEGION_CONTROL_SERVICE)
  add_executable(legion_control_service ../control/legion_control_service.cc)
  set_target_properties(legion_control_service PROPERTIES OUTPUT_NAME "legion-control-service")
  target_compile_features(legion_control_service PRIVATE cxx_std_14)
  target_compile_options(legion_control_service PRIVATE -Wall -Wextra -Werror)
  target_link_libraries(legion_control_service PRIVATE control_service_runtime trusted_executable control_commands managed_command PkgConfig::GIO PkgConfig::POLKIT)
  add_executable(graphics_next_boot ../control/graphics_next_boot.cc)
  set_target_properties(graphics_next_boot PROPERTIES OUTPUT_NAME "legion-graphics-next-boot")
  target_compile_features(graphics_next_boot PRIVATE cxx_std_14)
  target_compile_options(graphics_next_boot PRIVATE -Wall -Wextra -Werror)
  target_link_libraries(graphics_next_boot PRIVATE control_commands PkgConfig::GIO)
endif()

if(BUILD_PORTABLE_CONTROL_PROTOTYPE)
  add_executable(portable_control_probe ../control/prototype/portable_control_probe.cc ../control/test_support/direct_command_runner.cc)
  target_compile_features(portable_control_probe PRIVATE cxx_std_14)
  target_compile_options(portable_control_probe PRIVATE -Wall -Wextra -Werror)
  target_link_libraries(portable_control_probe PRIVATE control_service_runtime trusted_executable control_commands managed_command PkgConfig::GIO PkgConfig::POLKIT)
endif()

if(BUILD_LEGION_CONTROL_SERVICE OR BUILD_PORTABLE_BOOTSTRAP_PROTOTYPE)
  add_library(portable_cli STATIC ../control/portable_cli.cc)
  target_compile_features(portable_cli PUBLIC cxx_std_14)
  target_compile_options(portable_cli PRIVATE -Wall -Wextra -Werror)
  target_include_directories(portable_cli PUBLIC ../control)
  target_link_libraries(portable_cli PUBLIC control_commands managed_command)
endif()

function(add_portable_helper target)
  add_executable(${target} ../control/portable_bootstrap.cc ../control/portable_control_session.cc)
  target_compile_features(${target} PRIVATE cxx_std_14)
  target_compile_options(${target} PRIVATE -Wall -Wextra -Werror)
  target_link_libraries(${target} PRIVATE portable_cli control_service_runtime trusted_executable executable_snapshot portable_lifetime)
endfunction()

if(BUILD_PORTABLE_CONTROL_HELPER)
  add_executable(legion_portable_control ../control/portable_bootstrap.cc)
  target_compile_features(legion_portable_control PRIVATE cxx_std_14)
  target_compile_options(legion_portable_control PRIVATE -Wall -Wextra -Werror)
  target_link_libraries(legion_portable_control PRIVATE
    executable_snapshot portable_lifetime PkgConfig::GIO PkgConfig::GIO_UNIX)
  if(DART_BUNDLE_DIRECTORY)
    if(NOT EXISTS "${DART_BUNDLE_DIRECTORY}/bundle.o" OR
       NOT EXISTS "${DART_BUNDLE_DIRECTORY}/bundled_dart_manifest.h")
      message(FATAL_ERROR
        "DART_BUNDLE_DIRECTORY must contain bundle.o and bundled_dart_manifest.h")
    endif()
    set(dart_bundle_dir "${DART_BUNDLE_DIRECTORY}")
  endif()
  if(NOT DART_BUNDLE_DIRECTORY AND NOT DART_SDK)
    find_program(DART_EXECUTABLE dart)
    if(DART_EXECUTABLE)
      get_filename_component(DART_EXECUTABLE "${DART_EXECUTABLE}" REALPATH)
      get_filename_component(DART_SDK "${DART_EXECUTABLE}" DIRECTORY)
      get_filename_component(DART_SDK "${DART_SDK}" DIRECTORY)
    endif()
  endif()
  if(NOT DART_BUNDLE_DIRECTORY AND
     (NOT DART_SDK OR NOT EXISTS "${DART_SDK}/bin/dartaotruntime"))
    message(FATAL_ERROR "A Dart SDK is required to build the bundled control helper")
  endif()
  if(NOT DART_BUNDLE_DIRECTORY AND NOT EXISTS "${DART_HELPER_SOURCE}")
    message(FATAL_ERROR "Dart control helper source is missing: ${DART_HELPER_SOURCE}")
  endif()
  if(NOT DART_BUNDLE_DIRECTORY)
    find_program(CMAKE_OBJCOPY NAMES llvm-objcopy objcopy REQUIRED)
    find_program(CMAKE_LINKER NAMES ld.lld ld REQUIRED)
    find_program(DART_HELPER_PATCHELF patchelf REQUIRED)
    find_program(DART_HELPER_PKG_CONFIG NAMES pkg-config REQUIRED)
    find_program(DART_HELPER_LDD NAMES ldd REQUIRED)
    set(dart_bundle_dir "${CMAKE_CURRENT_BINARY_DIR}/dart-helper")
    file(GLOB_RECURSE dart_helper_sources CONFIGURE_DEPENDS
      "${CMAKE_CURRENT_SOURCE_DIR}/../control/dart/*.dart")
    add_custom_command(
    OUTPUT "${dart_bundle_dir}/bundle.o"
           "${dart_bundle_dir}/bundled_dart_manifest.h"
    COMMAND "${DART_SDK}/bin/dart"
      "${CMAKE_CURRENT_SOURCE_DIR}/../tool/build_dart_helper_bundle.dart"
      --sdk "${DART_SDK}" --root "${CMAKE_CURRENT_SOURCE_DIR}/.."
      --source "${DART_HELPER_SOURCE}" --output "${dart_bundle_dir}"
      --objcopy "${CMAKE_OBJCOPY}" --linker "${CMAKE_LINKER}"
      --patchelf "${DART_HELPER_PATCHELF}"
      --pkg-config "${DART_HELPER_PKG_CONFIG}" --ldd "${DART_HELPER_LDD}"
      DEPENDS "${DART_HELPER_SOURCE}"
              "${CMAKE_CURRENT_SOURCE_DIR}/../tool/build_dart_helper_bundle.dart"
              "${CMAKE_CURRENT_SOURCE_DIR}/../pubspec.yaml"
              "${CMAKE_CURRENT_SOURCE_DIR}/../.dart_tool/package_config.json"
              ${dart_helper_sources}
      VERBATIM)
  endif()
  add_custom_target(dart_helper_bundle
    DEPENDS "${dart_bundle_dir}/bundle.o"
            "${dart_bundle_dir}/bundled_dart_manifest.h")
  add_dependencies(legion_portable_control dart_helper_bundle)
  target_sources(legion_portable_control PRIVATE
    ../control/prototype/bundled_dart_runtime.cc
    "${dart_bundle_dir}/bundle.o")
  target_include_directories(legion_portable_control PRIVATE
    "${dart_bundle_dir}")
  target_compile_definitions(legion_portable_control PRIVATE LEGION_BUNDLED_DART_RUNTIME)
  target_link_options(legion_portable_control PRIVATE -Wl,-z,noexecstack)
  if(BUILD_PORTABLE_CONTROL_STATIC)
    target_link_options(legion_portable_control PRIVATE -static -Wl,--gc-sections -Wl,-t)
  endif()
endif()
if(BUILD_PORTABLE_CONTROL_HELPER OR
   (BUILD_PORTABLE_CONTROL_STATIC AND BUILD_BUNDLED_DART_PROTOTYPE))
  if(NOT TARGET legion_portable_cleanup)
    add_executable(legion_portable_cleanup ../control/portable_cleanup.cc)
    target_compile_features(legion_portable_cleanup PRIVATE cxx_std_14)
    target_compile_options(legion_portable_cleanup PRIVATE
      -Os -fno-pie -fno-stack-protector -fno-exceptions -fno-rtti
      -fno-asynchronous-unwind-tables -fno-unwind-tables)
    target_link_options(legion_portable_cleanup PRIVATE
      -nostdlib -static -no-pie -Wl,--build-id=none -Wl,-e,_start)
    add_custom_command(OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/portable_cleanup_image.h"
      COMMAND ${CMAKE_COMMAND} -DINPUT=$<TARGET_FILE:legion_portable_cleanup>
        -DOUTPUT=${CMAKE_CURRENT_BINARY_DIR}/portable_cleanup_image.h
        -P "${CMAKE_CURRENT_SOURCE_DIR}/../control/embed_cleanup.cmake"
      DEPENDS legion_portable_cleanup ../control/embed_cleanup.cmake VERBATIM)
    add_custom_target(portable_cleanup_image DEPENDS "${CMAKE_CURRENT_BINARY_DIR}/portable_cleanup_image.h")
  endif()
  if(BUILD_PORTABLE_CONTROL_HELPER)
    add_dependencies(legion_portable_control portable_cleanup_image)
    target_include_directories(legion_portable_control PRIVATE "${CMAKE_CURRENT_BINARY_DIR}")
    target_compile_definitions(legion_portable_control PRIVATE LEGION_EMBEDDED_CLEANUP)
  endif()
endif()
if(BUILD_PORTABLE_CONTROL_HELPER)
  if(CMAKE_VERSION VERSION_LESS 3.16)
    message(FATAL_ERROR "Portable helper builds require CMake 3.16 or later.")
  endif()
  # Nix wrappers inject development rpaths. Keep only canonical store libraries;
  # other hosts use the loader cache. Never inherit the desktop bundle rpath.
  set(portable_host_library_paths "")
  foreach(directory IN LISTS GIO_LIBRARY_DIRS POLKIT_LIBRARY_DIRS CMAKE_CXX_IMPLICIT_LINK_DIRECTORIES)
    get_filename_component(canonical_directory "${directory}" REALPATH)
    if(canonical_directory MATCHES "^/nix/store/" AND IS_DIRECTORY "${canonical_directory}")
      list(APPEND portable_host_library_paths "${canonical_directory}")
    endif()
  endforeach()
  list(REMOVE_DUPLICATES portable_host_library_paths)
  set_target_properties(legion_portable_control PROPERTIES
    OUTPUT_NAME "legion-portable-control"
    INSTALL_REMOVE_ENVIRONMENT_RPATH TRUE
    INSTALL_RPATH_USE_LINK_PATH FALSE
    INSTALL_RPATH "${portable_host_library_paths}")
endif()
if(BUILD_PORTABLE_BOOTSTRAP_PROTOTYPE)
  add_portable_helper(portable_bootstrap_probe)
  target_compile_definitions(portable_bootstrap_probe PRIVATE LEGION_PORTABLE_TEST PORTABLE_CONTROL_TEST_CLI="${PORTABLE_CONTROL_TEST_CLI}")
endif()

if(BUILD_BUNDLED_DART_PROTOTYPE)
  if(NOT BUNDLED_DART_DIRECTORY OR
     NOT EXISTS "${BUNDLED_DART_DIRECTORY}/dartaotruntime" OR
     NOT EXISTS "${BUNDLED_DART_DIRECTORY}/helper.aot")
    message(FATAL_ERROR
      "BUNDLED_DART_DIRECTORY must contain dartaotruntime and helper.aot")
  endif()
  find_program(CMAKE_OBJCOPY NAMES llvm-objcopy objcopy REQUIRED)
  set(bundled_dart_inputs
    dartaotruntime helper.aot lib/ld-linux-x86-64.so.2 lib/libc.so.6
    lib/libm.so.6 lib/libdl.so.2 lib/libpthread.so.0)
  set(bundled_dart_objects "")
  foreach(relative_path IN LISTS bundled_dart_inputs)
    get_filename_component(file_name "${relative_path}" NAME)
    set(object "${CMAKE_CURRENT_BINARY_DIR}/bundled_dart_${file_name}.o")
    add_custom_command(
      OUTPUT "${object}"
      COMMAND "${CMAKE_OBJCOPY}" -I binary -O elf64-x86-64 -B i386:x86-64
        --rename-section .data=.rodata,alloc,load,readonly,data,contents
        "${relative_path}" "${object}"
      DEPENDS "${BUNDLED_DART_DIRECTORY}/${relative_path}"
      WORKING_DIRECTORY "${BUNDLED_DART_DIRECTORY}"
      VERBATIM)
    list(APPEND bundled_dart_objects "${object}")
  endforeach()
  add_executable(bundled_dart_bootstrap_probe
    ../control/portable_bootstrap.cc
    ../control/prototype/bundled_dart_runtime.cc
    ${bundled_dart_objects})
  target_compile_features(bundled_dart_bootstrap_probe PRIVATE cxx_std_14)
  target_compile_options(bundled_dart_bootstrap_probe PRIVATE -Wall -Wextra -Werror)
  target_link_options(bundled_dart_bootstrap_probe PRIVATE -Wl,-z,noexecstack)
  target_compile_definitions(bundled_dart_bootstrap_probe PRIVATE
    LEGION_PORTABLE_TEST LEGION_BUNDLED_DART_PROTOTYPE)
  target_include_directories(bundled_dart_bootstrap_probe PRIVATE
    ../control "${CMAKE_CURRENT_BINARY_DIR}")
  target_link_libraries(bundled_dart_bootstrap_probe PRIVATE
    executable_snapshot portable_lifetime PkgConfig::GIO PkgConfig::GIO_UNIX)
  add_executable(bundled_dart_runtime_test EXCLUDE_FROM_ALL
    ../control/prototype/bundled_dart_runtime_test.cc
    ../control/prototype/bundled_dart_runtime.cc
    ${bundled_dart_objects})
  target_compile_features(bundled_dart_runtime_test PRIVATE cxx_std_14)
  target_compile_options(bundled_dart_runtime_test PRIVATE -Wall -Wextra -Werror)
  target_link_options(bundled_dart_runtime_test PRIVATE -Wl,-z,noexecstack)
  target_compile_definitions(bundled_dart_runtime_test PRIVATE
    LEGION_BUNDLED_DART_TEST)
  target_include_directories(bundled_dart_runtime_test PRIVATE ../control)
  target_link_libraries(bundled_dart_runtime_test PRIVATE PkgConfig::GIO)
  if(BUILD_PORTABLE_CONTROL_STATIC)
    target_link_options(bundled_dart_bootstrap_probe PRIVATE -static -Wl,--gc-sections)
    add_dependencies(bundled_dart_bootstrap_probe portable_cleanup_image)
    target_include_directories(bundled_dart_bootstrap_probe PRIVATE
      "${CMAKE_CURRENT_BINARY_DIR}")
    target_compile_definitions(bundled_dart_bootstrap_probe PRIVATE
      LEGION_EMBEDDED_CLEANUP)
  endif()
endif()

install(TARGETS legion_telemetry_service
  RUNTIME DESTINATION "libexec"
  COMPONENT Runtime
)
if(BUILD_LEGION_CONTROL_SERVICE)
  install(TARGETS legion_control_service RUNTIME DESTINATION "libexec" COMPONENT Runtime)
  install(TARGETS graphics_next_boot RUNTIME DESTINATION "bin" COMPONENT Runtime)
  install(FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/../packaging/systemd/legion-control.service"
    DESTINATION "lib/systemd/system" COMPONENT Runtime)
  install(FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/../packaging/dbus/io.github.prnice.LegionControl1.conf"
    DESTINATION "share/dbus-1/system.d" COMPONENT Runtime)
  install(FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/../packaging/polkit/io.github.prnice.legion-control.policy"
    DESTINATION "share/polkit-1/actions" COMPONENT Runtime)
endif()
install(FILES
  "${CMAKE_CURRENT_SOURCE_DIR}/../packaging/systemd/legion-telemetry.service"
  DESTINATION "lib/systemd/system"
  COMPONENT Runtime
)
install(FILES
  "${CMAKE_CURRENT_SOURCE_DIR}/../packaging/dbus/io.github.prnice.LegionTelemetry1.conf"
  DESTINATION "share/dbus-1/system.d"
  COMPONENT Runtime
)
install(FILES
  "${CMAKE_CURRENT_SOURCE_DIR}/../packaging/sysusers/legion-telemetry.conf"
  DESTINATION "lib/sysusers.d"
  COMPONENT Runtime
)

include(CTest)
if(BUILD_TESTING)
  if(TARGET bundled_dart_runtime_test)
    add_test(NAME bundled_dart_runtime COMMAND bundled_dart_runtime_test)
    set_tests_properties(bundled_dart_runtime PROPERTIES TIMEOUT 10)
  endif()
  add_executable(trusted_executable_test EXCLUDE_FROM_ALL ../control/trusted_executable_test.cc)
  target_link_libraries(trusted_executable_test PRIVATE trusted_executable PkgConfig::GIO)
  target_compile_options(trusted_executable_test PRIVATE -Wall -Wextra -Werror)
  add_test(NAME trusted_executable COMMAND trusted_executable_test)
  add_executable(portable_peer_test EXCLUDE_FROM_ALL ../control/portable_peer_test.cc)
  target_link_libraries(portable_peer_test PRIVATE portable_peer)
  target_compile_options(portable_peer_test PRIVATE -Wall -Wextra -Werror)
  add_test(NAME portable_peer COMMAND portable_peer_test)
  set_tests_properties(portable_peer PROPERTIES TIMEOUT 10)
  add_executable(package_power_sampler_test EXCLUDE_FROM_ALL
    package_power_sampler_test.cc
  )
  target_compile_features(package_power_sampler_test PRIVATE cxx_std_14)
  target_compile_options(package_power_sampler_test PRIVATE
    -Wall -Wextra -Werror
  )
  target_link_libraries(package_power_sampler_test
    PRIVATE telemetry_snapshot PkgConfig::GIO
  )
  add_test(NAME package_power_sampler COMMAND package_power_sampler_test)
  if(BUILD_LEGION_CONTROL_SERVICE)
    add_executable(portable_cli_test EXCLUDE_FROM_ALL ../control/portable_cli_test.cc)
    target_link_libraries(portable_cli_test PRIVATE portable_cli)
    target_compile_options(portable_cli_test PRIVATE -Wall -Wextra -Werror)
    add_test(NAME portable_cli COMMAND portable_cli_test)
    add_executable(portable_lifetime_test EXCLUDE_FROM_ALL ../control/portable_lifetime_test.cc)
    target_compile_features(portable_lifetime_test PRIVATE cxx_std_14)
    target_compile_options(portable_lifetime_test PRIVATE -Wall -Wextra -Werror)
    target_link_libraries(portable_lifetime_test PRIVATE portable_lifetime)
    add_test(NAME portable_lifetime COMMAND portable_lifetime_test)
    set_tests_properties(portable_lifetime PROPERTIES TIMEOUT 10)
    add_executable(executable_snapshot_test EXCLUDE_FROM_ALL ../control/executable_snapshot_test.cc)
    target_compile_features(executable_snapshot_test PRIVATE cxx_std_14)
    target_compile_options(executable_snapshot_test PRIVATE -Wall -Wextra -Werror)
    target_link_libraries(executable_snapshot_test PRIVATE executable_snapshot PkgConfig::GIO)
    add_test(NAME executable_snapshot COMMAND executable_snapshot_test)
    set_tests_properties(executable_snapshot PROPERTIES TIMEOUT 20)
    add_executable(control_commands_test EXCLUDE_FROM_ALL ../control/control_commands_test.cc)
    target_compile_features(control_commands_test PRIVATE cxx_std_14)
    target_compile_options(control_commands_test PRIVATE -Wall -Wextra -Werror)
    target_link_libraries(control_commands_test PRIVATE control_commands PkgConfig::GIO)
    add_test(NAME control_commands COMMAND control_commands_test)
    add_executable(managed_command_test EXCLUDE_FROM_ALL ../control/managed_command_test.cc)
    target_compile_features(managed_command_test PRIVATE cxx_std_14)
    target_compile_options(managed_command_test PRIVATE -Wall -Wextra -Werror)
    target_link_libraries(managed_command_test PRIVATE managed_command PkgConfig::GIO)
    add_test(NAME managed_command COMMAND managed_command_test)
    set_tests_properties(managed_command PROPERTIES TIMEOUT 90)
    add_executable(graphics_boot_service_test EXCLUDE_FROM_ALL ../control/graphics_boot_service_test.cc ../control/test_support/direct_command_runner.cc)
    target_compile_features(graphics_boot_service_test PRIVATE cxx_std_14)
    target_compile_options(graphics_boot_service_test PRIVATE -Wall -Wextra -Werror)
    target_link_libraries(graphics_boot_service_test PRIVATE control_service_runtime trusted_executable control_commands managed_command PkgConfig::GIO PkgConfig::POLKIT)
    target_compile_definitions(graphics_boot_service_test PRIVATE GRAPHICS_CLIENT_PATH="$<TARGET_FILE:graphics_next_boot>")
    add_dependencies(graphics_boot_service_test graphics_next_boot)
    add_test(NAME graphics_boot_service COMMAND graphics_boot_service_test)
    set_tests_properties(graphics_boot_service PROPERTIES TIMEOUT 20)
  endif()
endif()
