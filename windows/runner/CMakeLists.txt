cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "flutter_window.cpp"
  "main.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Window title per flavor. Flutter 3.47+ sets FLUTTER_APP_FLAVOR when building
# with --flavor (see https://docs.flutter.dev/deployment/flavors-windows).
# Older SDKs, and builds without --flavor, get the neutral name; Dart then
# decides the role from --dart-define=YESEM_APP or --yesem-role and retitles
# the window at start-up through window_manager.
if(DEFINED FLUTTER_APP_FLAVOR AND FLUTTER_APP_FLAVOR STREQUAL "pincode")
  set(YESEM_WINDOW_TITLE "YesEm Pin Code Manager")
elseif(DEFINED FLUTTER_APP_FLAVOR AND FLUTTER_APP_FLAVOR STREQUAL "desktop")
  set(YESEM_WINDOW_TITLE "YesEm Desktop")
else()
  set(YESEM_WINDOW_TITLE "YesEm")
endif()
target_compile_definitions(${BINARY_NAME} PRIVATE "YESEM_WINDOW_TITLE=\"${YESEM_WINDOW_TITLE}\"")

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)
