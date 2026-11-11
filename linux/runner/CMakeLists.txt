cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# Set the executable name through BINARY_NAME in ../CMakeLists.txt so Flutter
# can find it. Add runner source files to this target.
add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "portable_control_channel.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

# Use the shared compiler settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the application ID.
add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

# Link runner dependencies.
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)
target_link_libraries(${BINARY_NAME} PRIVATE portable_peer trusted_executable)

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

add_executable(portable_control_channel_test EXCLUDE_FROM_ALL portable_control_channel_test.cc)
apply_standard_settings(portable_control_channel_test)
target_link_libraries(portable_control_channel_test PRIVATE flutter PkgConfig::GTK portable_peer trusted_executable)
