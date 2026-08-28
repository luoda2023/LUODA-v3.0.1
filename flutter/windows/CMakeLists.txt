# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(luoda LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "luoda")

# Explicitly opt into modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(SET CMP0063 NEW)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")
# Replace /MD flags to /MT to use static vcruntine
set(CompilerFlags
        CMAKE_CXX_FLAGS
        CMAKE_CXX_FLAGS_DEBUG
        CMAKE_CXX_FLAGS_RELEASE
        CMAKE_C_FLAGS
        CMAKE_C_FLAGS_DEBUG
        CMAKE_C_FLAGS_RELEASE
        )
foreach(CompilerFlag ${CompilerFlags})
  string(REPLACE "/MD" "/MT" ${CompilerFlag} "${${CompilerFlag}}")
endforeach()

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /utf-8 /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  # Disable VC140_1
  target_compile_options(${TARGET} PRIVATE /d2FH4-)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")

# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)


# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# flutter_rust_bridge
set(LUODA_LIB_BUILD_TYPE $<IF:$<CONFIG:Debug>,debug,release>)
message(STATUS "luoda lib build type: ${LUODA_LIB_BUILD_TYPE}")
set(LUODA_LIB "../../target/${LUODA_LIB_BUILD_TYPE}/luoda.dll")
install(FILES "${LUODA_LIB}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
COMPONENT Runtime RENAME luoda.dll)

# === shot_overlay.exe (screenshot region tool) ===
# Compiled from assets/scripts/shot_overlay.cs with the .NET Framework csc.exe
# into a WinForms GUI app (no console window, no PowerShell startup delay,
# UTF-8 source so the Chinese hint can never be mojibake). Compilation runs
# at CONFIGURE time via execute_process: invoking csc as an MSBuild custom
# build step fails because MSBuild poisons the LIB environment variable and
# rewrites relative paths, so a plain configure-time compile is far more
# reliable. If csc.exe is unavailable the build continues; the Dart side then
# falls back to the PowerShell overlay script.
set(SHOT_OVERLAY_CS "${CMAKE_CURRENT_SOURCE_DIR}/../assets/scripts/shot_overlay.cs")
set(SHOT_OVERLAY_EXE "${CMAKE_CURRENT_BINARY_DIR}/shot_overlay.exe")
find_program(DOTNET_CSC csc.exe
  PATHS "C:/Windows/Microsoft.NET/Framework64/v4.0.30319"
  NO_DEFAULT_PATH)
if(DOTNET_CSC)
  # csc resolves -r: references via the LIB environment variable, which the
  # Flutter/VS build environment poisons with paths that do not exist. Pass
  # full framework paths explicitly so the compile is hermetic.
  set(DOTNET_FX "C:/Windows/Microsoft.NET/Framework64/v4.0.30319")
  execute_process(
    COMMAND "${DOTNET_CSC}" -nologo -target:winexe -codepage:65001 -optimize+
            "-r:${DOTNET_FX}/System.Windows.Forms.dll"
            "-r:${DOTNET_FX}/System.Drawing.dll"
            "-out:${SHOT_OVERLAY_EXE}" "${SHOT_OVERLAY_CS}"
    WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
    RESULT_VARIABLE SHOT_OVERLAY_RC
    OUTPUT_VARIABLE SHOT_OVERLAY_OUT
    ERROR_VARIABLE SHOT_OVERLAY_ERR)
  if(SHOT_OVERLAY_RC)
    message(WARNING "shot_overlay.exe compile failed (rc=${SHOT_OVERLAY_RC}): ${SHOT_OVERLAY_ERR}; screenshot will fall back to PowerShell (runtime build will be attempted)")
  else()
    install(FILES "${SHOT_OVERLAY_EXE}"
      DESTINATION "${INSTALL_BUNDLE_LIB_DIR}" COMPONENT Runtime)
  endif()
else()
  message(WARNING "csc.exe not found; screenshot will fall back to PowerShell")
endif()

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)
