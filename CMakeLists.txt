cmake_minimum_required(VERSION 3.16)

project(obs-syphon-server VERSION 1.0.0 LANGUAGES C CXX)

# For macOS, build for current architecture
if(APPLE)
    execute_process(COMMAND uname -m OUTPUT_VARIABLE CURRENT_ARCH OUTPUT_STRIP_TRAILING_WHITESPACE)
    set(CMAKE_OSX_ARCHITECTURES "${CURRENT_ARCH}")
    message(STATUS "Setting macOS architecture to: ${CURRENT_ARCH}")
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
target_sources(${PLUGIN_NAME} PRIVATE
    src/plugin-main.c
    ${CMAKE_BINARY_DIR}/src/plugin-support.c
)

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
            target_include_directories(${PLUGIN_NAME} PRIVATE
                "${OBS_STUDIO_PATH}/libobs"
                "src"
            )
            
            # Link against system OBS libraries  
            target_link_libraries(${PLUGIN_NAME} PRIVATE
                "${OBS_APP_PATH}/Frameworks/libobs.framework/Versions/A/libobs"
                "${OBS_APP_PATH}/Frameworks/obs-frontend-api.dylib"
            )
            
            # Set rpath for OBS libraries
            set_target_properties(${PLUGIN_NAME} PROPERTIES
                LINK_FLAGS "-rpath ${OBS_APP_PATH}/Frameworks"
            )
            
            target_compile_definitions(${PLUGIN_NAME} PRIVATE
                PLUGIN_NAME_STR="${PLUGIN_NAME}"
                PLUGIN_VERSION_STR="${PLUGIN_VERSION}"
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
        
        # Try to find the built OBS library
        find_library(LIBOBS_LIBRARY 
            NAMES obs libobs
            PATHS "${OBS_STUDIO_PATH}/build/libobs/Debug"
            NO_DEFAULT_PATH
        )
        
        if(LIBOBS_LIBRARY)
            message(STATUS "Found built OBS library: ${LIBOBS_LIBRARY}")
            target_link_libraries(${PLUGIN_NAME} PRIVATE ${LIBOBS_LIBRARY})
        endif()
        
        target_include_directories(${PLUGIN_NAME} PRIVATE
            "${OBS_STUDIO_PATH}/libobs"
            "src"
        )
        
        target_compile_definitions(${PLUGIN_NAME} PRIVATE
            PLUGIN_NAME_STR="${PLUGIN_NAME}"
            PLUGIN_VERSION_STR="${PLUGIN_VERSION}"
        )
    else()
        message(FATAL_ERROR "Could not find OBS Studio headers. Please install OBS Studio development files or run setup.sh")
    endif()
else()
    target_include_directories(${PLUGIN_NAME} PRIVATE ${OBS_INCLUDE_DIRS})
    target_link_libraries(${PLUGIN_NAME} PRIVATE ${OBS_LIBRARIES})
endif()

# macOS-specific configuration for Syphon support
if(APPLE)
    # Get current architecture
    execute_process(COMMAND uname -m OUTPUT_VARIABLE CURRENT_ARCH OUTPUT_STRIP_TRAILING_WHITESPACE)
    message(STATUS "Building for architecture: ${CURRENT_ARCH}")
    
    # Set architecture for current build
    set(CMAKE_OSX_ARCHITECTURES ${CURRENT_ARCH})
    
    # Add Objective-C compilation flags
    target_compile_options(${PLUGIN_NAME} PRIVATE 
        -fobjc-arc
    )
    
    # Add Objective-C sources for Syphon (main output only - filter disabled due to symbol conflicts)
    target_sources(${PLUGIN_NAME} PRIVATE
        src/syphon_common.hpp
        src/syphon_common.mm
        src/syphon_output.mm
        src/syphon_main_server.mm
    )
    
    # Build Syphon from source for main output (filter disabled to avoid crashes)
    set(SYPHON_FRAMEWORK_PATH "${CMAKE_CURRENT_SOURCE_DIR}/deps/Syphon-Framework")
    if(EXISTS "${SYPHON_FRAMEWORK_PATH}/CMakeLists.txt")
        message(STATUS "Building Syphon from source using CMake for ${CURRENT_ARCH}")
        
        # Include ExternalProject for building Syphon
        include(ExternalProject)
        
        # Set the Syphon build directory
        set(SYPHON_BUILD_DIR "${CMAKE_CURRENT_BINARY_DIR}/syphon-build")
        
        # Configure and build Syphon using CMake
        ExternalProject_Add(SyphonFramework
            SOURCE_DIR "${SYPHON_FRAMEWORK_PATH}"
            BINARY_DIR "${SYPHON_BUILD_DIR}"
            CMAKE_ARGS
                -DCMAKE_OSX_ARCHITECTURES=${CURRENT_ARCH}
                -DCMAKE_INSTALL_PREFIX=${SYPHON_BUILD_DIR}
                -DCMAKE_BUILD_TYPE=Release
            BUILD_COMMAND ${CMAKE_COMMAND} --build . --config Release
            INSTALL_COMMAND ${CMAKE_COMMAND} --build . --target install
        )
        
        # Use local headers for compilation and link static library
        add_dependencies(${PLUGIN_NAME} SyphonFramework)
        target_include_directories(${PLUGIN_NAME} SYSTEM BEFORE PRIVATE "${SYPHON_BUILD_DIR}/include")
        target_link_libraries(${PLUGIN_NAME} PRIVATE "${SYPHON_BUILD_DIR}/lib/libSyphon.a")
        
        # Link required Apple frameworks for Syphon
        find_library(COCOA_FRAMEWORK Cocoa)
        find_library(OPENGL_FRAMEWORK OpenGL)
        find_library(IOSURFACE_FRAMEWORK IOSurface)
        find_library(METAL_FRAMEWORK Metal)
        find_library(METALKIT_FRAMEWORK MetalKit)
        
        target_link_libraries(${PLUGIN_NAME} PRIVATE
            ${COCOA_FRAMEWORK}
            ${OPENGL_FRAMEWORK}
            ${IOSURFACE_FRAMEWORK}
            ${METAL_FRAMEWORK}
            ${METALKIT_FRAMEWORK}
        )
        
        # Compile options to reduce symbol visibility
        target_compile_options(${PLUGIN_NAME} PRIVATE
            -fvisibility=hidden
            -fvisibility-inlines-hidden
        )
        
        message(STATUS "Main Syphon output configured (filter disabled to avoid conflicts)")
    else()
        message(FATAL_ERROR "Could not find Syphon framework source at ${SYPHON_FRAMEWORK_PATH}")
    endif()
    
    # Ensure proper compilation of Objective-C++ files
    set_source_files_properties(
        src/syphon_common.mm
        src/syphon_output.mm
        PROPERTIES
        COMPILE_FLAGS "-fobjc-arc -x objective-c++"
    )
    
    # Set plugin bundle properties
    set_target_properties(${PLUGIN_NAME} PROPERTIES
        BUNDLE TRUE
        BUNDLE_EXTENSION "plugin"
        OUTPUT_NAME ${PLUGIN_NAME}
    )
endif()

# Set output directory
set_target_properties(${PLUGIN_NAME} PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)

# Install target - deploy to user plugins directory
if(APPLE)
    # Get the user's home directory
    execute_process(
        COMMAND whoami
        OUTPUT_VARIABLE USERNAME
        OUTPUT_STRIP_TRAILING_WHITESPACE
    )
    
    set(OBS_PLUGINS_DIR "/Users/${USERNAME}/Library/Application Support/obs-studio/plugins")
    
    install(DIRECTORY "${CMAKE_BINARY_DIR}/bin/${PLUGIN_NAME}.plugin"
        DESTINATION "${OBS_PLUGINS_DIR}"
        USE_SOURCE_PERMISSIONS
    )
    
    # Custom target for easy installation
    add_custom_target(install-plugin
        COMMAND ${CMAKE_COMMAND} --build ${CMAKE_BINARY_DIR} --target install
        DEPENDS ${PLUGIN_NAME}
        COMMENT "Installing ${PLUGIN_NAME} to OBS Studio user plugins directory"
    )
    
    # Custom target to uninstall the plugin
    add_custom_target(uninstall-plugin
        COMMAND rm -rf "${OBS_PLUGINS_DIR}/${PLUGIN_NAME}.plugin"
        COMMENT "Removing ${PLUGIN_NAME} from OBS Studio user plugins directory"
    )
    
    message(STATUS "Plugin will be installed to: ${OBS_PLUGINS_DIR}")
endif()
