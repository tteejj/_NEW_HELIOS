# Test script to diagnose and fix rendering issues
# Run this to test the fixed TUI engine

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# Get the directory where this script is located
$script:BasePath = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "PMC Terminal - Render Fix Test" -ForegroundColor Cyan
Write-Host "==============================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Load modules in correct order
Write-Host "Loading modules..." -ForegroundColor Yellow

try {
    # Load core modules first
    Import-Module "$BasePath\modules\exceptions.psm1" -Force -Global
    Import-Module "$BasePath\modules\logger.psm1" -Force -Global
    Initialize-Logger
    
    # Load theme support
    Import-Module "$BasePath\modules\theme-support.psm1" -Force -Global
    
    # CRITICAL: Use the FIXED TUI engine
    Write-Host "Loading FIXED TUI engine..." -ForegroundColor Green
    Import-Module "$BasePath\modules\tui-engine-fixed.psm1" -Force -Global
    
    # Load UI components
    Import-Module "$BasePath\ui\helios-panels.psm1" -Force -Global
    Import-Module "$BasePath\ui\helios-components.psm1" -Force -Global
    
    Write-Host "Modules loaded successfully!" -ForegroundColor Green
    Write-Host ""
    
} catch {
    Write-Host "Failed to load modules: $_" -ForegroundColor Red
    exit 1
}

# Step 2: Create a simple test screen
Write-Host "Creating test screen..." -ForegroundColor Yellow

$testScreen = [PSCustomObject]@{
    Name = "TestScreen"
    _rootPanel = $null
}

# Add Init method
$testScreen | Add-Member -MemberType ScriptMethod -Name Init -Value {
    param($Services)
    Write-Host "Test screen initialized" -ForegroundColor Green
}

# Add OnEnter method
$testScreen | Add-Member -MemberType ScriptMethod -Name OnEnter -Value {
    Write-Host "Test screen entered" -ForegroundColor Green
}

# Add OnExit method
$testScreen | Add-Member -MemberType ScriptMethod -Name OnExit -Value {
    Write-Host "Test screen exited" -ForegroundColor Green
}

# Add HandleInput method
$testScreen | Add-Member -MemberType ScriptMethod -Name HandleInput -Value {
    param($Key)
    if ($Key.Key -eq [ConsoleKey]::Escape -or $Key.Key -eq [ConsoleKey]::Q) {
        Write-Host "`nExit key pressed" -ForegroundColor Yellow
        Stop-TuiEngine
        return $true
    }
    if ($Key.Key -eq [ConsoleKey]::Enter) {
        Write-Host "`nEnter key pressed - Button would be clicked here" -ForegroundColor Cyan
        Request-TuiRefresh
        return $true
    }
    return $false
}

# Create the UI
Write-Host "Building test UI..." -ForegroundColor Yellow

# Create root panel
$rootPanel = New-HeliosStackPanel -Props @{
    Name = "TestRootPanel"
    X = 5
    Y = 2
    Width = 70
    Height = 20
    ShowBorder = $true
    BorderColor = "Accent"
    Title = " Render Test Screen "
    Orientation = "Vertical"
    Spacing = 1
    Padding = 2
    Visible = $true
}

# Add a label
$label = New-HeliosLabel -Props @{
    Name = "TestLabel"
    Text = "If you can see this, rendering is working!"
    Width = 60
    Height = 1
    Visible = $true
    ForegroundColor = [ConsoleColor]::Green
}
$rootPanel.AddChild($label)

# Add some buttons
$button1 = New-HeliosButton -Props @{
    Name = "TestButton1"
    Text = "Working Button (Press Enter)"
    Width = 30
    Height = 3
    Visible = $true
    IsFocusable = $true
    OnClick = {
        Write-Host "`nButton 1 clicked!" -ForegroundColor Green
    }
}
$rootPanel.AddChild($button1)

$button2 = New-HeliosButton -Props @{
    Name = "TestButton2"
    Text = "Another Button"
    Width = 30
    Height = 3
    Visible = $true
    IsFocusable = $true
    OnClick = {
        Write-Host "`nButton 2 clicked!" -ForegroundColor Green
    }
}
$rootPanel.AddChild($button2)

# Add status label
$statusLabel = New-HeliosLabel -Props @{
    Name = "StatusLabel"
    Text = "Press ESC or Q to exit, Tab to switch buttons, Enter to click"
    Width = 60
    Height = 1
    Visible = $true
    ForegroundColor = [ConsoleColor]::DarkGray
}
$rootPanel.AddChild($statusLabel)

# Attach root panel to screen
$testScreen._rootPanel = $rootPanel
$testScreen | Add-Member -MemberType NoteProperty -Name RootPanel -Value $rootPanel -Force

Write-Host "Test UI built successfully!" -ForegroundColor Green
Write-Host ""

# Step 3: Initialize TUI and run
Write-Host "Starting TUI engine..." -ForegroundColor Yellow
Write-Host "Console size: $([Console]::WindowWidth)x$([Console]::WindowHeight)" -ForegroundColor Gray
Write-Host ""

try {
    # Initialize TUI
    Initialize-TuiEngine
    
    # Create minimal services object
    $services = [PSCustomObject]@{}
    
    # Push the test screen
    Push-Screen -Screen $testScreen -Services $services
    
    # Add a debug render to see immediate results
    Write-Host "Forcing initial render..." -ForegroundColor Yellow
    Request-TuiRefresh
    Render-Frame
    
    Write-Host "`nStarting main loop..." -ForegroundColor Green
    Write-Host "You should now see the UI. If the screen is black, rendering is still broken." -ForegroundColor Yellow
    Write-Host ""
    
    # Start the main loop
    Start-TuiLoop
    
} catch {
    Write-Host "`nError during TUI operation: $_" -ForegroundColor Red
    Write-Host "Stack trace:" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Gray
} finally {
    Write-Host "`nCleaning up..." -ForegroundColor Yellow
    Cleanup-TuiEngine
    Write-Host "Test complete!" -ForegroundColor Green
}
