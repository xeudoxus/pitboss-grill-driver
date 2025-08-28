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
    Version        : 1.0.0
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
#>


param(
    [Alias('c')][string]$ConfigFile = "local-config.json",
    [Alias('p')][switch]$PackageOnly,
    [Alias('u')][switch]$UpdateCapabilities,
    [Alias('r')][switch]$RemoveDriver,
    [Alias('m')][switch]$ManualWork,
    [Alias('a','y','NonInteractive','Force')][switch]$AutoRestore,
    [Alias('h')][switch]$Help,
    [Alias('v')][switch]$Verbose
)

# Clear global dirty file tracking at the start of every run
$global:DetectedDirtyFiles = @()
$global:DetectedWrongNamedCapabilities = @()

# Show help if requested
if ($Help) {
    Get-Help $MyInvocation.MyCommand.Path -Detailed
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

# Function to detect and clean up dirty files
function Test-AndCleanDirtyFiles {
    param($Config, [switch]$AutoRestore)

    $dirtyFiles = @()
    $filesToCheck = @(
        "config.yml",
        "profiles\pitboss-grill-profile.yml",
        "src\custom_capabilities.lua"
    )

    # Add capability files to check - look for both placeholder and real namespace files
    $placeholderCapabilityPattern = "capabilities\{{NAMESPACE}}*"
    $realCapabilityPattern = "capabilities\$($Config.namespace)*"

    $placeholderCapabilityFiles = Get-ChildItem $placeholderCapabilityPattern -ErrorAction SilentlyContinue
    $realCapabilityFiles = Get-ChildItem $realCapabilityPattern -ErrorAction SilentlyContinue

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
    $wrongNamedCapabilities = Get-ChildItem "capabilities\$($Config.namespace)*" -ErrorAction SilentlyContinue

    if ($dirtyFiles.Count -gt 0 -or $wrongNamedCapabilities.Count -gt 0) {
        Write-Warning "Detected files that weren't properly restored from previous run:"

        if ($dirtyFiles.Count -gt 0) {
            Write-Host "Files with real values instead of placeholders:" -ForegroundColor Yellow
            foreach ($file in $dirtyFiles) {
                Write-Host "  - $($file.RelativePath)" -ForegroundColor Yellow
            }
        }

        if ($wrongNamedCapabilities.Count -gt 0) {
            Write-Host "Capability files with real namespace in filename:" -ForegroundColor Yellow
            foreach ($file in $wrongNamedCapabilities) {
                Write-Host "  - $($file.Name)" -ForegroundColor Yellow
            }
        }

        # If AutoRestore is requested, restore now and exit so user can re-run.
        if ($AutoRestore) {
            Write-Info "AutoRestore enabled - restoring files to placeholder versions..."

            foreach ($file in $dirtyFiles) {
                try {
                    $cleanContent = $file.Content
                    $cleanContent = $cleanContent -replace [regex]::Escape($Config.namespace), '{{NAMESPACE}}'
                    $cleanContent = $cleanContent -replace [regex]::Escape($Config.profileId), '{{PROFILE_ID}}'
                    $cleanContent = $cleanContent -replace [regex]::Escape($Config.presentationId), '{{PRESENTATION_ID}}'

                    Set-Content $file.Path $cleanContent -NoNewline
                    Write-Success "Restored $($file.RelativePath)" -Force:$false
                } catch {
                    Write-Error "Failed to restore $($file.RelativePath): $($_.Exception.Message)"
                }
            }

            foreach ($file in $wrongNamedCapabilities) {
                try {
                    $placeholderName = $file.Name -replace [regex]::Escape($Config.namespace), '{{NAMESPACE}}'
                    $placeholderPath = Join-Path "capabilities" $placeholderName

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
foreach ($field in $requiredFields) {
    if (-not $config.$field) {
        Write-Error "Missing required field '$field' in configuration file"
        exit 1
    }
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
    $filesToProcess = @(
        "config.yml",
        "profiles\pitboss-grill-profile.yml",
        "src\custom_capabilities.lua"
    )
    
    # Add all capability files
    $capabilityPattern = "capabilities\{{NAMESPACE}}*"
    $capabilityFiles = Get-ChildItem $capabilityPattern -ErrorAction SilentlyContinue
    if ($capabilityFiles) {
        $filesToProcess += $capabilityFiles | ForEach-Object { $_.FullName }
    } else {
        # If placeholder files don't exist, look for current namespace files
        $namespacePattern = "capabilities\$($config.namespace)*"
        $capabilityFiles = Get-ChildItem $namespacePattern -ErrorAction SilentlyContinue
        if ($capabilityFiles) {
            $filesToProcess += $capabilityFiles | ForEach-Object { $_.FullName }
        }
    }
    
    # Process files - replace placeholders and backup originals
    foreach ($file in $filesToProcess) {
        $fullPath = if ([System.IO.Path]::IsPathRooted($file)) { $file } else { Join-Path $PWD $file }
        if (Test-Path $fullPath) {
            # Backup original content
            $originalContent = Get-Content $fullPath -Raw
            $filesToRestore += @{
                Path = $fullPath
                Content = $originalContent
            }
            
            # Replace placeholders
            $newContent = $originalContent
            $newContent = $newContent -replace '\{\{NAMESPACE\}\}', $config.namespace
            $newContent = $newContent -replace '\{\{PROFILE_ID\}\}', $config.profileId
            $newContent = $newContent -replace '\{\{PRESENTATION_ID\}\}', $config.presentationId
            
            Set-Content $fullPath $newContent -NoNewline
            $relativePath = if ([System.IO.Path]::IsPathRooted($file)) { Split-Path $file -Leaf } else { $file }
            Write-Success "Updated placeholders in $relativePath" -Force:$false
        }
    }
    
    # Rename capability files from {{NAMESPACE}} to real namespace
    $placeholderPattern = "capabilities\{{NAMESPACE}}*"
    $placeholderCapabilities = Get-ChildItem $placeholderPattern -ErrorAction SilentlyContinue
    foreach ($file in $placeholderCapabilities) {
        $newName = $file.Name -replace '\{\{NAMESPACE\}\}', $config.namespace
        $newPath = Join-Path "capabilities" $newName
        
        Move-Item $file.FullName $newPath
        $capabilityRenames += @{
            From = $newPath
            To = $file.FullName
        }
        Write-Success "Renamed $($file.Name) to $newName" -Force:$false
    }
    
    Write-Host "Placeholders have been replaced with real values." -ForegroundColor Green
    Write-Host "You can now perform manual work with the files." -ForegroundColor Green
    Write-Host "Press any key to restore placeholder values and exit..." -ForegroundColor Yellow
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    
    # Restore original file contents
    Write-Info "Restoring placeholder values..."
    foreach ($fileInfo in $filesToRestore) {
        try {
            # Check if this is a capability file that was renamed
            $currentPath = $fileInfo.Path
            $fileName = Split-Path $currentPath -Leaf
            
            # If it's a capability file with {{NAMESPACE}} in the path, it may have been renamed
            if ($currentPath -like "*capabilities*" -and $fileName -like "*{{NAMESPACE}}*") {
                # Check if the renamed version exists instead
                $renamedFileName = $fileName -replace '\{\{NAMESPACE\}\}', $config.namespace
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
    $removalFields = @("smartthings")
    foreach ($field in $removalFields) {
        if (-not $config.$field) {
            Write-Error "Missing required field '$field' in configuration file for driver removal"
            exit 1
        }
    }
    
    $removalSubFields = @("channelId", "hubId")
    foreach ($field in $removalSubFields) {
        if (-not $config.smartthings.$field) {
            Write-Error "Missing required field 'smartthings.$field' in configuration file for driver removal"
            exit 1
        }
    }
    
    # Get driver ID from profile
    if (-not $config.profileId) {
        Write-Error "Missing required field 'profileId' in configuration file for driver removal"
        exit 1
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
            Write-Host $uninstallResult -ForegroundColor Yellow
        }
        
        # Step 2: Unassign driver from channel
        Write-Info "Step 2: Unassigning driver from channel..."
        $unassignResult = & smartthings edge:channels:unassign $driverId --channel=$channelId 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Successfully unassigned driver from channel" -Force
        } else {
            Write-Warning "Driver unassign may have failed or driver was not assigned"
            Write-Host $unassignResult -ForegroundColor Yellow
        }
        
        # Step 3: Remove capabilities (presentations are automatically removed with capabilities)
        Write-Info "Step 3: Removing capabilities and their presentations..."
        
        # First check for placeholder files, then real namespace files
        $capabilityFiles = @()
        $placeholderCapabilityPattern = "capabilities\{{NAMESPACE}}*.json"
        $realCapabilityPattern = "capabilities\$($config.namespace)*.json"
        
        $placeholderCapabilityFiles = Get-ChildItem $placeholderCapabilityPattern -ErrorAction SilentlyContinue
        $realCapabilityFiles = Get-ChildItem $realCapabilityPattern -ErrorAction SilentlyContinue
        
        $capabilityFiles = @($placeholderCapabilityFiles) + @($realCapabilityFiles)
        
        foreach ($capFile in $capabilityFiles) {
            $fileName = [System.IO.Path]::GetFileNameWithoutExtension($capFile.Name)
            # Replace placeholder with real namespace if needed
            $capabilityName = $fileName -replace '\{\{NAMESPACE\}\}', $config.namespace
            
            try {
                Write-Info "  Removing capability: $capabilityName"
                $removeCapResult = & smartthings capabilities:delete $capabilityName 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Success "  Successfully removed capability: $capabilityName" -Force:$false
                } else {
                    Write-Warning "  Failed to remove capability: $capabilityName"
                    Write-Host "    $removeCapResult" -ForegroundColor Yellow
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
    $filesToProcess = @(
        "config.yml",
        "profiles\pitboss-grill-profile.yml",
        "src\custom_capabilities.lua"
    )
    
    # Add all capability files - use wildcard pattern properly
    $capabilityPattern = "capabilities\{{NAMESPACE}}*"
    $capabilityFiles = Get-ChildItem $capabilityPattern -ErrorAction SilentlyContinue
    if ($capabilityFiles) {
        $filesToProcess += $capabilityFiles | ForEach-Object { $_.FullName }
    } else {
        # If placeholder files don't exist, look for current namespace files
        $namespacePattern = "capabilities\$($config.namespace)*"
        $capabilityFiles = Get-ChildItem $namespacePattern -ErrorAction SilentlyContinue
        if ($capabilityFiles) {
            $filesToProcess += $capabilityFiles | ForEach-Object { $_.FullName }
        }
    }
    
    foreach ($file in $filesToProcess) {
        $fullPath = if ([System.IO.Path]::IsPathRooted($file)) { $file } else { Join-Path $PWD $file }
        if (Test-Path $fullPath) {
            # Backup original content
            $originalContent = Get-Content $fullPath -Raw
            $filesToRestore += @{
                Path = $fullPath
                Content = $originalContent
            }
            
            # Replace placeholders
            $newContent = $originalContent
            $newContent = $newContent -replace '\{\{NAMESPACE\}\}', $config.namespace
            $newContent = $newContent -replace '\{\{PROFILE_ID\}\}', $config.profileId
            $newContent = $newContent -replace '\{\{PRESENTATION_ID\}\}', $config.presentationId
            
            Set-Content $fullPath $newContent -NoNewline
            $relativePath = if ([System.IO.Path]::IsPathRooted($file)) { Split-Path $file -Leaf } else { $file }
            Write-Success "Updated placeholders in $relativePath" -Force:$false
        }
    }
    
    Write-Info "Phase 2: Renaming capability files..."
    
    # Rename capability files from {{NAMESPACE}} to real namespace
    $placeholderPattern = "capabilities\{{NAMESPACE}}*"
    $placeholderCapabilities = Get-ChildItem $placeholderPattern -ErrorAction SilentlyContinue
    foreach ($file in $placeholderCapabilities) {
        $newName = $file.Name -replace '\{\{NAMESPACE\}\}', $config.namespace
        $newPath = Join-Path "capabilities" $newName
        
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
        $namespacePattern = "capabilities\$($config.namespace)*"
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
                    Write-Host $updateResult -ForegroundColor Red
                }
            } else {
                Write-Info "Creating new capability: $capabilityName"
                $createResult = & smartthings capabilities:create -i $capabilityFile.FullName 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Success "Created capability: $capabilityName" -Force:$false
                } else {
                    Write-Error "Failed to create capability $capabilityName"
                    Write-Host $createResult -ForegroundColor Red
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
                    Write-Host $updateResult -ForegroundColor Red
                }
            } else {
                Write-Info "Creating new capability presentation: $presentationName"
                $createResult = & smartthings capabilities:presentation:create $presentationName -i $presentationFile.FullName 2>&1
                if ($LASTEXITCODE -eq 0) {
                    Write-Success "Created capability presentation: $presentationName" -Force:$false
                } else {
                    Write-Error "Failed to create capability presentation $presentationName"
                    Write-Host $createResult -ForegroundColor Red
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
        Write-Host $packageResult -ForegroundColor Red
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
            Write-Host $deployResult -ForegroundColor Red
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
        try {
            # Check if this is a capability file that was renamed
            $currentPath = $fileInfo.Path
            $fileName = Split-Path $currentPath -Leaf
            
            # If it's a capability file with {{NAMESPACE}} in the path, it may have been renamed
            if ($currentPath -like "*capabilities*" -and $fileName -like "*{{NAMESPACE}}*") {
                # Check if the renamed version exists instead
                $renamedFileName = $fileName -replace '\{\{NAMESPACE\}\}', $config.namespace
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
        Write-Info "Generated package files are ready for deployment"
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
                    $cleanContent = $file.Content
                    $cleanContent = $cleanContent -replace [regex]::Escape($config.namespace), '{{NAMESPACE}}'
                    $cleanContent = $cleanContent -replace [regex]::Escape($config.profileId), '{{PROFILE_ID}}'
                    $cleanContent = $cleanContent -replace [regex]::Escape($config.presentationId), '{{PRESENTATION_ID}}'
                    Set-Content $file.Path $cleanContent -NoNewline
                    Write-Success "Restored $($file.RelativePath)" -Force:$false
                } catch {
                    Write-Warning "Failed to restore $($file.RelativePath): $($_.Exception.Message)"
                }
            }

            foreach ($file in $wrongNamed) {
                try {
                    $placeholderName = $file.Name -replace [regex]::Escape($config.namespace), '{{NAMESPACE}}'
                    $placeholderPath = Join-Path "capabilities" $placeholderName
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