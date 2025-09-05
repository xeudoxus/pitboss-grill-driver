<#
.SYNOPSIS
    Run Python test suite for Pit Boss Grill SmartThings Edge Driver

.DESCRIPTION
    This script runs the comprehensive Python-based test suite using pytest with coverage reporting.
    It automatically activates the virtual environment and provides various testing options.

    Coverage can measure both Python test infrastructure and Lua source code execution.
    Use -LuaCoverage to enable tracking of Lua code execution within the lupa runtime.

.PARAMETER TestPath
    Specific test file or directory to run (optional)

.PARAMETER NoCoverage
    Skip coverage reporting for faster test execution

.PARAMETER DetailedOutput
    Enable detailed output

.PARAMETER HtmlReport
    Generate HTML coverage report in addition to console output

.PARAMETER LuaCoverage
    Enable Lua source code coverage tracking (requires LUA_COVERAGE=1 environment variable)

.EXAMPLE
    .\test.ps1 -LuaCoverage
    Run tests with both Python and Lua coverage

.EXAMPLE
    .\test.ps1 -LuaCoverage -HtmlReport
    Run tests with Lua coverage and generate HTML report

.NOTES
    Requires Python virtual environment to be set up
    Requires pytest and coverage packages to be installed
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$TestPath = "tests/",

    [Parameter(Mandatory = $false)]
    [switch]$NoCoverage,

    [Parameter(Mandatory = $false)]
    [switch]$DetailedOutput,

    [Parameter(Mandatory = $false)]
    [switch]$HtmlReport,

    [Parameter(Mandatory = $false)]
    [switch]$XmlReport,

    [Parameter(Mandatory = $false)]
    [switch]$LuaCoverage
)

# Set UTF-8 encoding for proper emoji and Unicode character display in console only
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Script configuration
$ErrorActionPreference = "Stop"

# Color codes for output
$Green = "Green"
$Red = "Red"
$Yellow = "Yellow"
$Cyan = "Cyan"
$White = "White"

function Write-ColoredOutput {
    param(
        [string]$Message,
        [string]$Color = $White
    )
    Write-Host $Message -ForegroundColor $Color
}

function Write-Header {
    param([string]$Text)
    Write-ColoredOutput "`n=== $Text ===" $Cyan
}

function Write-Success {
    param([string]$Text)
    Write-ColoredOutput "[OK] $Text" $Green
}

function Write-ErrorMessage {
    param([string]$Text)
    Write-ColoredOutput "[ERROR] $Text" $Red
}

function Write-Info {
    param([string]$Text)
    Write-ColoredOutput "[INFO] $Text" $Yellow
}

function Test-VirtualEnvironment {
    Write-Info "Checking Python virtual environment..."

    # Check if we're already in a virtual environment
    if ($env:VIRTUAL_ENV) {
        Write-Success "Virtual environment is already active: $env:VIRTUAL_ENV"
        return $true
    }

    # Check for virtual environment in common locations
    $venvPaths = @(
        ".venv",
        "venv",
        ".env",
        "env"
    )

    foreach ($venvPath in $venvPaths) {
        $activateScript = Join-Path $PSScriptRoot $venvPath
        $activateScript = Join-Path $activateScript "Scripts"
        $activateScript = Join-Path $activateScript "Activate.ps1"

        if (Test-Path $activateScript) {
            Write-Info "Found virtual environment at: $venvPath"
            try {
                # Source the activation script to modify current session
                . $activateScript
                Write-Success "Virtual environment activated successfully"
                return $true
            }
            catch {
                Write-ErrorMessage "Failed to activate virtual environment: $_"
                return $false
            }
        }
    }

    Write-ErrorMessage "No virtual environment found. Please run 'python -m venv .venv' first."
    return $false
}

