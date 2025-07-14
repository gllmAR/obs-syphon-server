cmake_minimum_required(VERSION 3.16)

project(obs-syphon-server VERSION 1.0.0 LANGUAGES C CXX)

# For macOS, build for current architecture or universal binary
if(APPLE)
  # Check OBS architecture support early to set build architectures
  set(OBS_APP_PATH "/Applications/OBS.app/Contents")
  if(EXISTS "${OBS_APP_PATH}/Frameworks/libobs.framework")
    # Check what architectures OBS supports
    execute_process(
      COMMAND file "${OBS_APP_PATH}/Frameworks/libobs.framework/Versions/A/libobs"
      OUTPUT_VARIABLE OBS_FILE_INFO
      OUTPUT_STRIP_TRAILING_WHITESPACE
    )

    # Determine available architectures in OBS
    set(OBS_HAS_ARM64 FALSE)
    set(OBS_HAS_X86_64 FALSE)

    if(OBS_FILE_INFO MATCHES "arm64")
      set(OBS_HAS_ARM64 TRUE)
    endif()
    if(OBS_FILE_INFO MATCHES "x86_64")
      set(OBS_HAS_X86_64 TRUE)
    endif()

    # Set build architectures based on OBS availability before project configuration
    if(OBS_HAS_ARM64 AND OBS_HAS_X86_64)
      message(STATUS "OBS supports universal binary - will build for both architectures")
      set(CMAKE_OSX_ARCHITECTURES "arm64;x86_64")
    elseif(OBS_HAS_ARM64)
      message(STATUS "OBS is arm64-only - will build for arm64 only")
      set(CMAKE_OSX_ARCHITECTURES "arm64")
    elseif(OBS_HAS_X86_64)
      message(STATUS "OBS is x86_64-only - will build for x86_64 only")
      set(CMAKE_OSX_ARCHITECTURES "x86_64")
    else()
      message(WARNING "Could not determine OBS architecture, falling back to universal")
      set(CMAKE_OSX_ARCHITECTURES "arm64;x86_64")
    endif()
  else()
    # Check if we're building with Xcode (which handles multi-arch via build args)
    if(CMAKE_GENERATOR STREQUAL "Xcode")
      # Let Xcode handle architecture via build arguments
      message(STATUS "Using Xcode generator - architecture will be set by build arguments")
    else()
      # For other generators, detect current architecture
      execute_process(COMMAND uname -m OUTPUT_VARIABLE CURRENT_ARCH OUTPUT_STRIP_TRAILING_WHITESPACE)
      set(CMAKE_OSX_ARCHITECTURES "${CURRENT_ARCH}")
      message(STATUS "Setting macOS architecture to: ${CURRENT_ARCH}")
    endif()
  endif()
endif()

# Set C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Plugin configuration
set(PLUGIN_NAME "obs-syphon-server")
set(PLUGIN_VERSION "1.0.0")

# Configure plugin support definitions
configure_file(src/plugin-support.c.in src/plugin-support.c @ONLY)

# Create the plugin target
add_library(${PLUGIN_NAME} MODULE)

# Add sources
target_sources(${PLUGIN_NAME} PRIVATE src/plugin-main.c ${CMAKE_BINARY_DIR}/src/plugin-support.c)

# Add source directory to include path
target_include_directories(${PLUGIN_NAME} PRIVATE src)

# Find OBS Studio
find_package(PkgConfig QUIET)
if(PKG_CONFIG_FOUND)
  pkg_check_modules(OBS QUIET obs)
endif()

