cmake_minimum_required(VERSION 3.13)
project(legion_control_vm_fixtures LANGUAGES CXX)

find_package(PkgConfig REQUIRED)
pkg_check_modules(GIO REQUIRED IMPORTED_TARGET gio-2.0)

add_executable(legion_cli control_lifecycle_fixture.cc)
add_executable(legion-control-test-client control_lifecycle_client.cc)
foreach(target legion_cli legion-control-test-client)
  target_compile_features(${target} PRIVATE cxx_std_14)
  target_compile_options(${target} PRIVATE -Wall -Wextra -Werror)
endforeach()
target_link_libraries(legion-control-test-client PRIVATE PkgConfig::GIO)

# These executables belong only to the disposable VM's fixture package.
install(TARGETS legion_cli legion-control-test-client RUNTIME DESTINATION bin)
