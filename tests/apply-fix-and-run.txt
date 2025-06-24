# Apply the render fix and start PMC Terminal
$ErrorActionPreference = "Stop"
$script:BasePath = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "PMC Terminal - Applying Render Fix" -ForegroundColor Cyan
Write-Host "==================================" -ForegroundColor Cyan
Write-Host ""

# Backup original file
$originalFile = "$BasePath\modules\tui-engine.psm1"
$backupFile = "$BasePath\modules\tui-engine.psm1.bak"
$fixedFile = "$BasePath\modules\tui-engine-fixed.psm1"

if (Test-Path $fixedFile) {
    Write-Host "Creating backup of original tui-engine.psm1..." -ForegroundColor Yellow
    Copy-Item -Path $originalFile -Destination $backupFile -Force
    
    Write-Host "Applying fixed version..." -ForegroundColor Yellow
    Copy-Item -Path $fixedFile -Destination $originalFile -Force
    
    Write-Host "Fix applied successfully!" -ForegroundColor Green
    Write-Host ""
    
    Write-Host "Starting PMC Terminal with the fix..." -ForegroundColor Cyan
    Write-Host ""
    
    # Start the application
    & "$BasePath\Start-PMCTerminal.ps1"
} else {
    Write-Host "Fixed file not found at: $fixedFile" -ForegroundColor Red
    Write-Host "Please ensure tui-engine-fixed.psm1 exists." -ForegroundColor Red
}
