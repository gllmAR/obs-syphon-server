# CI Configuration for OBS Syphon Server Plugin

## Platform Support

**macOS Only**: This plugin uses the Syphon framework which is exclusive to macOS. Linux and Windows builds have been disabled in CI.

## CI Workflow

The GitHub Actions workflow (`build-project.yaml`) includes:

1. **macOS Build** (macOS 15, Xcode 16.1)
   - Builds Syphon framework from source
   - Compiles the OBS plugin with Syphon integration
   - Creates universal binary (arm64 + x86_64)
   - Validates build with automated tests

2. **Disabled Builds**
   - Ubuntu: Commented out (Syphon not available)
   - Windows: Commented out (Syphon not available)

## Dependencies

The CI installs these Homebrew packages:
- `ccache` - Build cache for faster compilation
- `coreutils` - GNU core utilities
- `cmake` - Build system
- `jq` - JSON processor
- `xcbeautify` - Xcode output formatter
- `git` - Version control
- `ninja` - Build system
- `pkg-config` - Package configuration

## Build Process

1. **Setup Environment**
   - Uses Xcode 16.1 for compatibility
   - Configures code signing (if enabled)
   - Sets up ccache for faster builds

2. **Build Syphon Framework**
   - Checks if framework already built
   - Builds from source using `xcodebuild`
   - Creates universal binary framework

3. **Build Plugin**
   - Uses CMake with `macos-ci` preset
   - Links against pre-built Syphon framework
   - Creates plugin bundle

4. **Validate Build**
   - Runs automated tests to verify:
     - Syphon framework presence
     - Plugin binary existence
     - Proper linking
     - Architecture support

## Manual Testing

To test the CI build manually:

1. Use GitHub Actions "Dispatch" workflow
2. Select "build" from the dropdown
3. Monitor the workflow run for any issues

## Local Development

For local development setup, run:
```bash
./setup.sh  # Set up dependencies
./build.sh  # Build plugin
```

The plugin will be installed to:
`~/Library/Application Support/obs-studio/plugins/`

## Troubleshooting

Common issues:
- **Syphon build fails**: Check Xcode version and ensure submodules are initialized
- **Link errors**: Verify Syphon framework was built successfully  
- **Architecture issues**: Ensure universal binary build is enabled
- **Code signing**: Only enabled for release builds, not required for testing
