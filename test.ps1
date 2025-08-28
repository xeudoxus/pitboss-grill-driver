# PowerShell test runner for Pit Boss driver
# Supports enhanced test runner with filtering and verbose options

param(
    [switch]$Verbose,
    [string]$Filter,
    [switch]$NoTiming,
    [switch]$Help
)

# Set UTF-8 encoding
chcp 65001 > $null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Set working directory
Set-Location "c:\Users\Admin\Documents\SmartThingsDrivers\pitboss-grill-driver"

if ($Help) {
    Write-Host "Pit Boss Grill Driver Test Runner" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Usage: .\test.ps1 [options]" -ForegroundColor White
    Write-Host ""
    Write-Host "Options:" -ForegroundColor Yellow
    Write-Host "  -Verbose      Show verbose output including test execution details" -ForegroundColor White
    Write-Host "  -Filter       Run only tests matching the given pattern" -ForegroundColor White
    Write-Host "  -NoTiming     Disable timing information" -ForegroundColor White
    Write-Host "  -Help         Show this help message" -ForegroundColor White
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor Yellow
    Write-Host "  .\test.ps1" -ForegroundColor White
    Write-Host "  .\test.ps1 -Verbose" -ForegroundColor White
    Write-Host "  .\test.ps1 -Filter temperature" -ForegroundColor White
    Write-Host "  .\test.ps1 -Filter command_service" -ForegroundColor White
    exit 0
}

# Build lua command arguments
$luaArgs = @("tests\runner.lua")

if ($Verbose) {
    $luaArgs += "--verbose"
}

if ($Filter) {
    $luaArgs += "--filter"
    $luaArgs += $Filter
}

if ($NoTiming) {
    $luaArgs += "--no-timing"
}

Write-Host "Running test suite..." -ForegroundColor Green
if ($Verbose) {
    Write-Host "Command: lua $($luaArgs -join ' ')" -ForegroundColor Gray
}

# Execute the test runner
& lua $luaArgs

# Exit with the same code as the test runner
exit $LASTEXITCODE