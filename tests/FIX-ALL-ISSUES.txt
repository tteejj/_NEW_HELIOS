#!/usr/bin/env pwsh
# PMC Terminal v5 - Comprehensive Fix Script
# This script applies all necessary fixes for the black screen and non-responsive button issues

param(
    [switch]$TestOnly,
    [switch]$Verbose
)

$ErrorActionPreference = "Stop"
$script:BasePath = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "`nPMC Terminal v5 - Comprehensive Fix" -ForegroundColor Cyan
Write-Host "===================================" -ForegroundColor Cyan
Write-Host ""

function Write-Status {
    param($Message, $Status = "Info", $Indent = 0)
    $prefix = " " * $Indent
    switch ($Status) {
        "Success" { Write-Host "$prefix✓ $Message" -ForegroundColor Green }
        "Error" { Write-Host "$prefix✗ $Message" -ForegroundColor Red }
        "Warning" { Write-Host "$prefix⚠ $Message" -ForegroundColor Yellow }
        "Info" { Write-Host "$prefix$Message" -ForegroundColor Gray }
        "Action" { Write-Host "$prefix→ $Message" -ForegroundColor Cyan }
    }
}

# Step 1: Verify required files exist
Write-Status "Checking required files..." "Action"
$requiredFiles = @(
    "modules\tui-engine.psm1",
    "modules\exceptions.psm1",
    "modules\logger.psm1",
    "ui\helios-components.psm1",
    "ui\helios-panels.psm1",
    "Start-PMCTerminal.ps1"
)

$allFilesExist = $true
foreach ($file in $requiredFiles) {
    $fullPath = Join-Path $script:BasePath $file
    if (Test-Path $fullPath) {
        Write-Status "$file" "Success" 2
    } else {
        Write-Status "$file - NOT FOUND" "Error" 2
        $allFilesExist = $false
    }
}

if (-not $allFilesExist) {
    Write-Status "Missing required files. Cannot continue." "Error"
    exit 1
}

# Step 2: Apply the fixed TUI engine
Write-Status "`nApplying TUI engine fix..." "Action"

if (Test-Path "$script:BasePath\modules\tui-engine-fixed.psm1") {
    # Backup original
    Copy-Item "$script:BasePath\modules\tui-engine.psm1" "$script:BasePath\modules\tui-engine.psm1.original" -Force
    Copy-Item "$script:BasePath\modules\tui-engine-fixed.psm1" "$script:BasePath\modules\tui-engine.psm1" -Force
    Write-Status "TUI engine fix applied" "Success" 2
} else {
    Write-Status "Fixed TUI engine not found. Fix will be limited." "Warning" 2
}

# Step 3: Run diagnostics if requested
if ($TestOnly) {
    Write-Status "`nRunning diagnostics..." "Action"
    
    # Load modules
    Import-Module "$script:BasePath\modules\exceptions.psm1" -Force
    Import-Module "$script:BasePath\modules\logger.psm1" -Force
    Initialize-Logger
    Import-Module "$script:BasePath\modules\theme-support.psm1" -Force
    Import-Module "$script:BasePath\modules\tui-engine.psm1" -Force
    Import-Module "$script:BasePath\ui\helios-panels.psm1" -Force
    Import-Module "$script:BasePath\ui\helios-components.psm1" -Force
    
    # Test 1: Component creation
    Write-Status "Testing component creation..." "Info" 2
    try {
        $panel = New-HeliosStackPanel -Props @{ Name = "Test"; Visible = $true }
        $button = New-HeliosButton -Props @{ Name = "TestBtn"; Text = "Test" }
        Write-Status "Components created successfully" "Success" 4
    } catch {
        Write-Status "Component creation failed: $_" "Error" 4
    }
    
    # Test 2: Render pipeline
    Write-Status "Testing render pipeline..." "Info" 2
    try {
        Initialize-TuiEngine -Width 80 -Height 24
        Clear-BackBuffer
        Write-BufferString -X 10 -Y 5 -Text "RENDER TEST" -ForegroundColor Green
        Render-BufferOptimized
        Write-Status "Render pipeline working" "Success" 4
    } catch {
        Write-Status "Render pipeline failed: $_" "Error" 4
    }
    
    # Test 3: Button clicks
    Write-Status "Testing button input..." "Info" 2
    $clickWorked = $false
    $testButton = New-HeliosButton -Props @{
        OnClick = { $script:clickWorked = $true }
    }
    $enterKey = [System.ConsoleKeyInfo]::new([char]13, [ConsoleKey]::Enter, $false, $false, $false)
    $testButton.HandleInput($enterKey) | Out-Null
    if ($clickWorked) {
        Write-Status "Button clicks working" "Success" 4
    } else {
        Write-Status "Button clicks not working" "Error" 4
    }
    
    Write-Status "`nDiagnostics complete!" "Success"
    exit 0
}

# Step 4: Start the application
Write-Status "`nStarting PMC Terminal..." "Action"

# Check console size
$width = [Console]::WindowWidth
$height = [Console]::WindowHeight
Write-Status "Console size: ${width}x${height}" "Info" 2

if ($width -lt 80 -or $height -lt 24) {
    Write-Status "Console too small! Minimum 80x24 required." "Error"
    Write-Status "Please resize your terminal window." "Warning"
    exit 1
}

# Add verbose flag if requested
$args = @()
if ($Verbose) {
    $args += "-Verbose"
}

# Clear screen for clean start
Clear-Host

# Start the application
try {
    & "$script:BasePath\Start-PMCTerminal.ps1" @args
} catch {
    Write-Status "`nApplication crashed!" "Error"
    Write-Status "Error: $_" "Error" 2
    Write-Status "Check log at: $(Join-Path $env:TEMP 'PMCTerminal\*.log')" "Info" 2
}

Write-Host ""
