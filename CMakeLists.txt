cmake_minimum_required(VERSION 3.20)

# ─── Arm64 only, macOS only ──────────────────────────────────────────────────
if(NOT APPLE)
  message(FATAL_ERROR "obs-syphon-server is macOS-only.")
endif()

set(CMAKE_OSX_ARCHITECTURES "arm64" CACHE STRING "Build architectures" FORCE)
set(CMAKE_OSX_DEPLOYMENT_TARGET "12.0" CACHE STRING "Minimum macOS version" FORCE)

# Prefer Command Line Tools clang (newer libc++ headers than the bundled Xcode).
if(NOT CMAKE_C_COMPILER AND EXISTS "/Library/Developer/CommandLineTools/usr/bin/clang")
  set(CMAKE_C_COMPILER   "/Library/Developer/CommandLineTools/usr/bin/clang"   CACHE FILEPATH "" FORCE)
  set(CMAKE_CXX_COMPILER "/Library/Developer/CommandLineTools/usr/bin/clang++" CACHE FILEPATH "" FORCE)
endif()
if(NOT CMAKE_OSX_SYSROOT)
  file(GLOB _clt_sdks "/Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk")
  if(_clt_sdks)
    list(SORT _clt_sdks)
    list(REVERSE _clt_sdks)
    list(GET _clt_sdks 0 _clt_sdk)
    set(CMAKE_OSX_SYSROOT "${_clt_sdk}" CACHE PATH "" FORCE)
  endif()
endif()

project(obs-syphon-server VERSION 2.0.1 LANGUAGES C CXX OBJC OBJCXX)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(PLUGIN_NAME ${PROJECT_NAME})

# ─── Syphon framework: compile sources directly (no xcodebuild) ─────────────
set(SYPHON_DIR "${CMAKE_CURRENT_SOURCE_DIR}/deps/Syphon-Framework")
if(NOT EXISTS "${SYPHON_DIR}/Syphon.h")
  message(FATAL_ERROR "Syphon sources missing — run: git submodule update --init --recursive")
endif()

# All .m/.c files except Metal (we only use the OpenGL server)
file(GLOB SYPHON_M  "${SYPHON_DIR}/*.m")
file(GLOB SYPHON_C  "${SYPHON_DIR}/*.c")
list(FILTER SYPHON_M EXCLUDE REGEX ".*Metal.*\\.m$")
set(SYPHON_SOURCES ${SYPHON_M} ${SYPHON_C})

# Create an include shim so `#import <Syphon/Foo.h>` resolves without a framework
set(SYPHON_SHIM_DIR "${CMAKE_BINARY_DIR}/syphon-include")
file(MAKE_DIRECTORY "${SYPHON_SHIM_DIR}/Syphon")
file(GLOB SYPHON_HEADERS "${SYPHON_DIR}/*.h")
foreach(_h IN LISTS SYPHON_HEADERS)
  get_filename_component(_hn "${_h}" NAME)
  if(NOT EXISTS "${SYPHON_SHIM_DIR}/Syphon/${_hn}")
    file(CREATE_LINK "${_h}" "${SYPHON_SHIM_DIR}/Syphon/${_hn}" SYMBOLIC)
  endif()
endforeach()

