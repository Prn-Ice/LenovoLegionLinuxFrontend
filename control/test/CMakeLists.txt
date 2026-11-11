cmake_minimum_required(VERSION 3.13)
project(legion_control_vm_fixtures LANGUAGES CXX)

find_package(PkgConfig REQUIRED)
pkg_check_modules(GIO REQUIRED IMPORTED_TARGET gio-2.0)
pkg_check_modules(GIO_UNIX REQUIRED IMPORTED_TARGET gio-unix-2.0)
add_library(portable_peer STATIC ../portable_peer.cc)
target_compile_features(portable_peer PUBLIC cxx_std_14)
target_compile_options(portable_peer PRIVATE -Wall -Wextra -Werror)
target_include_directories(portable_peer PUBLIC ..)
target_link_libraries(portable_peer PUBLIC PkgConfig::GIO PkgConfig::GIO_UNIX)

add_executable(legion_cli control_lifecycle_fixture.cc)
add_executable(legion-control-test-client control_lifecycle_client.cc)
add_executable(legion-portable-test-client portable_control_client.cc)
foreach(target legion_cli legion-control-test-client legion-portable-test-client)
  target_compile_features(${target} PRIVATE cxx_std_14)
  target_compile_options(${target} PRIVATE -Wall -Wextra -Werror)
endforeach()
target_link_libraries(legion-control-test-client PRIVATE PkgConfig::GIO)
target_link_libraries(legion-portable-test-client PRIVATE portable_peer)

# These executables belong only to the disposable VM's fixture package.
install(TARGETS legion_cli legion-control-test-client legion-portable-test-client RUNTIME DESTINATION bin)
