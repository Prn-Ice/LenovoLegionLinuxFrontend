cmake_minimum_required(VERSION 3.13)
project(legion_telemetry LANGUAGES CXX)

find_package(PkgConfig REQUIRED)
pkg_check_modules(GIO REQUIRED IMPORTED_TARGET gio-2.0)
pkg_check_modules(GIO_UNIX REQUIRED IMPORTED_TARGET gio-unix-2.0)
option(BUILD_LEGION_CONTROL_SERVICE "Build the privileged Legion control service" OFF)
option(BUILD_PORTABLE_CONTROL_PROTOTYPE "Build the hardware-free private-peer control probe" OFF)
option(BUILD_PORTABLE_BOOTSTRAP_PROTOTYPE "Build the VM-only administrator-startup probe" OFF)
set(PORTABLE_CONTROL_TEST_CLI "" CACHE FILEPATH "Fixed synthetic CLI for the VM-only portable control test")

if(BUILD_LEGION_CONTROL_SERVICE OR BUILD_PORTABLE_BOOTSTRAP_PROTOTYPE)
  add_library(executable_snapshot STATIC ../control/executable_snapshot.cc)
  target_compile_features(executable_snapshot PUBLIC cxx_std_14)
  target_compile_options(executable_snapshot PRIVATE -Wall -Wextra -Werror)
  target_include_directories(executable_snapshot PUBLIC ../control)
  add_library(portable_lifetime STATIC ../control/portable_lifetime.cc)
  target_compile_features(portable_lifetime PUBLIC cxx_std_14)
  target_compile_options(portable_lifetime PRIVATE -Wall -Wextra -Werror)
  target_include_directories(portable_lifetime PUBLIC ../control)
  target_link_libraries(portable_lifetime PUBLIC PkgConfig::GIO)
endif()

if(BUILD_PORTABLE_BOOTSTRAP_PROTOTYPE)
  add_executable(portable_bootstrap_probe ../control/prototype/portable_bootstrap_probe.cc ../control/prototype/portable_control_helper.cc)
  target_compile_features(portable_bootstrap_probe PRIVATE cxx_std_14)
  target_compile_options(portable_bootstrap_probe PRIVATE -Wall -Wextra -Werror)
  target_compile_definitions(portable_bootstrap_probe PRIVATE PORTABLE_CONTROL_TEST_CLI="${PORTABLE_CONTROL_TEST_CLI}")
  target_link_libraries(portable_bootstrap_probe PRIVATE executable_snapshot portable_lifetime control_commands managed_command PkgConfig::GIO PkgConfig::GIO_UNIX PkgConfig::POLKIT)
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
endif()

if(BUILD_LEGION_CONTROL_SERVICE)
  add_executable(legion_control_service ../control/legion_control_service.cc)
  set_target_properties(legion_control_service PROPERTIES OUTPUT_NAME "legion-control-service")
  target_compile_features(legion_control_service PRIVATE cxx_std_14)
  target_compile_options(legion_control_service PRIVATE -Wall -Wextra -Werror)
  target_link_libraries(legion_control_service PRIVATE control_commands managed_command PkgConfig::GIO PkgConfig::POLKIT)
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
  target_link_libraries(portable_control_probe PRIVATE control_commands managed_command PkgConfig::GIO PkgConfig::POLKIT)
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
    target_link_libraries(graphics_boot_service_test PRIVATE control_commands managed_command PkgConfig::GIO PkgConfig::POLKIT)
    target_compile_definitions(graphics_boot_service_test PRIVATE GRAPHICS_CLIENT_PATH="$<TARGET_FILE:graphics_next_boot>")
    add_dependencies(graphics_boot_service_test graphics_next_boot)
    add_test(NAME graphics_boot_service COMMAND graphics_boot_service_test)
    set_tests_properties(graphics_boot_service PROPERTIES TIMEOUT 20)
  endif()
endif()
