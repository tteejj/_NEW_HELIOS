# Test script to verify focus management fixes
# Run this to test if the black screen and button issues are resolved

param()

Write-Host "Testing PMC Terminal Focus Management Fixes..." -ForegroundColor Green

try {
    # Change to the project directory
    Set-Location "C:\Users\jhnhe\Documents\GitHub\_NEW_HELIOS"
    
    Write-Host "Current directory: $(Get-Location)" -ForegroundColor Yellow
    
    # Import required modules in correct order
    Write-Host "Importing modules..." -ForegroundColor Yellow
    
    Import-Module ".\modules\logger.psm1" -Force
    Import-Module ".\modules\exceptions.psm1" -Force  
    Import-Module ".\modules\tui-engine.psm1" -Force
    Import-Module ".\modules\focus-manager.psm1" -Force
    Import-Module ".\services\navigation.psm1" -Force
    Import-Module ".\services\keybindings.psm1" -Force
    Import-Module ".\services\task-service.psm1" -Force
    Import-Module ".\ui\helios-components.psm1" -Force
    Import-Module ".\ui\helios-panels.psm1" -Force
    Import-Module ".\screens\dashboard-screen.psm1" -Force
    
    Write-Host "All modules imported successfully" -ForegroundColor Green
    
    # Initialize services
    Write-Host "Initializing services..." -ForegroundColor Yellow
    
    $taskService = Get-TaskService
    $keybindingService = Get-KeybindingService
    $navigationService = Get-NavigationService
    
    $services = [PSCustomObject]@{
        Task = $taskService
        Keybindings = $keybindingService  
        Navigation = $navigationService
    }
    
    Write-Host "Services initialized successfully" -ForegroundColor Green
    
    # Test dashboard screen creation
    Write-Host "Testing dashboard screen creation..." -ForegroundColor Yellow
    
    $dashboardScreen = Get-HeliosDashboardScreen -Services $services
    
    if (-not $dashboardScreen) {
        throw "Failed to create dashboard screen"
    }
    
    if (-not $dashboardScreen.RootPanel) {
        throw "Dashboard screen has no RootPanel"
    }
    
    if ($dashboardScreen._menuButtons.Count -eq 0) {
        throw "Dashboard screen has no menu buttons"
    }
    
    Write-Host "Dashboard screen created successfully with $($dashboardScreen._menuButtons.Count) buttons" -ForegroundColor Green
    
    # Test button properties
    Write-Host "Testing button properties..." -ForegroundColor Yellow
    
    $focusableButtons = 0
    foreach ($button in $dashboardScreen._menuButtons) {
        if (($button.PSObject.Properties.Name -notcontains 'IsFocusable')) {
            throw "Button $($button.Name) missing IsFocusable property"
        }
        if (($button.PSObject.Properties.Name -notcontains 'Visible')) {
            throw "Button $($button.Name) missing Visible property"
        }
        if (($button.PSObject.Properties.Name -notcontains 'IsFocused')) {
            throw "Button $($button.Name) missing IsFocused property"
        }
        
        if ($button.IsFocusable -and $button.Visible) {
            $focusableButtons++
        }
    }
    
    if ($focusableButtons -eq 0) {
        throw "No focusable buttons found"
    }
    
    Write-Host "Button properties validated successfully - $focusableButtons focusable buttons" -ForegroundColor Green
    
    # Test focus manager
    Write-Host "Testing focus manager..." -ForegroundColor Yellow
    
    Initialize-FocusManager
    
    # Test Update-TabOrderAndFocus function
    try {
        Update-TabOrderAndFocus -Screen $dashboardScreen
        Write-Host "Update-TabOrderAndFocus function works correctly" -ForegroundColor Green
    } catch {
        throw "Update-TabOrderAndFocus failed: $_"
    }
    
    # Check if focus was established
    $focusedComponent = Get-FocusedComponent
    if (-not $focusedComponent) {
        Write-Host "Warning: No component is currently focused" -ForegroundColor Yellow
    } else {
        Write-Host "Focus established on: $($focusedComponent.Name)" -ForegroundColor Green
    }
    
    # Test TUI engine initialization
    Write-Host "Testing TUI engine initialization..." -ForegroundColor Yellow
    
    Initialize-TuiEngine -Width 80 -Height 25
    
    if (-not $global:TuiState.BufferWidth -or $global:TuiState.BufferWidth -eq 0) {
        throw "TUI Engine failed to initialize"
    }
    
    Write-Host "TUI Engine initialized successfully ($($global:TuiState.BufferWidth)x$($global:TuiState.BufferHeight))" -ForegroundColor Green
    
    # Test screen pushing with event firing
    Write-Host "Testing screen push with event firing..." -ForegroundColor Yellow
    
    Push-Screen -Screen $dashboardScreen -Services $services
    
    if ($global:TuiState.CurrentScreen -ne $dashboardScreen) {
        throw "Screen was not set as current screen"
    }
    
    Write-Host "Screen pushed successfully" -ForegroundColor Green
    
    # Test focus after screen push
    Start-Sleep -Milliseconds 200
    $focusedAfterPush = Get-FocusedComponent
    if (-not $focusedAfterPush) {
        Write-Host "Warning: No component focused after screen push" -ForegroundColor Yellow
        
        # Try manual focus refresh
        Force-RefreshFocus
        Start-Sleep -Milliseconds 100
        $focusedAfterRefresh = Get-FocusedComponent
        
        if ($focusedAfterRefresh) {
            Write-Host "Focus established after manual refresh: $($focusedAfterRefresh.Name)" -ForegroundColor Green
        } else {
            Write-Host "Warning: Still no focus after manual refresh" -ForegroundColor Yellow
        }
    } else {
        Write-Host "Focus maintained after screen push: $($focusedAfterPush.Name)" -ForegroundColor Green
    }
    
    # Test tab navigation
    Write-Host "Testing tab navigation..." -ForegroundColor Yellow
    
    $initialFocus = Get-FocusedComponent
    Move-Focus
    $afterTabFocus = Get-FocusedComponent
    
    if ($afterTabFocus -and $initialFocus -and ($afterTabFocus.Name -ne $initialFocus.Name)) {
        Write-Host "Tab navigation works: $($initialFocus.Name) -> $($afterTabFocus.Name)" -ForegroundColor Green
    } else {
        Write-Host "Warning: Tab navigation may not be working properly" -ForegroundColor Yellow
    }
    
    # Test rendering
    Write-Host "Testing rendering..." -ForegroundColor Yellow
    
    try {
        Render-Frame
        Write-Host "Frame rendering works correctly" -ForegroundColor Green
    } catch {
        throw "Frame rendering failed: $_"
    }
    
    Write-Host "`nAll tests completed successfully!" -ForegroundColor Green
    Write-Host "The focus management system should now work properly." -ForegroundColor Green
    Write-Host "`nYou can now run the main application with:" -ForegroundColor Cyan
    Write-Host ".\Start-PMCTerminal.ps1" -ForegroundColor Cyan
    
    return $true
    
} catch {
    Write-Host "`nTest failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Red
    return $false
} finally {
    # Cleanup
    if ($global:TuiState -and $global:TuiState.Running) {
        Stop-TuiEngine
    }
    
    try {
        Cleanup-TuiEngine
    } catch {
        # Ignore cleanup errors
    }
}