# Check for system OBS installation (macOS app bundle)
if(NOT OBS_FOUND AND APPLE)
  set(OBS_APP_PATH "/Applications/OBS.app/Contents")
  if(EXISTS "${OBS_APP_PATH}/Frameworks/libobs.framework")
    message(STATUS "Found system OBS installation at ${OBS_APP_PATH}")

    # Use system OBS headers from submodule but system libraries
    set(OBS_STUDIO_PATH "${CMAKE_CURRENT_SOURCE_DIR}/deps/obs-studio")
    if(EXISTS "${OBS_STUDIO_PATH}/libobs/obs.h")
      # Add src directory first so obsconfig.h can be found
      target_include_directories(${PLUGIN_NAME} BEFORE PRIVATE "src")
      target_include_directories(${PLUGIN_NAME} PRIVATE "${OBS_STUDIO_PATH}/libobs")

      # Link against system OBS libraries  
      target_link_libraries(
        ${PLUGIN_NAME}
        PRIVATE
          "${OBS_APP_PATH}/Frameworks/libobs.framework/Versions/A/libobs"
          "${OBS_APP_PATH}/Frameworks/obs-frontend-api.dylib"
      )

      # Set rpath for OBS libraries
      set_target_properties(${PLUGIN_NAME} PROPERTIES LINK_FLAGS "-rpath ${OBS_APP_PATH}/Frameworks")

      target_compile_definitions(
        ${PLUGIN_NAME}
        PRIVATE PLUGIN_NAME_STR="${PLUGIN_NAME}" PLUGIN_VERSION_STR="${PLUGIN_VERSION}"
      )

      set(OBS_FOUND TRUE)
    endif()
  endif()
endif()

# If system OBS not found, look for OBS submodule build
if(NOT OBS_FOUND)
  set(OBS_STUDIO_PATH "${CMAKE_CURRENT_SOURCE_DIR}/deps/obs-studio")
  if(EXISTS "${OBS_STUDIO_PATH}/libobs/obs.h")
    message(STATUS "Using OBS Studio headers from submodule")

    # Try to find the built OBS library (check multiple possible paths including Xcode output)
    find_library(
      LIBOBS_LIBRARY
      NAMES obs libobs
      PATHS
        "${OBS_STUDIO_PATH}/build/libobs/RelWithDebInfo"
        "${OBS_STUDIO_PATH}/build/libobs/Debug"
        "${OBS_STUDIO_PATH}/build/libobs/Release"
        "${OBS_STUDIO_PATH}/build/libobs"
      NO_DEFAULT_PATH
    )

    if(LIBOBS_LIBRARY)
      message(STATUS "Found built OBS library: ${LIBOBS_LIBRARY}")
      target_link_libraries(${PLUGIN_NAME} PRIVATE ${LIBOBS_LIBRARY})

      target_include_directories(${PLUGIN_NAME} BEFORE PRIVATE "src")
      target_include_directories(${PLUGIN_NAME} PRIVATE "${OBS_STUDIO_PATH}/libobs")

      target_compile_definitions(
        ${PLUGIN_NAME}
        PRIVATE PLUGIN_NAME_STR="${PLUGIN_NAME}" PLUGIN_VERSION_STR="${PLUGIN_VERSION}"
      )

      set(OBS_FOUND TRUE)
    endif()
  else()
    message(
      FATAL_ERROR
      "Could not find OBS Studio headers. Please install OBS Studio development files or run setup.sh"
    )
  endif()
else()
  target_include_directories(${PLUGIN_NAME} PRIVATE ${OBS_INCLUDE_DIRS})
  target_link_libraries(${PLUGIN_NAME} PRIVATE ${OBS_LIBRARIES})
endif()

