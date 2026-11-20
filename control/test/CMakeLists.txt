cmake_minimum_required(VERSION 3.13)
project(legion_control_vm_fixtures LANGUAGES CXX)

find_package(PkgConfig REQUIRED)
pkg_check_modules(GIO REQUIRED IMPORTED_TARGET gio-2.0)
pkg_check_modules(GIO_UNIX REQUIRED IMPORTED_TARGET gio-unix-2.0)
add_library(control_peer STATIC ../control_peer.cc)
target_compile_features(control_peer PUBLIC cxx_std_14)
target_compile_options(control_peer PRIVATE -Wall -Wextra -Werror)
target_include_directories(control_peer PUBLIC ..)
target_link_libraries(control_peer PUBLIC PkgConfig::GIO PkgConfig::GIO_UNIX)

add_executable(legion_cli control_cli_fixture.cc)
add_executable(legion-helper-test-client control_test_client.cc)
foreach(target legion_cli legion-helper-test-client)
  target_compile_features(${target} PRIVATE cxx_std_14)
  target_compile_options(${target} PRIVATE -Wall -Wextra -Werror)
endforeach()
target_link_libraries(legion-helper-test-client PRIVATE control_peer)

# This probe only inspects paths; it never launches the CLI or a helper.
add_executable(host-cli-read-test ../trusted_executable_test.cc ../trusted_executable.cc)
target_compile_features(host-cli-read-test PRIVATE cxx_std_14)
target_compile_options(host-cli-read-test PRIVATE -Wall -Wextra -Werror)
target_include_directories(host-cli-read-test PRIVATE ..)
target_link_libraries(host-cli-read-test PRIVATE PkgConfig::GIO)

# These executables belong only to the disposable VM's fixture package.
install(TARGETS legion_cli legion-helper-test-client host-cli-read-test RUNTIME DESTINATION bin)