function Test-PythonDependencies {
    Write-Info "Checking Python dependencies..."

    # Check if required packages are installed
    $requiredPackages = @("pytest", "coverage", "lupa")

    foreach ($package in $requiredPackages) {
        try {
            python -c "import $package" 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                Write-Success "$package is installed"
            } else {
                Write-ErrorMessage "$package is not installed or has issues"
                return $false
            }
        }
        catch {
            Write-ErrorMessage "Failed to check $package`: $_"
            return $false
        }
    }

    return $true
}

function Invoke-Tests {
    param(
        [string]$TestPath,
        [bool]$UseCoverage,
        [bool]$DetailedOutput,
        [bool]$HtmlReport,
        [bool]$XmlReport,
        [bool]$LuaCoverage
    )

    Write-Header "Running Tests"

    # Build pytest command
    $pytestArgs = @()

    if ($DetailedOutput) {
        $pytestArgs += "-v"
    } else {
        $pytestArgs += "-q"
    }

    # Add test path
    $pytestArgs += $TestPath

    # Build coverage command if needed
    if ($UseCoverage) {
        Write-Info "Running tests with coverage analysis..."

        # Set Lua coverage environment variable if requested
        $originalLuaCoverage = $env:LUA_COVERAGE
        if ($LuaCoverage) {
            $env:LUA_COVERAGE = "1"
            Write-Info "Lua coverage tracking enabled"
        }

        $coverageArgs = @("run", "--source=tests", "-m", "pytest") + $pytestArgs

        try {
            & coverage $coverageArgs
            if ($LASTEXITCODE -ne 0) {
                Write-ErrorMessage "Tests failed with exit code $LASTEXITCODE"
                return $false
            }
        }
        catch {
            Write-ErrorMessage "Failed to run coverage: $_"
            return $false
        }
        finally {
            # Restore original environment variable
            if ($LuaCoverage) {
                $env:LUA_COVERAGE = $originalLuaCoverage
            }
        }

        # Generate coverage report
        Write-Info "Generating coverage report..."
        & coverage report --show-missing

        if ($HtmlReport) {
            Write-Info "Generating HTML coverage report..."
            & coverage html
            Write-Success "HTML report generated in htmlcov/"
        }

        if ($XmlReport) {
            Write-Info "Generating XML coverage report..."
            & coverage xml
            Write-Success "XML report generated as coverage.xml"
        }

        # Check for Lua coverage data
        if ($LuaCoverage -and (Test-Path "lua_coverage.json")) {
            Write-Info "Lua coverage data found. Generating Lua coverage summary..."
            try {
                $luaCoverageData = Get-Content "lua_coverage.json" | ConvertFrom-Json
                Write-ColoredOutput "`n=== Lua Coverage Summary ===" $Cyan

                $totalFiles = 0
                $totalLines = 0
                $coveredLines = 0

                foreach ($file in $luaCoverageData.PSObject.Properties) {
                    $filename = $file.Name
                    $fileData = $file.Value
                    $fileTotalLines = 0
                    $fileCoveredLines = 0

                    foreach ($line in $fileData.PSObject.Properties) {
                        $executionCount = [int]$line.Value
                        $fileTotalLines++
                        if ($executionCount -gt 0) {
                            $fileCoveredLines++
                        }
                    }

                    $fileCoveragePercent = if ($fileTotalLines -gt 0) { [math]::Round(($fileCoveredLines / $fileTotalLines) * 100, 2) } else { 0 }
                    Write-ColoredOutput "$filename`: $fileCoveredLines/$fileTotalLines lines ($fileCoveragePercent%)" $White

                    $totalFiles++
                    $totalLines += $fileTotalLines
                    $coveredLines += $fileCoveredLines
                }

                $overallCoveragePercent = if ($totalLines -gt 0) { [math]::Round(($coveredLines / $totalLines) * 100, 2) } else { 0 }
                Write-ColoredOutput "`nOverall Lua Coverage: $coveredLines/$totalLines lines ($overallCoveragePercent%) across $totalFiles files" $Green
            }
            catch {
                Write-ErrorMessage "Failed to process Lua coverage data: $_"
            }
        }
    } else {
        Write-Info "Running tests without coverage (fast mode)..."

        try {
            & pytest $pytestArgs
            if ($LASTEXITCODE -ne 0) {
                Write-ErrorMessage "Tests failed with exit code $LASTEXITCODE"
                return $false
            }
        }
        catch {
            Write-ErrorMessage "Failed to run pytest: $_"
            return $false
        }
    }

    return $true
}

