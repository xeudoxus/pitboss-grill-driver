#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Build and deploy Pit Boss Grill SmartThings Edge Driver

.DESCRIPTION
    This script replaces placeholder values with personal configuration,
    builds the SmartThings Edge driver package, optionally deploys it,
    and then restores placeholder values for version control.

.NOTES
    File Name      : build.ps1
    Author         : xeudoxus
    Version        : 1.0.1
    Created        : 2025
    Repository     : https://github.com/xeudoxus/pitboss-grill-driver
    License        : Apache License 2.0

    SmartThings Edge Driver for Pit Boss WiFi Grills
    Provides comprehensive control and monitoring without cloud dependency

    Requirements:
    - SmartThings CLI installed and configured (tested with @smartthings/cli/1.10.5)
    - Windows PowerShell 5.1 or PowerShell 7+ (cross-platform support)
    - Local network access to Pit Boss grill
    - Node.js (tested with node-v18.5.0)

    For installation and usage instructions, see:
    https://github.com/xeudoxus/pitboss-grill-driver/wiki

.PARAMETER ConfigFile
    Path to the configuration JSON file (default: "local-config.json")

.PARAMETER PackageOnly
    Only package the driver, skip deployment

.PARAMETER UpdateCapabilities
    Create or update SmartThings capabilities and presentation (only needed once)

.PARAMETER RemoveDriver
    Remove driver from hub, unassign from channel, and delete all capabilities (complete cleanup)

.PARAMETER ManualWork
    Replace placeholders with real values, pause for manual work, then restore placeholders when finished

.PARAMETER AutoRestore
    When set, automatically restore dirty files to placeholder versions without prompting (CI-friendly)

.PARAMETER Help
    Show this help message

.PARAMETER Verbose
    Show detailed [SUCCESS] output for placeholder/capability file changes

.PARAMETER SmartVersion
    Intelligently update versions for modified files based on Git changes, then build and deploy

.PARAMETER BumpAllVersions
    Update all project files to today's version (major release), then exit without building

.PARAMETER VersionOnly
    Used with SmartVersion to only update versions without building or deploying

.PARAMETER CheckVersions
    Validate version consistency and readiness for release, then exit without building

# Example usage:
#
#   .\build.ps1
#   Build and deploy using local-config.json
#
#   .\build.ps1 -ConfigFile "local-config.example.json"
#   Build using example configuration (won't deploy due to placeholder IDs)
#
#   .\build.ps1 -PackageOnly
#   Only build the package, skip deployment
#
#   .\build.ps1 -UpdateCapabilities
#   Update/create capabilities and presentation, then build and deploy
#
#   .\build.ps1 -UpdateCapabilities -PackageOnly
#   Update/create capabilities and presentation, then only build the package
#
#   .\build.ps1 -RemoveDriver
#   Remove driver from hub, unassign from channel, and delete all capabilities
#
#   .\build.ps1 -ManualWork
#   Replace placeholders, pause for manual work, then restore placeholders
#
#   .\build.ps1 -Verbose
#   Show detailed [SUCCESS] output for placeholder/capability file changes
#
#   .\build.ps1 -SmartVersion
#   Intelligently update versions for modified files, then build and deploy
#
#   .\build.ps1 -SmartVersion -VersionOnly
#   Only update versions for modified files (no build/deploy)
#
#   .\build.ps1 -BumpAllVersions
#   Update all files to today's version (major release)
#
#   .\build.ps1 -CheckVersions
#   Validate version consistency and readiness for release
#>

param(
    [Alias('c')][string]$ConfigFile = "local-config.json",
    [Alias('p')][switch]$PackageOnly,
    [Alias('u')][switch]$UpdateCapabilities,
    [Alias('r')][switch]$RemoveDriver,
    [Alias('m')][switch]$ManualWork,
    [Alias('a','y','NonInteractive','Force')][switch]$AutoRestore,
    [Alias('h')][switch]$Help,
    [Alias('v')][switch]$Verbose,
    [Alias('s')][switch]$SmartVersion,
    [Alias('b')][switch]$BumpAllVersions,
    [Alias('o')][switch]$VersionOnly,
    [Alias('k')][switch]$CheckVersions
)

# Set UTF-8 encoding for proper emoji and Unicode character display in console only
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Clear global dirty file tracking at the start of every run
$global:DetectedDirtyFiles = @()
$global:DetectedWrongNamedCapabilities = @()

# Define common constants used throughout the script
$script:DateFormat = "yyyy.M.d"
$script:PlaceholderTokens = @{
    Namespace = '{{NAMESPACE}}'
    ProfileId = '{{PROFILE_ID}}'
    PresentationId = '{{PRESENTATION_ID}}'
}
$script:CommonPaths = @{
    Capabilities = "capabilities"
    Src = "src"
    Profiles = "profiles"
}
$script:StandardFiles = @(
    "config.yml",
    "profiles\pitboss-grill-profile.yml", 
    "src\custom_capabilities.lua"
)

