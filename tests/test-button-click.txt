# Minimal test to verify button clicks work
$ErrorActionPreference = "Stop"
$script:BasePath = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "`nButton Click Test" -ForegroundColor Cyan
Write-Host "=================" -ForegroundColor Cyan

# Load modules
Import-Module "$BasePath\modules\exceptions.psm1" -Force
Import-Module "$BasePath\modules\logger.psm1" -Force
Initialize-Logger
Import-Module "$BasePath\ui\helios-components.psm1" -Force

Write-Host "`nCreating test button..." -ForegroundColor Yellow

# Create a simple button
$testButton = New-HeliosButton -Props @{
    Name = "TestButton"
    Text = "Click Me"
    IsFocusable = $true
    OnClick = {
        Write-Host "BUTTON CLICKED! OnClick handler executed!" -ForegroundColor Green -BackgroundColor DarkGreen
    }
}

Write-Host "Button created: $($testButton.Name)" -ForegroundColor Green
Write-Host "OnClick defined: $(if ($testButton.OnClick) { 'Yes' } else { 'No' })" -ForegroundColor Gray

# Test the OnClick directly
Write-Host "`nTesting OnClick directly..." -ForegroundColor Yellow
try {
    if ($testButton.OnClick) {
        & $testButton.OnClick
        Write-Host "✓ Direct OnClick call successful" -ForegroundColor Green
    } else {
        Write-Host "✗ OnClick is null!" -ForegroundColor Red
    }
} catch {
    Write-Host "✗ OnClick execution failed: $_" -ForegroundColor Red
}

# Test HandleInput with Enter key
Write-Host "`nTesting HandleInput with Enter key..." -ForegroundColor Yellow
try {
    $enterKey = [System.ConsoleKeyInfo]::new([char]13, [ConsoleKey]::Enter, $false, $false, $false)
    $handled = $testButton.HandleInput($enterKey)
    Write-Host "HandleInput returned: $handled" -ForegroundColor Gray
    if ($handled) {
        Write-Host "✓ HandleInput processed Enter key" -ForegroundColor Green
    } else {
        Write-Host "✗ HandleInput did not process Enter key" -ForegroundColor Red
    }
} catch {
    Write-Host "✗ HandleInput failed: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Gray
}

Write-Host "`nTest complete!" -ForegroundColor Cyan
