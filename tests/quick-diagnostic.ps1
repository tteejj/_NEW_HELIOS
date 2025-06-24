# Quick diagnostic script to test what's happening
$ErrorActionPreference = "Stop"
$script:BasePath = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "`nPMC Terminal - Quick Diagnostic Test" -ForegroundColor Cyan
Write-Host "====================================" -ForegroundColor Cyan
Write-Host ""

# Load minimal modules
Import-Module "$BasePath\modules\exceptions.psm1" -Force -Global
Import-Module "$BasePath\modules\logger.psm1" -Force -Global
Initialize-Logger

Write-Host "Testing component creation..." -ForegroundColor Yellow

# Test 1: Can we create UI components?
try {
    Import-Module "$BasePath\modules\theme-support.psm1" -Force -Global
    Import-Module "$BasePath\modules\tui-engine.psm1" -Force -Global
    Import-Module "$BasePath\ui\helios-panels.psm1" -Force -Global
    Import-Module "$BasePath\ui\helios-components.psm1" -Force -Global
    
    $testPanel = New-HeliosStackPanel -Props @{
        Name = "TestPanel"
        X = 10
        Y = 5
        Width = 60
        Height = 15
        Visible = $true
        ShowBorder = $true
    }
    
    Write-Host "✓ Panel created successfully" -ForegroundColor Green
    Write-Host "  Panel Name: $($testPanel.Name)" -ForegroundColor Gray
    Write-Host "  Position: X=$($testPanel.X), Y=$($testPanel.Y)" -ForegroundColor Gray
    Write-Host "  Size: $($testPanel.Width)x$($testPanel.Height)" -ForegroundColor Gray
    Write-Host "  Has Render method: $(if ($testPanel.PSObject.ScriptMethods['Render']) { 'Yes' } else { 'No' })" -ForegroundColor Gray
    
} catch {
    Write-Host "✗ Failed to create panel: $_" -ForegroundColor Red
}

# Test 2: Check TUI state
Write-Host "`nChecking TUI state..." -ForegroundColor Yellow
if ($global:TuiState) {
    Write-Host "✓ TUI state exists" -ForegroundColor Green
    Write-Host "  Buffer size: $($global:TuiState.BufferWidth)x$($global:TuiState.BufferHeight)" -ForegroundColor Gray
    Write-Host "  Current screen: $(if ($global:TuiState.CurrentScreen) { $global:TuiState.CurrentScreen.Name } else { 'None' })" -ForegroundColor Gray
} else {
    Write-Host "✗ TUI state not found" -ForegroundColor Red
}

# Test 3: Check if Write-BufferString exists
Write-Host "`nChecking buffer functions..." -ForegroundColor Yellow
$bufferFuncs = @('Write-BufferString', 'Write-BufferBox', 'Clear-BackBuffer', 'Render-Frame')
foreach ($func in $bufferFuncs) {
    if (Get-Command $func -ErrorAction SilentlyContinue) {
        Write-Host "✓ $func exists" -ForegroundColor Green
    } else {
        Write-Host "✗ $func not found" -ForegroundColor Red
    }
}

# Test 4: Try a minimal render
Write-Host "`nTesting minimal render..." -ForegroundColor Yellow
try {
    Initialize-TuiEngine -Width 80 -Height 24
    Clear-BackBuffer
    Write-BufferString -X 10 -Y 5 -Text "TEST RENDER" -ForegroundColor ([ConsoleColor]::Green)
    Write-BufferBox -X 5 -Y 3 -Width 30 -Height 5 -BorderColor ([ConsoleColor]::Cyan)
    
    Write-Host "✓ Buffer operations successful" -ForegroundColor Green
    Write-Host "  Attempting to render to screen..." -ForegroundColor Gray
    
    # Try to render
    Render-BufferOptimized
    
    Write-Host "✓ Render completed" -ForegroundColor Green
    
} catch {
    Write-Host "✗ Render test failed: $_" -ForegroundColor Red
    Write-Host "Stack trace:" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Gray
}

Write-Host "`nDiagnostic complete. Check the log file for details." -ForegroundColor Cyan
Write-Host "Log location: $(Get-LogPath)" -ForegroundColor Gray