add_library(syphon STATIC ${SYPHON_SOURCES})
set_target_properties(syphon PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_include_directories(syphon PUBLIC "${SYPHON_DIR}" "${SYPHON_SHIM_DIR}")
# Inject Cocoa import in place of the upstream Syphon_Prefix.pch
target_compile_options(syphon PRIVATE
  -include "${SYPHON_DIR}/Syphon_Prefix.pch"
  -fobjc-arc
  -Wno-deprecated-declarations
  -Wno-unused-parameter
  -Wno-shorten-64-to-32
  -Wno-incompatible-pointer-types
  -fvisibility=hidden
)

find_library(COCOA_FW     Cocoa     REQUIRED)
find_library(OPENGL_FW    OpenGL    REQUIRED)
find_library(IOSURFACE_FW IOSurface REQUIRED)

target_link_libraries(syphon PUBLIC ${COCOA_FW} ${OPENGL_FW} ${IOSURFACE_FW})

# ─── OBS Studio (use installed app's libobs + submodule headers) ─────────────
set(OBS_APP "/Applications/OBS.app/Contents")
set(OBS_LIBOBS "${OBS_APP}/Frameworks/libobs.framework/Versions/A/libobs")
set(OBS_FRONTEND "${OBS_APP}/Frameworks/obs-frontend-api.dylib")
set(OBS_HEADERS "${CMAKE_CURRENT_SOURCE_DIR}/deps/obs-studio/libobs")
set(OBS_FRONTEND_HEADERS "${CMAKE_CURRENT_SOURCE_DIR}/deps/obs-studio/frontend/api")

if(NOT EXISTS "${OBS_LIBOBS}")
  message(FATAL_ERROR "OBS not installed at /Applications/OBS.app — install OBS Studio first.")
endif()
if(NOT EXISTS "${OBS_HEADERS}/obs.h")
  message(FATAL_ERROR "OBS headers missing — run: git submodule update --init --recursive")
endif()

# ─── Plugin target ──────────────────────────────────────────────────────────
configure_file(src/plugin-support.c.in src/plugin-support.c @ONLY)

add_library(${PLUGIN_NAME} MODULE
  src/plugin-main.c
  src/syphon-server.mm
  src/syphon-publisher.mm
  src/syphon-filter.mm
  src/syphon-tools.mm
  ${CMAKE_BINARY_DIR}/src/plugin-support.c
)

target_include_directories(${PLUGIN_NAME} BEFORE PRIVATE
  src
  "${OBS_HEADERS}"
  "${OBS_FRONTEND_HEADERS}"
)

target_compile_definitions(${PLUGIN_NAME} PRIVATE
  PLUGIN_NAME_STR="${PLUGIN_NAME}"
  PLUGIN_VERSION_STR="${PROJECT_VERSION}"
  GL_SILENCE_DEPRECATION
)

target_compile_options(${PLUGIN_NAME} PRIVATE
  -Wall -Wextra -Wno-unused-parameter
  -fobjc-arc
  -fvisibility=hidden -fvisibility-inlines-hidden
)

target_link_libraries(${PLUGIN_NAME} PRIVATE
  syphon
  "${OBS_LIBOBS}"
  "${OBS_FRONTEND}"
)

target_link_options(${PLUGIN_NAME} PRIVATE
  "-Wl,-rpath,${OBS_APP}/Frameworks"
)

set_target_properties(${PLUGIN_NAME} PROPERTIES
  BUNDLE TRUE
  BUNDLE_EXTENSION "plugin"
  OUTPUT_NAME ${PLUGIN_NAME}
  MACOSX_BUNDLE_BUNDLE_NAME ${PLUGIN_NAME}
  MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION}
  MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION}
  MACOSX_BUNDLE_GUI_IDENTIFIER "com.obsproject.${PLUGIN_NAME}"
)

# ─── Bundle locale data ─────────────────────────────────────────────────────
add_custom_command(TARGET ${PLUGIN_NAME} POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_directory
          "${CMAKE_CURRENT_SOURCE_DIR}/data"
          "$<TARGET_BUNDLE_CONTENT_DIR:${PLUGIN_NAME}>/Resources"
  COMMENT "Copying plugin data into bundle"
)

# ─── Install ────────────────────────────────────────────────────────────────
set(OBS_USER_PLUGINS "$ENV{HOME}/Library/Application Support/obs-studio/plugins")

install(DIRECTORY "$<TARGET_BUNDLE_DIR:${PLUGIN_NAME}>"
        DESTINATION "${OBS_USER_PLUGINS}"
        USE_SOURCE_PERMISSIONS)

add_custom_target(install-plugin
  COMMAND ${CMAKE_COMMAND} --install "${CMAKE_BINARY_DIR}"
  DEPENDS ${PLUGIN_NAME}
  COMMENT "Installing ${PLUGIN_NAME}.plugin → ${OBS_USER_PLUGINS}")

add_custom_target(uninstall-plugin
  COMMAND ${CMAKE_COMMAND} -E rm -rf "${OBS_USER_PLUGINS}/${PLUGIN_NAME}.plugin"
  COMMENT "Removing ${PLUGIN_NAME}.plugin")

message(STATUS "")
message(STATUS "  obs-syphon-server v${PROJECT_VERSION}  (arm64)")
message(STATUS "  Toolchain:  ${CMAKE_C_COMPILER}")
message(STATUS "  SDK:        ${CMAKE_OSX_SYSROOT}")
message(STATUS "  OBS:        ${OBS_APP}")
message(STATUS "  Syphon:     in-tree static (no Xcode required)")
message(STATUS "  Install to: ${OBS_USER_PLUGINS}")
message(STATUS "")