# macOS-specific configuration for Syphon support
if(APPLE)
  # Add Objective-C compilation flags
  target_compile_options(${PLUGIN_NAME} PRIVATE -fobjc-arc)

  # Silence OpenGL deprecation warnings (OpenGL is deprecated on macOS but still used by Syphon)
  target_compile_definitions(${PLUGIN_NAME} PRIVATE GL_SILENCE_DEPRECATION)

  # Add Objective-C sources for Syphon (main output only - filter disabled due to symbol conflicts)
  target_sources(
    ${PLUGIN_NAME}
    PRIVATE src/syphon_common.hpp src/syphon_common.mm src/syphon_output.mm src/syphon_main_server.mm
  )

  # Use pre-built Syphon framework
  set(SYPHON_FRAMEWORK_PATH "${CMAKE_CURRENT_SOURCE_DIR}/deps/Syphon-Framework")
  set(SYPHON_FRAMEWORK_BUILD_PATH "${SYPHON_FRAMEWORK_PATH}/build/Release/Syphon.framework")

  if(EXISTS "${SYPHON_FRAMEWORK_BUILD_PATH}")
    message(STATUS "Using pre-built Syphon framework")

    # Add the framework headers with highest priority (BEFORE SYSTEM)
    target_include_directories(${PLUGIN_NAME} BEFORE PRIVATE "${SYPHON_FRAMEWORK_BUILD_PATH}/Headers")
    target_include_directories(${PLUGIN_NAME} BEFORE PRIVATE "${SYPHON_FRAMEWORK_PATH}")

    # Link the pre-built framework
    target_link_libraries(${PLUGIN_NAME} PRIVATE "${SYPHON_FRAMEWORK_BUILD_PATH}")

    # Explicitly exclude system Syphon framework
    target_compile_options(${PLUGIN_NAME} PRIVATE -iframework "${SYPHON_FRAMEWORK_BUILD_PATH}/..")
    # Link required Apple frameworks for Syphon
    find_library(COCOA_FRAMEWORK Cocoa)
    find_library(OPENGL_FRAMEWORK OpenGL)
    find_library(IOSURFACE_FRAMEWORK IOSurface)
    find_library(METAL_FRAMEWORK Metal)
    find_library(METALKIT_FRAMEWORK MetalKit)

    target_link_libraries(
      ${PLUGIN_NAME}
      PRIVATE ${COCOA_FRAMEWORK} ${OPENGL_FRAMEWORK} ${IOSURFACE_FRAMEWORK} ${METAL_FRAMEWORK} ${METALKIT_FRAMEWORK}
    )

    # Compile options to reduce symbol visibility
    target_compile_options(${PLUGIN_NAME} PRIVATE -fvisibility=hidden -fvisibility-inlines-hidden)

    message(STATUS "Main Syphon output configured (filter disabled to avoid conflicts)")
  else()
    message(FATAL_ERROR "Could not find pre-built Syphon framework at ${SYPHON_FRAMEWORK_BUILD_PATH}")
  endif()

  # Ensure proper compilation of Objective-C++ files
  set_source_files_properties(
    src/syphon_common.mm
    src/syphon_output.mm
    PROPERTIES COMPILE_FLAGS "-fobjc-arc -x objective-c++"
  )

  # Set plugin bundle properties
  set_target_properties(
    ${PLUGIN_NAME}
    PROPERTIES BUNDLE TRUE BUNDLE_EXTENSION "plugin" OUTPUT_NAME ${PLUGIN_NAME}
  )
endif()

# Set output directory
set_target_properties(
  ${PLUGIN_NAME}
  PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin" LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)

# Install target - deploy to user plugins directory
if(APPLE)
  # Get the user's home directory
  execute_process(COMMAND whoami OUTPUT_VARIABLE USERNAME OUTPUT_STRIP_TRAILING_WHITESPACE)

  set(OBS_PLUGINS_DIR "/Users/${USERNAME}/Library/Application Support/obs-studio/plugins")

  # Install from the configuration-specific directory (RelWithDebInfo, Debug, etc.)
  install(
    DIRECTORY "$<TARGET_BUNDLE_DIR:${PLUGIN_NAME}>"
    DESTINATION "${OBS_PLUGINS_DIR}"
    USE_SOURCE_PERMISSIONS
  )

  # Custom target for easy installation
  add_custom_target(
    install-plugin
    COMMAND ${CMAKE_COMMAND} --build ${CMAKE_BINARY_DIR} --target install
    DEPENDS ${PLUGIN_NAME}
    COMMENT "Installing ${PLUGIN_NAME} to OBS Studio user plugins directory"
  )

  # Custom target to uninstall the plugin
  add_custom_target(
    uninstall-plugin
    COMMAND rm -rf "${OBS_PLUGINS_DIR}/${PLUGIN_NAME}.plugin"
    COMMENT "Removing ${PLUGIN_NAME} from OBS Studio user plugins directory"
  )

  message(STATUS "Plugin will be installed to: ${OBS_PLUGINS_DIR}")
endif()
