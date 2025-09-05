# Development Guide

## Build System Overview

This project uses a templating system to keep personal SmartThings identifiers out of version control while enabling easy building and deployment.

### Files Created/Modified

#### Configuration Files
- `local-config.example.json` - Template configuration with placeholder values (committed to repo)
- `local-config.json` - Your personal configuration (gitignored)

#### Build System
- `build.ps1` - PowerShell build script that handles templating and deployment
- `.gitignore` - Updated to exclude personal config and build artifacts

#### Templated Files
All files now use placeholder values that get replaced during build:

**Placeholders Used:**
- `{{NAMESPACE}}` - Replaces your SmartThings namespace (e.g., "perfectlife6617")
- `{{PROFILE_ID}}` - Replaces your profile ID (e.g., "ed3e53a1-ef5e-4d7f-86fa-cd30da196025")
- `{{PRESENTATION_ID}}` - Replaces your presentation ID (same as profile ID in this case)

**Files Modified:**
- `config.yml` - Capability references and presentation ID
- `profiles/pitboss-grill-profile.yml` - Profile ID and capability references
- `src/custom_capabilities.lua` - Namespace references in comments and code
- `capabilities/{{NAMESPACE}}.*.json` - All capability definition files (renamed and content updated)
- `capabilities/{{NAMESPACE}}.*.yaml` - All capability presentation files (renamed and content updated)

### Usage

#### First Time Setup
```powershell
# Copy example config
Copy-Item "local-config.example.json" "local-config.json"

# Edit local-config.json with your personal values:
# - namespace: Your SmartThings namespace
# - profileId: Your profile ID
# - presentationId: Your presentation ID  
# - smartthings.channelId: Your channel ID
# - smartthings.hubId: Your hub ID
```

#### Building and Deployment
```powershell
# Normal build and deploy
.\build.ps1

# Package only (no deployment)
.\build.ps1 -PackageOnly

# Test with example config
.\build.ps1 -ConfigFile "local-config.example.json"

# Non-interactive CI-friendly package-only build
.\build.ps1 -PackageOnly -AutoRestore

# Get help
.\build.ps1 -Help

# Smart version management examples
.\build.ps1 -SmartVersion               # Update versions for modified files + build + deploy
.\build.ps1 -SmartVersion -VersionOnly  # Only update versions (no build/deploy)
.\build.ps1 -BumpAllVersions            # Bump all files to today's version
.\build.ps1 -CheckVersions              # Validate version consistency
```

#### CLI Alias Cheat-sheet

Short aliases for convenience in scripts and CI:

- `-c` => `-ConfigFile`
- `-p` => `-PackageOnly`
- `-u` => `-UpdateCapabilities`
- `-r` => `-RemoveDriver`
- `-m` => `-ManualWork`
- `-a`, `-y`, `-NonInteractive`, `-Force` => `-AutoRestore`
- `-h` => `-Help`
- `-v` => `-Verbose`
- `-s` => `-SmartVersion`
- `-b` => `-BumpAllVersions`
- `-o` => `-VersionOnly`
- `-k` => `-CheckVersions`

### How It Works

1. **Build Process**:
   - Reads your personal configuration from `local-config.json`
   - Temporarily replaces all `{{PLACEHOLDER}}` values with your real values
   - Renames capability files from `{{NAMESPACE}}.*` to `your-namespace.*`
   - Runs `smartthings edge:drivers:package .\`
   - Optionally runs `smartthings edge:drivers:install -H {hubId} -C {channelId} {driverId}`
   - Restores all files back to placeholder versions
   - Renames capability files back to `{{NAMESPACE}}.*`

2. **Safety Features**:
   - Automatic detection of placeholder values (won't deploy if found)
   - Complete restoration of original files even if build fails
      - AutoRestore mode for CI/non-interactive runs (use `-AutoRestore`, `-a`, or `-y`)
   - Comprehensive error handling

3. **Version Control**:
   - Repository contains only placeholder values
   - Personal identifiers never committed
   - Clean diffs and collaboration-friendly

### Benefits

- **Privacy**: Personal SmartThings identifiers stay out of version control
- **Collaboration**: Multiple developers can work on the same codebase
- **Automation**: One-command build and deployment
- **Safety**: Automatic restoration prevents accidental commits of personal data
- **Flexibility**: Support for different configurations and deployment targets

### Troubleshooting

If the build fails:
1. Files are automatically restored to placeholder versions
2. Check that `local-config.json` exists and has valid JSON
3. Verify all required fields are present in your config
4. Ensure SmartThings CLI is installed and authenticated
5. Run with `-AutoRestore` for CI-friendly automatic restoration

### Adding New Files

When adding new files that contain personal identifiers:
1. Use placeholder values (`{{NAMESPACE}}`, `{{PROFILE_ID}}`, etc.)
2. Add the file to the `$filesToProcess` array in `build.ps1`
3. Test with `-AutoRestore` to ensure non-interactive replacement in CI