# Show help if requested
if ($Help) {
    $helpData = @{
        Title = "Pit Boss Grill SmartThings Edge Driver - Build Script"
        Description = "  This script replaces placeholder values with personal configuration,`n  builds the SmartThings Edge driver package, optionally deploys it,`n  and then restores placeholder values for version control."
        Syntax = "  .\build.ps1 [[-ConfigFile] <string>] [-PackageOnly] [-UpdateCapabilities]`n               [-RemoveDriver] [-ManualWork] [-AutoRestore] [-Help] [-Verbose]`n               [-SmartVersion] [-BumpAllVersions] [-VersionOnly] [-CheckVersions]"
        Parameters = @(
            "-ConfigFile <string>     Path to configuration JSON file (default: local-config.json)",
            "-PackageOnly      (-p)   Only package the driver, skip deployment",
            "-UpdateCapabilities (-u) Create or update SmartThings capabilities and presentation",
            "-RemoveDriver     (-r)   Remove driver, unassign from channel, delete capabilities",
            "-ManualWork       (-m)   Replace placeholders, pause for manual work, then restore",
            "-AutoRestore   (-a,-y)   Auto-restore dirty files without prompting (CI-friendly)",
            "-Help             (-h)   Show this help message",
            "-Verbose          (-v)   Show detailed [SUCCESS] output for file changes",
            "-SmartVersion     (-s)   Intelligently update versions for modified files",
            "-BumpAllVersions  (-b)   Update all files to today's version (major release)",
            "-VersionOnly      (-o)   Used with SmartVersion to only update versions",
            "-CheckVersions    (-k)   Validate version consistency and readiness"
        )
        Examples = @(
            @{ Command = ".\build.ps1"; Description = "Build and deploy using local-config.json" },
            @{ Command = ".\build.ps1 -ConfigFile `"local-config.example.json`""; Description = "Build using example configuration (won't deploy due to placeholder IDs)" },
            @{ Command = ".\build.ps1 -PackageOnly"; Description = "Only build the package, skip deployment" },
            @{ Command = ".\build.ps1 -UpdateCapabilities"; Description = "Update/create capabilities and presentation, then build and deploy" },
            @{ Command = ".\build.ps1 -SmartVersion"; Description = "Intelligently update versions for modified files, then build and deploy" },
            @{ Command = ".\build.ps1 -SmartVersion -VersionOnly"; Description = "Only update versions for modified files (no build/deploy)" },
            @{ Command = ".\build.ps1 -s -o -v"; Description = "SmartVersion with VersionOnly and Verbose output (using shortcodes)" },
            @{ Command = ".\build.ps1 -BumpAllVersions"; Description = "Update all files to today's version (major release)" },
            @{ Command = ".\build.ps1 -b"; Description = "Same as -BumpAllVersions using shortcode" },
            @{ Command = ".\build.ps1 -CheckVersions"; Description = "Validate version consistency and readiness for release" },
            @{ Command = ".\build.ps1 -RemoveDriver"; Description = "Remove driver from hub, unassign from channel, and delete all capabilities" },
            @{ Command = ".\build.ps1 -ManualWork"; Description = "Replace placeholders, pause for manual work, then restore placeholders" }
        )
    }

    Write-Host ""
    Write-Host $helpData.Title -ForegroundColor Cyan
    Write-Host ("=" * $helpData.Title.Length) -ForegroundColor Cyan
    Write-Host ""
    Write-Host "DESCRIPTION:" -ForegroundColor Yellow
    Write-Host $helpData.Description
    Write-Host ""
    Write-Host "SYNTAX:" -ForegroundColor Yellow
    Write-Host $helpData.Syntax
    Write-Host ""
    Write-Host "PARAMETERS:" -ForegroundColor Yellow
    foreach ($param in $helpData.Parameters) {
        Write-Host "  $param"
    }
    Write-Host ""
    Write-Host "EXAMPLES:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $helpData.Examples.Count; $i++) {
        $example = $helpData.Examples[$i]
        Write-Host "  $($example.Command)"
        Write-Host "    $($example.Description)"
        if ($i -lt $helpData.Examples.Count - 1) { Write-Host "" }
    }
    Write-Host ""
    exit 0
}

# Color output functions
function Write-Success {
    param($Message, [switch]$Force)
    if ($Force -or $Verbose) {
        Write-Host "[SUCCESS] $Message" -ForegroundColor Green
    }
}
function Write-Info { param($Message) Write-Host "[INFO] $Message" -ForegroundColor Cyan }
function Write-Warning { param($Message) Write-Host "[WARNING] $Message" -ForegroundColor Yellow }
function Write-Error { param($Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }

# Stage 1 Refactor: Exact duplicate code functions
function Save-VersionJson {
    param($VersionData)
    # Create properly formatted JSON manually to avoid PowerShell formatting issues
    $jsonContent = @"
{
  "version": "$($VersionData.version)",
  "lastUpdated": "$($VersionData.lastUpdated)",
  "files": {
"@
    
    $fileEntries = @()
    $VersionData.files.PSObject.Properties | ForEach-Object {
        $fileEntries += "    `"$($_.Name)`": `"$($_.Value)`""
    }
    
    $jsonContent += "`n" + ($fileEntries -join ",`n") + "`n  }`n}"
    $jsonContent | Set-Content "version.json" -NoNewline
}

function Update-PlaceholdersInFile {
    param($FullPath, $Config, [ref]$FilesToRestore, $File)
    # Backup original content
    $originalContent = Get-Content $FullPath -Raw
    $FilesToRestore.Value += @{
        Path = $FullPath
        Content = $originalContent
    }

    # Replace placeholders
    $newContent = $originalContent
    $newContent = $newContent -replace [regex]::Escape($script:PlaceholderTokens.Namespace), $Config.namespace
    $newContent = $newContent -replace [regex]::Escape($script:PlaceholderTokens.ProfileId), $Config.profileId
    $newContent = $newContent -replace [regex]::Escape($script:PlaceholderTokens.PresentationId), $Config.presentationId

    Set-Content $FullPath $newContent -NoNewline
    $relativePath = if ([System.IO.Path]::IsPathRooted($File)) { Split-Path $File -Leaf } else { $File }
    Write-Success "Updated placeholders in $relativePath" -Force:$false
}

# Stage 2 Refactor: Similar patterns with parameter variations
function Restore-PlaceholdersInContent {
    param($Content, $Config)
    $cleanContent = $Content
    $cleanContent = $cleanContent -replace [regex]::Escape($Config.namespace), $script:PlaceholderTokens.Namespace
    $cleanContent = $cleanContent -replace [regex]::Escape($Config.profileId), $script:PlaceholderTokens.ProfileId
    $cleanContent = $cleanContent -replace [regex]::Escape($Config.presentationId), $script:PlaceholderTokens.PresentationId
    return $cleanContent
}

function Restore-FileContent {
    param($FileInfo, $Config, $ErrorLevel = "Warning")
    try {
        # Check if this is a capability file that was renamed
        $currentPath = $FileInfo.Path
        $fileName = Split-Path $currentPath -Leaf

        # If it's a capability file with {{NAMESPACE}} in the path, it may have been renamed
        if ($currentPath -like "*$($script:CommonPaths.Capabilities)*" -and $fileName -like "*$($script:PlaceholderTokens.Namespace)*") {
            # Check if the renamed version exists instead
            $renamedFileName = $fileName -replace [regex]::Escape($script:PlaceholderTokens.Namespace), $Config.namespace
            $renamedPath = Join-Path (Split-Path $currentPath -Parent) $renamedFileName

            if (Test-Path $renamedPath) {
                $currentPath = $renamedPath
            }
        }

        Set-Content $currentPath $FileInfo.Content -NoNewline
        Write-Success "Restored $(Split-Path $FileInfo.Path -Leaf)" -Force:$false
    } catch {
        if ($ErrorLevel -eq "Error") {
            Write-Error "Failed to restore $(Split-Path $FileInfo.Path -Leaf): $($_.Exception.Message)"
        } else {
            Write-Warning "Failed to restore $(Split-Path $FileInfo.Path -Leaf): $($_.Exception.Message)"
        }
    }
}

# Stage 3 Refactor: Standard DRY principles
function Update-FileVersionContent {
    param($FilePath, $NewVersion, $VersionPattern, $ReplacementTemplate, $LogMessage)
    if (Test-Path $FilePath) {
        $content = Get-Content $FilePath -Raw
        $newContent = $content -replace $VersionPattern, ($ReplacementTemplate -f $NewVersion)
        if ($newContent -ne $content) {
            Set-Content -Path $FilePath -Value $newContent -NoNewline
            Write-Success $LogMessage -Force
        }
    }
}

function Get-CapabilityFiles {
    param($Config, [switch]$UseRealNamespace)
    $namespace = if ($UseRealNamespace) { $Config.namespace } else { $script:PlaceholderTokens.Namespace }
    $pattern = "$($script:CommonPaths.Capabilities)\$namespace*"
    return Get-ChildItem $pattern -ErrorAction SilentlyContinue
}

function Get-FilePathsForTracking {
    param($FileName)
    
    $filePatterns = @(
        @{ Pattern = "*.lua"; Template = "$($script:CommonPaths.Src)\{0}" },
        @{ Pattern = "pitboss-grill-profile.yml"; Template = "$($script:CommonPaths.Profiles)\{0}" },
        @{ Pattern = @("config.yml", "README.md"); Template = "{0}" }
    )
    
    foreach ($pattern in $filePatterns) {
        if ($pattern.Pattern -is [array]) {
            if ($FileName -in $pattern.Pattern) {
                return @($pattern.Template -f $FileName)
            }
        } elseif ($FileName -like $pattern.Pattern) {
            return @($pattern.Template -f $FileName)
        }
    }
    return @()
}

function Test-RequiredConfigFields {
    param($Config, $FieldList, $Section = "")
    foreach ($field in $FieldList) {
        $value = if ($Section) { $Config.$Section.$field } else { $Config.$field }
        if (-not $value) {
            $fieldPath = if ($Section) { "$Section.$field" } else { $field }
            Write-Error "Missing required field '$fieldPath' in configuration file"
            return $false
        }
    }
    return $true
}

# Intelligent version management - analyzes files and automatically does the right thing
if ($SmartVersion -and (Test-Path "version.json")) {
    # Define version pattern once for consistent validation
    $versionPattern = '^[0-9]{4}\.[0-9]{1,2}\.[0-9]{1,2}$'
    
    Write-Info "Smart Version Management - Analyzing project state..."

    # Step 1: Get list of all files in version.json (ONLY for the file list)
    try {
        $versionData = Get-Content "version.json" -Raw | ConvertFrom-Json
    }
    catch {
        Write-Warning "Could not read version.json, creating fresh version data"
        $versionData = [PSCustomObject]@{
            files = [PSCustomObject]@{}
            version = (Get-Date).ToString($script:DateFormat)
            lastUpdated = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
        }
        Save-VersionJson $versionData
    }

    Write-Info "Current main version: $($versionData.version)"

    # Step 2: Begin scan/fix loop - check each file's ACTUAL content and mod date
    $anyFileUpdated = $false
    $versionData.files.PSObject.Properties | ForEach-Object {
        $fileName = $_.Name
        $trackedVersion = $_.Value  # We ignore this and trust the file
        
        # Find file path
        $filePaths = Get-FilePathsForTracking $fileName
        $filePath = $filePaths | Where-Object { Test-Path $_ } | Select-Object -First 1
        
        if ($filePath -and (Test-Path $filePath)) {
            $fileModDate = (Get-Item $filePath).LastWriteTime.ToString($script:DateFormat)
            
            # Read actual file version content (trust the file, not version.json)
            $actualFileVersion = $null
            $needsFileContentFix = $false
            
            if ($fileName -like "*.lua") {
                $luaContent = Get-Content $filePath -Raw
                if ($luaContent -match '(?m)^\s*Version:\s*([^\r\n]+)') {
                    $actualFileVersion = $matches[1].Trim()
                } else {
                    # Missing Version field
                    $actualFileVersion = $null
                    $needsFileContentFix = $true
                }
            } elseif ($fileName -like "*.yml") {
                $ymlContent = Get-Content $filePath -Raw
                if ($ymlContent -match '(?m)^# Version:\s*([^\r\n]+)') {
                    $actualFileVersion = $matches[1].Trim()
                } else {
                    # Missing Version comment
                    $actualFileVersion = $null
                    $needsFileContentFix = $true
                }
            } else {
                # For files without version fields, use mod date as "actual version"
                $actualFileVersion = $fileModDate
            }
            
            # Compare file's internal version to its modification date
            if ($actualFileVersion -ne $fileModDate -or $needsFileContentFix) {
                Write-Success "Updating $fileName → internal version '$actualFileVersion' to match file date '$fileModDate'" -Force
                
                # Update file's internal version content to match mod date
                if ($fileName -like "*.lua") {
                    $luaContent = Get-Content $filePath -Raw
                    if ($luaContent -match '(?m)^\s*Version:\s*([^\r\n]+)') {
                        $luaContent = $luaContent -replace '(?m)^\s*Version:\s*[^\r\n]+', "  Version: $fileModDate"
                    } else {
                        # Add Version field if missing (this shouldn't happen normally)
                        $luaContent = "  Version: $fileModDate`n" + $luaContent
                    }
                    
                    # Note: Log message version handling removed - log message no longer contains version
                    
                    Set-Content $filePath -Value $luaContent -NoNewline
                } elseif ($fileName -like "*.yml") {
                    $ymlContent = Get-Content $filePath -Raw
                    if ($ymlContent -match '(?m)^# Version:\s*([^\r\n]+)') {
                        $ymlContent = $ymlContent -replace '(?m)^# Version:\s*[^\r\n]+', "# Version: $fileModDate"
                    } else {
                        # Add Version comment if missing
                        $ymlContent = "# Version: $fileModDate`n" + $ymlContent
                    }
                    Set-Content $filePath -Value $ymlContent -NoNewline
                }
                
                # Update version.json tracking to match what we just fixed
                $versionData.files.$fileName = $fileModDate
                $anyFileUpdated = $true
                
            } else {
                # File's internal version matches its mod date
                # Check if version.json tracking is correct
                if ($trackedVersion -ne $fileModDate) {
                    Write-Success "Correcting tracking for $fileName → was '$trackedVersion', now '$fileModDate'" -Force
                    $versionData.files.$fileName = $fileModDate
                    $anyFileUpdated = $true
                } else {
                    if ($Verbose) {
                        Write-Success "Current $fileName → $fileModDate (file and tracking match)" -Force
                    }
                }
            }
        }
    }

    # Calculate new main version (filter out invalid versions)
    $validVersions = $versionData.files.PSObject.Properties.Value | Where-Object { 
        try { 
            # Skip empty, null, or whitespace values
            if ([string]::IsNullOrWhiteSpace($_)) { return $false }
            # Additional validation for malformed versions
            if ($_ -match $versionPattern) {
                [version]"$_.0" | Out-Null
                $true 
            } else {
                $false
            }
        } catch { 
            $false 
        } 
    }
    
    if ($validVersions.Count -gt 0) {
        # Extra safety check before sorting
        $safeVersions = $validVersions | Where-Object { 
            -not [string]::IsNullOrWhiteSpace($_) -and $_ -match $versionPattern 
        }
        if ($safeVersions.Count -gt 0) {
            $newMainVersion = $safeVersions | Sort-Object { [version]"$_.0" } | Select-Object -Last 1
        } else {
            $newMainVersion = $todayVersion
        }
    } else {
        $newMainVersion = $todayVersion
    }

    $oldMainVersion = $versionData.version
    $versionData.version = $newMainVersion

    Write-Info "Main version: $oldMainVersion → $newMainVersion"

    # Apply changes to version.json and config.yml (unless CheckVersions is specified)
    if ($anyFileUpdated -or $oldMainVersion -ne $newMainVersion) {
        if ($CheckVersions) {
            # Check-only mode: just report what would be done, don't modify files
            Write-Info "CHECK MODE - Changes detected but not applied due to -CheckVersions flag:"
            if ($anyFileUpdated) {
                Write-Warning "  - File version tracking would be updated"
            }
            if ($oldMainVersion -ne $newMainVersion) {
                Write-Warning "  - Main version would change: $oldMainVersion → $newMainVersion"
            }
            Write-Warning "  - version.json and config.yml would be updated"
            Write-Warning "  - File content version fields would be synchronized"
        } else {
            # Apply changes mode (both VersionOnly and normal SmartVersion apply changes)
            $versionData.lastUpdated = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
            
            Save-VersionJson $versionData
            
            # Update config.yml with new main version - use multiline mode for proper line start matching
            $configContent = Get-Content "config.yml" -Raw
            $configContent = $configContent -replace '(?m)^Version:\s*"[^"]*"', "Version: `"$newMainVersion`""
            Set-Content "config.yml" -Value $configContent -NoNewline
            
            # ONLY update file content if version fields don't match their file's mod date
            # This is separate from tracking updates - we're fixing content inconsistencies
            foreach ($fileName in $versionData.files.PSObject.Properties.Name) {
                if ($fileName -like "*.lua") {
                $filePath = "$($script:CommonPaths.Src)\$fileName"
                if (Test-Path $filePath) {
                    $fileModDate = (Get-Item $filePath).LastWriteTime.ToString($script:DateFormat)
                    $luaContent = Get-Content $filePath -Raw
                    $needsContentFix = $false
                    
                    # Check if Version field doesn't match the file's own mod date
                    if ($luaContent -match '(?m)^\s*Version:\s*([^\r\n]+)') {
                        $currentVersionField = $matches[1].Trim()
                        if ($currentVersionField -ne $fileModDate) {
                            Write-Warning "File $fileName Version field '$currentVersionField' doesn't match file date '$fileModDate'"
                            $luaContent = $luaContent -replace '(?m)^\s*Version:\s*[^\r\n]+', "  Version: $fileModDate"
                            $needsContentFix = $true
                        }
                    }
                    
                    if ($needsContentFix) {
                        Set-Content $filePath -Value $luaContent -NoNewline
                        Write-Success "Fixed version content in $filePath to match file date $fileModDate" -Force
                    }
                }
            }
            }
            
            # Fix profile file version content if needed
            foreach ($fileName in $versionData.files.PSObject.Properties.Name) {
                if ($fileName -like "*.yml") {
                    $filePaths = Get-FilePathsForTracking $fileName
                    $filePath = $filePaths | Where-Object { Test-Path $_ } | Select-Object -First 1
                    if ($filePath) {
                        $fileModDate = (Get-Item $filePath).LastWriteTime.ToString($script:DateFormat)
                        $ymlContent = Get-Content $filePath -Raw
                        
                        # Check if Version comment doesn't match the file's own mod date
                        if ($ymlContent -match '(?m)^# Version:\s*([^\r\n]+)') {
                            $currentVersionField = $matches[1].Trim()
                            if ($currentVersionField -ne $fileModDate) {
                                Write-Warning "File $fileName Version comment '$currentVersionField' doesn't match file date '$fileModDate'"
                                $ymlContent = $ymlContent -replace '(?m)^# Version:\s*[^\r\n]+', "# Version: $fileModDate"
                                Set-Content $filePath -Value $ymlContent -NoNewline
                                Write-Success "Fixed version content in $filePath to match file date $fileModDate" -Force
                            }
                        }
                    }
                }
            }
            
            # Fix config.yml comment version if needed
            if (Test-Path "config.yml") {
                $configContent = Get-Content "config.yml" -Raw
                if ($configContent -match '(?m)^# Version:\s*([^\r\n]+)') {
                    $currentCommentVersion = $matches[1].Trim()
                    if ($currentCommentVersion -ne $newMainVersion) {
                        Write-Warning "Config.yml comment has '$currentCommentVersion', should match main version '$newMainVersion'"
                        $configContent = $configContent -replace '(?m)^# Version:\s*[^\r\n]+', "# Version: $newMainVersion"
                        Set-Content "config.yml" -Value $configContent -NoNewline
                        Write-Success "Updated config.yml comment version to $newMainVersion" -Force
                    }
                }
            }
            
            Write-Success "Applied changes to version.json and config.yml" -Force
        }
    } else {
        Write-Info "No changes to apply" -Force
    }

    # If VersionOnly flag is set, exit here without building/deploying
    if ($VersionOnly) {
        Write-Success "Version-only update complete - skipping build and deploy" -Force
        exit 0
    }

    # If CheckVersions flag is set, exit here without building/deploying
    if ($CheckVersions) {
        Write-Success "Version check complete - no build or deploy" -Force
        exit 0
    }

    Write-Info "Continuing with smart build and deploy..."
}

# Force version bump for all files (major release)
if ($BumpAllVersions -and (Test-Path "version.json")) {
    Write-Info "🚀 Bump All Versions - Force updating all files to today's version..."

    $versionData = Get-Content "version.json" -Raw | ConvertFrom-Json
    $today = Get-Date -Format $script:DateFormat

    # Update main project version
    $versionData.version = $today
    $versionData.lastUpdated = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")

    # Update ALL file versions to today
    $versionData.files.PSObject.Properties | ForEach-Object {
        $versionData.files.($_.Name) = $today
        Write-Success "  Updated $($_.Name) to $today" -Force
    }

    # ALWAYS prioritize config.yml (SmartThings main version)
    if ($versionData.files.PSObject.Properties.Name -contains "config.yml") {
        $versionData.files."config.yml" = $today
        Write-Host "  Updated config.yml to $today (SmartThings main version)" -ForegroundColor Magenta
    }

    Save-VersionJson $versionData

    # Update all hardcoded versions
    Write-Info "Updating all hardcoded version strings..."

    # Update common files with version patterns
    $versionPatterns = @(
        @{ File = "config.yml"; Pattern = '(?m)^Version: "\d+\.\d+\.\d+"'; Template = 'Version: "{0}"'; Desc = "config.yml main version field" },
        @{ File = "config.yml"; Pattern = '(?m)^# Version:\s*\d+\.\d+\.\d+'; Template = '# Version: {0}'; Desc = "config.yml comment" }
    )
    
    $versionPatterns | ForEach-Object {
        Update-FileVersionContent $_.File $today $_.Pattern $_.Template "  Updated $($_.Desc)"
    }

    # Update all Lua file version headers
    Get-ChildItem "$($script:CommonPaths.Src)\*.lua" | ForEach-Object {
        $content = Get-Content $_.FullName -Raw
        $newContent = $content -replace '(?m)^\s*Version:\s*(\d+\.\d+\.\d+|)', "  Version: $today"
        if ($newContent -ne $content) {
            Set-Content -Path $_.FullName -Value $newContent -NoNewline
            Write-Success "  Updated $($_.Name)" -Force
        }
    }

    # Update all profile file version headers
    Get-ChildItem "$($script:CommonPaths.Profiles)\*.yml" | ForEach-Object {
        $content = Get-Content $_.FullName -Raw
        $newContent = $content -replace '(?m)^# Version:\s*(\d+\.\d+\.\d+|)', "# Version: $today"
        if ($newContent -ne $content) {
            Set-Content -Path $_.FullName -Value $newContent -NoNewline
            Write-Success "  Updated $($_.Name)" -Force
        }
    }

    Write-Success "🎉 All versions bumped to $today - ready for major release!" -Force
    Write-Info "Version bump complete - skipping build and deploy"
    exit 0
}

# Version consistency check and report
if ($CheckVersions -and (Test-Path "version.json")) {
    Write-Info "Version Consistency Check..."

    $versionData = Get-Content "version.json" -Raw | ConvertFrom-Json
    $today = Get-Date -Format $script:DateFormat
    
    # Determine the expected version based on the latest file modification date
    $latestModificationDate = $null
    
    # Check all tracked files for their latest modification date
    $versionData.files.PSObject.Properties | ForEach-Object {
        $fileName = $_.Name
        $filePaths = Get-FilePathsForTracking $fileName

        foreach ($filePath in $filePaths) {
            if (Test-Path $filePath) {
                $fileDate = (Get-Item $filePath).LastWriteTime
                if ($null -eq $latestModificationDate -or $fileDate -gt $latestModificationDate) {
                    $latestModificationDate = $fileDate
                }
            }
        }
    }
    
    # Expected version should be the date of the latest file modification, not today
    $expectedVersion = if ($latestModificationDate) {
        $latestModificationDate.ToString($script:DateFormat)
    } else {
        $versionData.version  # Fallback to current project version
    }
    
    $allIssues = @()

    # Collect all version issues in one pass
    $fileIssues = @()
    $luaHeaderIssues = @()
    $configIssues = @()

    # Check file tracking versions - each file should match its own modification date
    $versionData.files.PSObject.Properties | ForEach-Object {
        $fileName = $_.Name
        $trackedVersion = $_.Value
        
        # Find the actual file and get its modification date
        $filePaths = Get-FilePathsForTracking $fileName

        foreach ($filePath in $filePaths) {
            if (Test-Path $filePath) {
                $fileModDate = (Get-Item $filePath).LastWriteTime
                $expectedFileVersion = $fileModDate.ToString($script:DateFormat)
                
                if ($trackedVersion -ne $expectedFileVersion) {
                    $fileIssues += "$fileName (tracked: $trackedVersion, file modified: $expectedFileVersion)"
                }
                break
            }
        }
    }

    # Check hardcoded versions
    # Note: config.yml version field will be updated at the end if main version changes,
    # so we don't report it as an error here in CheckVersions mode
    
    if (Test-Path "$($script:CommonPaths.Src)\init.lua") {
        $initContent = Get-Content "$($script:CommonPaths.Src)\init.lua" -Raw
        $initFileModDate = (Get-Item "$($script:CommonPaths.Src)\init.lua").LastWriteTime.ToString($script:DateFormat)
        if ($initContent -match 'Starting Pit Boss Grill SmartThings Edge Driver v(\d+\.\d+\.\d+)') {
            $initLogVersion = $Matches[1]
            if ($initLogVersion -ne $initFileModDate) {
                $luaHeaderIssues += "init.lua log message (v$initLogVersion, should be: v$initFileModDate)"
            }
        }
    }

    # Check Lua file headers - these should match each file's own modification date
    Get-ChildItem $script:CommonPaths.Src -Filter "*.lua" | ForEach-Object {
        $content = Get-Content $_.FullName -Raw
        if ($content -match "Version: (\d+\.\d+\.\d+)") {
            $headerVersion = $Matches[1]
            $fileModDate = $_.LastWriteTime
            $expectedFileVersion = $fileModDate.ToString($script:DateFormat)
            
            if ($headerVersion -ne $expectedFileVersion) {
                $luaHeaderIssues += "$($_.Name) header ($headerVersion, should be: $expectedFileVersion)"
            }
        }
    }

    # Display results concisely
    if ($versionData.version -eq $expectedVersion) {
        Write-Success "Project Version: $($versionData.version)" -Force
    } else {
        Write-Warning "Project Version: $($versionData.version)"
    }
    Write-Info "Expected Version: $expectedVersion (based on latest file modification)"
    Write-Host "Current Date: $today" -ForegroundColor Gray
    Write-Host ""

    $allIssues = @()
    $allIssues += $fileIssues
    $allIssues += $configIssues
    $allIssues += $luaHeaderIssues

    if ($allIssues.Count -gt 0) {
        Write-Error "VERSION ISSUES FOUND:"
        $allIssues | ForEach-Object { Write-Error "  - $_" }
        Write-Host ""
        Write-Error "SUMMARY: $($allIssues.Count) version issues found"
        Write-Error "Fix version issues before release. Run 'build.ps1 -SmartVersion' to sync."
        exit 1
    } else {
        Write-Success "All versions are consistent and current ($expectedVersion)"
        exit 0
    }
}

# Function to detect and clean up dirty files
function Test-AndCleanDirtyFiles {
    param($Config, [switch]$AutoRestore)

    $dirtyFiles = @()
    $filesToCheck = $script:StandardFiles.Clone()

    # Add capability files to check - look for both placeholder and real namespace files
    $placeholderCapabilityFiles = Get-CapabilityFiles $Config
    $realCapabilityFiles = Get-CapabilityFiles $Config -UseRealNamespace

    if ($placeholderCapabilityFiles) {
        $filesToCheck += $placeholderCapabilityFiles | ForEach-Object { $_.FullName }
    }
    if ($realCapabilityFiles) {
        $filesToCheck += $realCapabilityFiles | ForEach-Object { $_.FullName }
    }

    # Check each file for non-placeholder content
    foreach ($file in $filesToCheck) {
        $fullPath = if ([System.IO.Path]::IsPathRooted($file)) { $file } else { Join-Path $PWD $file }
        if (Test-Path $fullPath) {
            $content = Get-Content $fullPath -Raw -ErrorAction SilentlyContinue
            if ($content) {
                # Check if file contains real values instead of placeholders
                $containsRealNamespace = $content -match [regex]::Escape($Config.namespace)
                $containsRealProfileId = $content -match [regex]::Escape($Config.profileId)
                $containsRealPresentationId = $content -match [regex]::Escape($Config.presentationId)

                if ($containsRealNamespace -or $containsRealProfileId -or $containsRealPresentationId) {
                    $relativePath = if ([System.IO.Path]::IsPathRooted($file)) { Split-Path $file -Leaf } else { $file }
                    $dirtyFiles += @{
                        Path = $fullPath
                        RelativePath = $relativePath
                        Content = $content
                    }
                }
            }
        }
    }

    # Check for capability files with wrong names (real namespace instead of placeholder)
    $wrongNamedCapabilities = Get-CapabilityFiles $Config -UseRealNamespace

    if ($dirtyFiles.Count -gt 0 -or $wrongNamedCapabilities.Count -gt 0) {
        Write-Warning "Detected files that weren't properly restored from previous run:"

        if ($dirtyFiles.Count -gt 0) {
            Write-Warning "Files with real values instead of placeholders:"
            foreach ($file in $dirtyFiles) {
                Write-Warning "  - $($file.RelativePath)"
            }
        }

        if ($wrongNamedCapabilities.Count -gt 0) {
            Write-Warning "Capability files with real namespace in filename:"
            foreach ($file in $wrongNamedCapabilities) {
                Write-Warning "  - $($file.Name)"
            }
        }

        # If AutoRestore is requested, restore now and exit so user can re-run.
        if ($AutoRestore) {
            Write-Info "AutoRestore enabled - restoring files to placeholder versions..."

            foreach ($file in $dirtyFiles) {
                try {
                    $cleanContent = $file.Content
                    $cleanContent = $cleanContent -replace [regex]::Escape($Config.namespace), $script:PlaceholderTokens.Namespace
                    $cleanContent = $cleanContent -replace [regex]::Escape($Config.profileId), $script:PlaceholderTokens.ProfileId
                    $cleanContent = $cleanContent -replace [regex]::Escape($Config.presentationId), $script:PlaceholderTokens.PresentationId

                    Set-Content $file.Path $cleanContent -NoNewline
                    Write-Success "Restored $($file.RelativePath)" -Force:$false
                } catch {
                    Write-Error "Failed to restore $($file.RelativePath): $($_.Exception.Message)"
                }
            }

            foreach ($file in $wrongNamedCapabilities) {
                try {
                    $placeholderName = $file.Name -replace [regex]::Escape($Config.namespace), $script:PlaceholderTokens.Namespace
                    $placeholderPath = Join-Path $script:CommonPaths.Capabilities $placeholderName

                    if (Test-Path $placeholderPath) {
                        Remove-Item $placeholderPath -Force
                    }

                    Move-Item $file.FullName $placeholderPath
                    Write-Success "Renamed $($file.Name) back to $placeholderName" -Force:$false
                } catch {
                    Write-Error "Failed to rename $($file.Name): $($_.Exception.Message)"
                }
            }

            Write-Success "Files restored to placeholder versions" -Force
            Write-Info "Re-run the script to proceed with build"
            # Clear global variables so the end-of-build prompt does not appear again
            $global:DetectedDirtyFiles = @()
            $global:DetectedWrongNamedCapabilities = @()
            return $false
        }

        # Otherwise defer any interactive restore until after build/deploy completes
        # But for normal builds, we can skip the prompt since build will overwrite anyway
        if (-not $PackageOnly -and -not $ManualWork) {
            Write-Info "Normal build mode - dirty files will be handled during build process"
        } else {
            $global:DetectedDirtyFiles = $dirtyFiles
            $global:DetectedWrongNamedCapabilities = $wrongNamedCapabilities
            Write-Info "Detected dirty files. Will prompt to restore after build completes."
        }
    }

    return $true  # Continue with build; restoration may be prompted later
}

# Check if config file exists
if (-not (Test-Path $ConfigFile)) {
    Write-Error "Configuration file '$ConfigFile' not found!"
    Write-Info "Create it by copying from local-config.example.json and updating with your values."
    exit 1
}

# Load configuration
try {
    $config = Get-Content $ConfigFile | ConvertFrom-Json
    Write-Success "Loaded configuration from '$ConfigFile'" -Force
} catch {
    Write-Error "Failed to parse configuration file '$ConfigFile': $($_.Exception.Message)"
    exit 1
}

# Validate required configuration
$requiredFields = @("namespace", "profileId", "presentationId")
if (-not (Test-RequiredConfigFields $config $requiredFields)) {
    exit 1
}

# Check for and clean up dirty files from previous interrupted runs
$shouldContinue = Test-AndCleanDirtyFiles -Config $config -AutoRestore:$AutoRestore
if (-not $shouldContinue) {
    exit 0
}

# Check for placeholder values
$hasPlaceholders = $false
if ($config.namespace -like "*your-*-here*") { $hasPlaceholders = $true }
if ($config.profileId -like "*your-*-here*") { $hasPlaceholders = $true }
if ($config.presentationId -like "*your-*-here*") { $hasPlaceholders = $true }

if ($hasPlaceholders -and -not $PackageOnly) {
    Write-Warning "Configuration contains placeholder values - will package but skip deployment"
    $PackageOnly = $true
}

Write-Info "Configuration:"
Write-Host "  Namespace: $($config.namespace)" -ForegroundColor White
Write-Host "  Profile ID: $($config.profileId)" -ForegroundColor White
Write-Host "  Presentation ID: $($config.presentationId)" -ForegroundColor White
if (-not $PackageOnly -and $config.smartthings) {
    Write-Host "  Channel ID: $($config.smartthings.channelId)" -ForegroundColor White
    Write-Host "  Hub ID: $($config.smartthings.hubId)" -ForegroundColor White
}

# Script will prompt interactively if dirty files are found

# Store original files for restoration
$filesToRestore = @()
$capabilityRenames = @()

# Handle ManualWork parameter - replace placeholders, pause, then restore
if ($ManualWork) {
    Write-Info "Manual Work Mode: Replacing placeholders with real values..."

    # Files to process for placeholder replacement
    $filesToProcess = $script:StandardFiles.Clone()

    # Add all capability files
    $capabilityFiles = Get-CapabilityFiles $config
    if ($capabilityFiles) {
        $filesToProcess += $capabilityFiles | ForEach-Object { $_.FullName }
    } else {
        # If placeholder files don't exist, look for current namespace files
        $capabilityFiles = Get-CapabilityFiles $config -UseRealNamespace
        if ($capabilityFiles) {
            $filesToProcess += $capabilityFiles | ForEach-Object { $_.FullName }
        }
    }

    # Process files - replace placeholders and backup originals
    foreach ($file in $filesToProcess) {
        $fullPath = if ([System.IO.Path]::IsPathRooted($file)) { $file } else { Join-Path $PWD $file }
        if (Test-Path $fullPath) {
            Update-PlaceholdersInFile $fullPath $config ([ref]$filesToRestore) $file
        }
    }

    # Rename capability files from {{NAMESPACE}} to real namespace
    $placeholderPattern = "$($script:CommonPaths.Capabilities)\$($script:PlaceholderTokens.Namespace)*"
    $placeholderCapabilities = Get-ChildItem $placeholderPattern -ErrorAction SilentlyContinue
    foreach ($file in $placeholderCapabilities) {
        $newName = $file.Name -replace [regex]::Escape($script:PlaceholderTokens.Namespace), $config.namespace
        $newPath = Join-Path $script:CommonPaths.Capabilities $newName

        Move-Item $file.FullName $newPath
        $capabilityRenames += @{
            From = $newPath
            To = $file.FullName
        }
        Write-Success "Renamed $($file.Name) to $newName" -Force:$false
    }

    Write-Success "Placeholders have been replaced with real values." -Force
    Write-Success "You can now perform manual work with the files." -Force
    Write-Warning "Press any key to restore placeholder values and exit..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

    # Restore original file contents
    Write-Info "Restoring placeholder values..."
    foreach ($fileInfo in $filesToRestore) {
        try {
            # Check if this is a capability file that was renamed
            $currentPath = $fileInfo.Path
            $fileName = Split-Path $currentPath -Leaf

            # If it's a capability file with {{NAMESPACE}} in the path, it may have been renamed
            if ($currentPath -like "*$($script:CommonPaths.Capabilities)*" -and $fileName -like "*$($script:PlaceholderTokens.Namespace)*") {
                # Check if the renamed version exists instead
                $renamedFileName = $fileName -replace [regex]::Escape($script:PlaceholderTokens.Namespace), $config.namespace
                $renamedPath = Join-Path (Split-Path $currentPath -Parent) $renamedFileName

                if (Test-Path $renamedPath) {
                    $currentPath = $renamedPath
                }
            }

            Set-Content $currentPath $fileInfo.Content -NoNewline
            Write-Success "Restored $(Split-Path $fileInfo.Path -Leaf)" -Force:$false
        } catch {
            Write-Warning "Failed to restore $(Split-Path $fileInfo.Path -Leaf): $($_.Exception.Message)"
        }
    }

    # Restore capability file names
    foreach ($rename in $capabilityRenames) {
        try {
            if (Test-Path $rename.From) {
                if (Test-Path $rename.To) {
                    Remove-Item $rename.To -Force
                }
                Move-Item $rename.From $rename.To
                Write-Success "Restored $(Split-Path $rename.To -Leaf)" -Force:$false
            }
        } catch {
            Write-Warning "Failed to restore capability file name: $($_.Exception.Message)"
        }
    }

    Write-Success "All files restored to placeholder versions" -Force
    exit 0
}

# Handle RemoveDriver parameter - uninstall from hub and unassign from channel
if ($RemoveDriver) {
    Write-Info "Remove Driver Mode: Uninstalling driver and unassigning from channel..."

    # Validate required configuration for removal
    $validationChecks = @(
        @{ Field = "smartthings"; Section = $null; Required = $true },
        @{ Field = "channelId"; Section = "smartthings"; Required = $true },
        @{ Field = "hubId"; Section = "smartthings"; Required = $true },
        @{ Field = "profileId"; Section = $null; Required = $true }
    )
    
    foreach ($check in $validationChecks) {
        $value = if ($check.Section) { $config.($check.Section).($check.Field) } else { $config.($check.Field) }
        if (-not $value) {
            $fieldPath = if ($check.Section) { "$($check.Section).$($check.Field)" } else { $check.Field }
            Write-Error "Missing required field '$fieldPath' in configuration file for driver removal"
            exit 1
        }
    }

    $driverId = $config.profileId
    $channelId = $config.smartthings.channelId
    $hubId = $config.smartthings.hubId

    Write-Info "Removal Configuration:"
    Write-Host "  Driver ID: $driverId" -ForegroundColor White
    Write-Host "  Channel ID: $channelId" -ForegroundColor White
    Write-Host "  Hub ID: $hubId" -ForegroundColor White

    try {
        # Step 1: Uninstall driver from hub
        Write-Info "Step 1: Uninstalling driver from hub..."
        $uninstallResult = & smartthings edge:drivers:uninstall $channelId --hub=$hubId 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Successfully uninstalled driver from hub" -Force
        } else {
            Write-Warning "Driver uninstall may have failed or driver was not installed"
            Write-Warning $uninstallResult
        }

        # Step 2: Unassign driver from channel
        Write-Info "Step 2: Unassigning driver from channel..."
        $unassignResult = & smartthings edge:channels:unassign $driverId --channel=$channelId 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Successfully unassigned driver from channel" -Force
        } else {
            Write-Warning "Driver unassign may have failed or driver was not assigned"
            Write-Warning $unassignResult
        }

        # Step 3: Remove capabilities (presentations are automatically removed with capabilities)
        Write-Info "Step 3: Removing capabilities and their presentations..."

        # First check for placeholder files, then real namespace files
        $capabilityFiles = @()
        $placeholderCapabilityPattern = "$($script:CommonPaths.Capabilities)\$($script:PlaceholderTokens.Namespace)*.json"
        $realCapabilityPattern = "$($script:CommonPaths.Capabilities)\$($config.namespace)*.json"

        $placeholderCapabilityFiles = Get-ChildItem $placeholderCapabilityPattern -ErrorAction SilentlyContinue
        $realCapabilityFiles = Get-ChildItem $realCapabilityPattern -ErrorAction SilentlyContinue

        $capabilityFiles = @($placeholderCapabilityFiles) + @($realCapabilityFiles)

        foreach ($capFile in $capabilityFiles) {
            $fileName = [System.IO.Path]::GetFileNameWithoutExtension($capFile.Name)
            # Replace placeholder with real namespace if needed
            $capabilityName = $fileName -replace [regex]::Escape($script:PlaceholderTokens.Namespace), $config.namespace

            try {
                Write-Info "  Removing capability: $capabilityName"
                $removeCapResult = & smartthings capabilities:delete $capabilityName 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Success "  Successfully removed capability: $capabilityName" -Force:$false
                } else {
                    Write-Warning "  Failed to remove capability: $capabilityName"
                    Write-Warning "    $removeCapResult"
                }
            } catch {
                Write-Warning "  Error removing capability $capabilityName : $($_.Exception.Message)"
            }
        }

        Write-Success "Complete driver removal and cleanup completed successfully" -Force

    } catch {
        Write-Error "Failed to remove driver: $($_.Exception.Message)"
        exit 1
    }

    exit 0
}

try {
    Write-Info "Phase 1: Replacing placeholders with real values..."

    # Files to process for placeholder replacement
    $filesToProcess = $script:StandardFiles.Clone()

    # Add all capability files
    $capabilityFiles = Get-CapabilityFiles $config
    if ($capabilityFiles) {
        $filesToProcess += $capabilityFiles | ForEach-Object { $_.FullName }
    } else {
        # If placeholder files don't exist, look for current namespace files
        $capabilityFiles = Get-CapabilityFiles $config -UseRealNamespace
        if ($capabilityFiles) {
            $filesToProcess += $capabilityFiles | ForEach-Object { $_.FullName }
        }
    }

    foreach ($file in $filesToProcess) {
        $fullPath = if ([System.IO.Path]::IsPathRooted($file)) { $file } else { Join-Path $PWD $file }
        if (Test-Path $fullPath) {
            Update-PlaceholdersInFile $fullPath $config ([ref]$filesToRestore) $file
        }
    }

    Write-Info "Phase 2: Renaming capability files..."

    # Rename capability files from {{NAMESPACE}} to real namespace
    $placeholderCapabilities = Get-CapabilityFiles $config
    foreach ($file in $placeholderCapabilities) {
        $newName = $file.Name -replace [regex]::Escape($script:PlaceholderTokens.Namespace), $config.namespace
        $newPath = Join-Path $script:CommonPaths.Capabilities $newName

        Move-Item $file.FullName $newPath
        $capabilityRenames += @{
            From = $newPath
            To = $file.FullName
        }
    Write-Success "Renamed $($file.Name) to $newName" -Force:$false
    }

    # Update capabilities and presentation if requested
    if ($UpdateCapabilities) {
        Write-Info "Phase 3: Updating SmartThings capabilities and presentation..."

        # Get all capability files (exclude .presentation.yaml files)
        $namespacePattern = "$($script:CommonPaths.Capabilities)\$($config.namespace)*"
        $allFiles = Get-ChildItem $namespacePattern -ErrorAction SilentlyContinue

        # Separate capability files from presentation files
        $capabilityFiles = $allFiles | Where-Object {
            $_.Name -notmatch '\.presentation\.(yaml|yml)$' -and
            ($_.Extension -eq '.json' -or $_.Extension -eq '.yml' -or $_.Extension -eq '.yaml')
        }
        $presentationFiles = $allFiles | Where-Object { $_.Name -match '\.presentation\.(yaml|yml)$' }

        # Process capability files
        foreach ($capabilityFile in $capabilityFiles) {
            $capabilityName = [System.IO.Path]::GetFileNameWithoutExtension($capabilityFile.Name)
            Write-Info "Processing capability: $capabilityName"

            # Check if capability exists by listing all capabilities and searching for this one
            $listResult = & smartthings capabilities --json 2>&1
            $capabilityExists = $false

            if ($LASTEXITCODE -eq 0) {
                try {
                    $capabilities = $listResult | ConvertFrom-Json
                    $capabilityExists = $capabilities | Where-Object { $_.id -eq $capabilityName } | Measure-Object | Select-Object -ExpandProperty Count
                    $capabilityExists = $capabilityExists -gt 0
                } catch {
                    Write-Warning "Failed to parse capabilities list, attempting direct check"
                    # Fallback: try to get the specific capability
                    & smartthings capabilities $capabilityName --json 2>&1 | Out-Null
                    $capabilityExists = $LASTEXITCODE -eq 0
                }
            } else {
                Write-Warning "Failed to list capabilities, attempting direct check"
                # Fallback: try to get the specific capability
                & smartthings capabilities $capabilityName --json 2>&1 | Out-Null
                $capabilityExists = $LASTEXITCODE -eq 0
            }

            if ($capabilityExists) {
                Write-Info "Updating existing capability: $capabilityName"
                $updateResult = & smartthings capabilities:update $capabilityName -i $capabilityFile.FullName 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Success "Updated capability: $capabilityName" -Force:$false
                } else {
                    Write-Error "Failed to update capability $capabilityName"
                    Write-Error $updateResult
                }
            } else {
                Write-Info "Creating new capability: $capabilityName"
                $createResult = & smartthings capabilities:create -i $capabilityFile.FullName 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Success "Created capability: $capabilityName" -Force:$false
                } else {
                    Write-Error "Failed to create capability $capabilityName"
                    Write-Error $createResult
                }
            }
        }

        # Process presentation files
        foreach ($presentationFile in $presentationFiles) {
            $presentationName = [System.IO.Path]::GetFileNameWithoutExtension([System.IO.Path]::GetFileNameWithoutExtension($presentationFile.Name))
            Write-Info "Processing capability presentation: $presentationName"

            # Check if presentation exists by trying to get it directly
            & smartthings capabilities:presentation $presentationName --json 2>&1 | Out-Null
            $presentationExists = $LASTEXITCODE -eq 0

            if ($presentationExists) {
                Write-Info "Updating existing capability presentation: $presentationName"
                $updateResult = & smartthings capabilities:presentation:update $presentationName -i $presentationFile.FullName 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Success "Updated capability presentation: $presentationName" -Force:$false
                } else {
                    Write-Error "Failed to update capability presentation $presentationName"
                    Write-Error $updateResult
                }
            } else {
                Write-Info "Creating new capability presentation: $presentationName"
                $createResult = & smartthings capabilities:presentation:create $presentationName -i $presentationFile.FullName 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Success "Created capability presentation: $presentationName" -Force:$false
                } else {
                    Write-Error "Failed to create capability presentation $presentationName"
                    Write-Error $createResult
                }
            }
        }
    }

    $phaseNum = if ($UpdateCapabilities) { 4 } else { 3 }
    Write-Info "Phase $phaseNum`: Building SmartThings Edge driver package..."

    # Package the driver
    $packageResult = & smartthings edge:drivers:package .\ 2>&1 --json | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to package driver:"
        Write-Error $packageResult
        throw "Package command failed"
    }
    Write-Success "Driver packaged successfully" -Force
    # Print a concise summary of the package result
    if ($packageResult.driverId) {
        Write-Host ("Driver ID: {0}" -f $packageResult.driverId) -ForegroundColor Gray
    }
    if ($packageResult.name) {
        Write-Host ("Name: {0}" -f $packageResult.name) -ForegroundColor Gray
    }
    if ($packageResult.version) {
        Write-Host ("Version: {0}" -f $packageResult.version) -ForegroundColor Gray
    }
    if ($packageResult.packageKey) {
        Write-Host ("Package Key: {0}" -f $packageResult.packageKey) -ForegroundColor Gray
    }

    # Deploy if not package-only mode
    if (-not $PackageOnly -and $config.smartthings -and $config.smartthings.channelId -and $config.smartthings.hubId) {
        $deployPhaseNum = if ($UpdateCapabilities) { 5 } else { 4 }
        Write-Info "Phase $deployPhaseNum`: Deploying to SmartThings..."

        # Use the correct CLI syntax: package, assign to channel, and install to hub in one command
        Write-Info "Packaging, assigning to channel, and installing to hub..."
        $deployResult = & smartthings edge:drivers:package .\ --channel $config.smartthings.channelId --hub $config.smartthings.hubId 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Driver packaged, assigned to channel, and installed to hub successfully" -Force
            # Print a concise summary of the deploy result
            if ($deployResult.driverId) {
                Write-Host ("Driver ID: {0}" -f $deployResult.driverId) -ForegroundColor Gray
            }
            if ($deployResult.name) {
                Write-Host ("Name: {0}" -f $deployResult.name) -ForegroundColor Gray
            }
            if ($deployResult.version) {
                Write-Host ("Version: {0}" -f $deployResult.version) -ForegroundColor Gray
            }
            if ($deployResult.packageKey) {
                Write-Host ("Package Key: {0}" -f $deployResult.packageKey) -ForegroundColor Gray
            }
        } else {
            Write-Error "Failed to deploy driver:"
            Write-Error $deployResult
            throw "Deploy command failed"
        }

    } elseif (-not $PackageOnly) {
        Write-Warning "Skipping deployment - missing SmartThings configuration"
    }

} catch {
    Write-Error "Build failed: $($_.Exception.Message)"
    $buildFailed = $true
} finally {
    $restorePhaseNum = if ($UpdateCapabilities) { 6 } else { 5 }
    Write-Info "Phase $restorePhaseNum`: Restoring placeholder versions..."

    # Restore original file contents
    foreach ($fileInfo in $filesToRestore) {
        Restore-FileContent $fileInfo $config "Warning"
    }

    # Restore capability file names
    foreach ($rename in $capabilityRenames) {
        try {
            if (Test-Path $rename.From) {
                # Remove existing destination file if it exists
                if (Test-Path $rename.To) {
                    Remove-Item $rename.To -Force
                }
                Move-Item $rename.From $rename.To
                Write-Success "Restored $(Split-Path $rename.To -Leaf)" -Force:$false
            }
        } catch {
            Write-Warning "Failed to restore capability file name: $($_.Exception.Message)"
        }
    }

    if ($buildFailed) {
        Write-Error "Build process failed - files have been restored to placeholder versions"
        exit 1
    } else {
        Write-Success "Build completed successfully - files restored to placeholder versions" -Force
        if ($PackageOnly) {
            Write-Info "Generated package files are ready for deployment"
        }
    }

    # If earlier runs detected dirty files, prompt once now (unless AutoRestore was set or PackageOnly mode)
    if ($global:DetectedDirtyFiles -or $global:DetectedWrongNamedCapabilities) {
        $detected = $global:DetectedDirtyFiles
        $wrongNamed = $global:DetectedWrongNamedCapabilities

        if ($AutoRestore) {
            Write-Info "AutoRestore enabled - restoring previously detected dirty files..."
            $doRestore = $true
        } elseif ($PackageOnly) {
            Write-Info "PackageOnly mode - skipping dirty file restoration prompt"
            Write-Warning "Note: Detected leftover dirty files from a previous run. Run with -AutoRestore to clean them up."
            $doRestore = $false
        } else {
            $answer = Read-Host "Detected leftover dirty files from a previous run. Restore them now? (y/N)"
            $doRestore = ($answer -eq 'y' -or $answer -eq 'Y')
        }

        if ($doRestore) {
            foreach ($file in $detected) {
                try {
                    $cleanContent = Restore-PlaceholdersInContent $file.Content $config
                    Set-Content $file.Path $cleanContent -NoNewline
                    Write-Success "Restored $($file.RelativePath)" -Force:$false
                } catch {
                    Write-Warning "Failed to restore $($file.RelativePath): $($_.Exception.Message)"
                }
            }

            foreach ($file in $wrongNamed) {
                try {
                    $placeholderName = $file.Name -replace [regex]::Escape($config.namespace), $script:PlaceholderTokens.Namespace
                    $placeholderPath = Join-Path $script:CommonPaths.Capabilities $placeholderName
                    if (Test-Path $placeholderPath) { Remove-Item $placeholderPath -Force }
                    Move-Item $file.FullName $placeholderPath
                    Write-Success "Renamed $($file.Name) back to $placeholderName" -Force:$false
                } catch {
                    Write-Warning "Failed to rename $($file.Name): $($_.Exception.Message)"
                }
            }

            Write-Info "Deferred files restored to placeholder versions"
        } else {
            Write-Warning "Deferred dirty files were not restored. Manually restore before committing."
        }
    }
}