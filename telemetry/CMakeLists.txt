cmake_minimum_required(VERSION 3.13)
project(legion_telemetry LANGUAGES CXX)

find_package(PkgConfig REQUIRED)
pkg_check_modules(GIO REQUIRED IMPORTED_TARGET gio-2.0)

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

install(TARGETS legion_telemetry_service
  RUNTIME DESTINATION "libexec"
  COMPONENT Runtime
)
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
endif()