function Show-Help {
    Write-Header "Test Runner Help"

    Write-ColoredOutput "This script runs the Python test suite for the Pit Boss Grill driver." $White
    Write-ColoredOutput "" $White
    Write-ColoredOutput "Usage:" $Cyan
    Write-ColoredOutput "  .\test.ps1 [options]" $White
    Write-ColoredOutput "" $White
    Write-ColoredOutput "Options:" $Cyan
    Write-ColoredOutput "  -TestPath <path>     Run specific test file or directory (default: tests/)" $White
    Write-ColoredOutput "  -NoCoverage          Skip coverage reporting for faster execution" $White
    Write-ColoredOutput "  -DetailedOutput     Enable detailed test output" $White
    Write-ColoredOutput "  -HtmlReport          Generate HTML coverage report" $White
    Write-ColoredOutput "  -XmlReport           Generate XML coverage report for CI/CD" $White
    Write-ColoredOutput "  -LuaCoverage         Enable Lua source code coverage tracking" $White
    Write-ColoredOutput "" $White
    Write-ColoredOutput "Examples:" $Cyan
    Write-ColoredOutput "  .\test.ps1                           # Run all tests with coverage" $White
    Write-ColoredOutput "  .\test.ps1 -DetailedOutput          # Run with detailed output" $White
    Write-ColoredOutput "  .\test.ps1 -NoCoverage              # Run fast without coverage" $White
    Write-ColoredOutput "  .\test.ps1 -TestPath tests/test_temperature_calibration.py" $White
    Write-ColoredOutput "  .\test.ps1 -HtmlReport              # Generate HTML coverage report" $White
    Write-ColoredOutput "  .\test.ps1 -LuaCoverage             # Run with Lua coverage tracking" $White
    Write-ColoredOutput "  .\test.ps1 -LuaCoverage -HtmlReport # Run with Lua coverage and HTML report" $White
}

# Main execution
function Main {
    Write-Header "Pit Boss Grill Driver Test Runner"
    Write-ColoredOutput "Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" $White
    Write-ColoredOutput "PowerShell Version: $($PSVersionTable.PSVersion)" $White

    # Show help if requested
    if ($args -contains "-h" -or $args -contains "--help" -or $args -contains "-?") {
        Show-Help
        return
    }

    # Validate test path
    if (-not (Test-Path $TestPath)) {
        Write-ErrorMessage "Test path does not exist: $TestPath"
        return
    }

    # Setup environment
    if (-not (Test-VirtualEnvironment)) {
        return
    }

    if (-not (Test-PythonDependencies)) {
        Write-ErrorMessage "Please install missing dependencies: pip install pytest coverage lupa"
        return
    }

    # Run tests
    $success = Invoke-Tests -TestPath $TestPath -UseCoverage (-not $NoCoverage) -DetailedOutput $DetailedOutput -HtmlReport $HtmlReport -XmlReport $XmlReport -LuaCoverage $LuaCoverage

    # Summary
    Write-Header "Test Run Complete"

    if ($success) {
        Write-Success "All tests completed successfully!"

        if (-not $NoCoverage) {
            Write-Info "Coverage report generated. Check coverage.xml or htmlcov/ for details."
        }
    } else {
        Write-ErrorMessage "Test run failed. Check output above for details."
        exit 1
    }
}

# Run main function
try {
    Main
}
catch {
    Microsoft.PowerShell.Utility\Write-Error "Unexpected error: $_"
    Microsoft.PowerShell.Utility\Write-Error "Stack trace: $($_.ScriptStackTrace)"
    exit 1
}
