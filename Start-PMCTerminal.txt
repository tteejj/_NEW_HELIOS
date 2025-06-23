# FILE: Start-PMCTerminal.ps1
# PURPOSE: Main entry point for the PMC Terminal v5 application.
#          Orchestrates module loading, service initialization, and application startup,
#          adhering to the PowerShell-First architectural principles.

# Set strict mode for better error handling
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Get the directory where this script is located
$script:BasePath = Split-Path -Parent $MyInvocation.MyCommand.Path

#region --- Module Definitions ---
# Module loading order is critical - dependencies must load first.
# This list defines the modules to be loaded and their relative paths.
$script:ModulesToLoad = @(
    # Foundation Modules (pre-loaded before this list, but included for conceptual completeness)
     #@{ Name = "exceptions"; Path = "modules\exceptions.psm1"; Required = $true },
     #@{ Name = "logger"; Path = "modules\logger.psm1"; Required = $true },

    # Core Application Modules (ordered by dependency)
    # NOTE: event-system removed - using PowerShell native eventing
    @{ Name = "theme-support"; Path = "modules\theme-support.psm1"; Required = $true },
    # NOTE: data-manager removed - services manage their own data
    @{ Name = "focus-manager"; Path = "modules\focus-manager.psm1"; Required = $true },
    @{ Name = "tui-engine"; Path = "modules\tui-engine.psm1"; Required = $true },
    @{ Name = "dialog-system"; Path = "modules\dialog-system.psm1"; Required = $true },

    # UI Modules (depend on tui-engine, theme-manager, focus-manager)
    @{ Name = "helios-panels"; Path = "ui\helios-panels.psm1"; Required = $true },
    @{ Name = "helios-components"; Path = "ui\helios-components.psm1"; Required = $true },

    # Service Modules (depend on others)
    @{ Name = "task-service"; Path = "services\task-service.psm1"; Required = $true },
    @{ Name = "keybindings"; Path = "services\keybindings.psm1"; Required = $true },
    @{ Name = "navigation"; Path = "services\navigation.psm1"; Required = $true }
)

# Screen Modules (loaded after all core modules and services, as they depend on them)
# These are loaded as modules, but their actual screen instances are created via factories
# registered with the NavigationService.
$script:ScreenModules = @(
    "dashboard-screen",
    "task-screen"
    # Add other screens here as they are developed
)
#endregion

#region --- Helper Functions ---

function Load-PMCTerminalModules {
    param([bool]$Silent = $false)
    
    Invoke-WithErrorHandling -Component "ModuleLoader" -Context @{ Operation = "Load-PMCTerminalModules" } -ScriptBlock {
        Write-Log -Level Trace -Message "Starting module loading sequence."
        
        if (-not $Silent) { Write-Host "Initializing PMC Terminal v5..." -ForegroundColor Cyan }
        
        $loadedModules = @()
        
        foreach ($module in $script:ModulesToLoad) {
            $modulePath = Join-Path $script:BasePath $module.Path
            
            Write-Log -Level Trace -Message "Attempting to load module." -Data @{
                ModuleName = $module.Name
                ModulePath = $modulePath
                Required = $module.Required
            }
            
            try {
                if (Test-Path $modulePath) {
                    if (-not $Silent) { Write-Host "  Loading $($module.Name)..." -ForegroundColor Gray }
                    Import-Module $modulePath -Force -Global -ErrorAction Stop
                    $loadedModules += $module.Name
                    Write-Log -Level Debug -Message "Module loaded successfully." -Data @{ ModuleName = $module.Name }
                } elseif ($module.Required) { 
                    $errorMsg = "Required module not found: $($module.Name) at $modulePath"
                    Write-Log -Level Error -Message $errorMsg -Force
                    throw $errorMsg
                } else {
                    if (-not $Silent) { Write-Host "  Optional module $($module.Name) not found: $modulePath (Skipping)" -ForegroundColor Yellow }
                    Write-Log -Level Warn -Message "Optional module not found, skipping." -Data @{ ModuleName = $module.Name; Path = $modulePath }
                }
            } catch {
                $errorMsg = "Failed to load module $($module.Name): $($_.Exception.Message)"
                Write-Log -Level Error -Message $errorMsg -Data @{
                    ModuleName = $module.Name
                    ModulePath = $modulePath
                    Exception = $_.Exception.Message
                    StackTrace = $_.ScriptStackTrace
                } -Force
                throw $errorMsg # Re-throw for Invoke-WithErrorHandling to catch
            }
        }
        
        if (-not $Silent) { Write-Host "Loaded $($loadedModules.Count) core modules successfully." -ForegroundColor Green }
        Write-Log -Level Info -Message "Core modules loaded." -Data @{ LoadedCount = $loadedModules.Count; Modules = $loadedModules }
        return $loadedModules
    } -ErrorHandler {
        param($Exception)
        Write-Log -Level Fatal -Message "Critical error during module loading: $($Exception.Message)" -Data $Exception.Context -Force
        throw # Re-throw to main error handler
    }
}

function Initialize-PMCTerminalServices {
    param([bool]$Silent = $false)
    
    Invoke-WithErrorHandling -Component "ServiceInitializer" -Context @{ Operation = "Initialize-PMCTerminalServices" } -ScriptBlock {
        Write-Log -Level Trace -Message "Starting service initialization."
        if (-not $Silent) { Write-Host "Initializing services..." -ForegroundColor Cyan }
        
        $services = [PSCustomObject]@{} # Use PSCustomObject for services collection
        
        # Initialize TaskService
        if (Get-Command -Name "Initialize-TaskService" -ErrorAction SilentlyContinue) {
            $services | Add-Member -MemberType NoteProperty -Name Task -Value (Initialize-TaskService)
            if (-not $services.Task) { throw "Failed to initialize TaskService." }
            Write-Log -Level Debug -Message "TaskService initialized."
        } else {
            Write-Log -Level Warn -Message "Initialize-TaskService not found. Task functionality will be limited."
        }

        # Initialize KeybindingService
        if (Get-Command -Name "Initialize-KeybindingService" -ErrorAction SilentlyContinue) {
            $services | Add-Member -MemberType NoteProperty -Name Keybindings -Value (Initialize-KeybindingService)
            if (-not $services.Keybindings) { throw "Failed to initialize KeybindingService." }
            Write-Log -Level Debug -Message "KeybindingService initialized."
        } else {
            Write-Log -Level Warn -Message "Initialize-KeybindingService not found. Keybinding functionality will be limited."
        }

        # Initialize NavigationService
        if (Get-Command -Name "Initialize-NavigationService" -ErrorAction SilentlyContinue) {
            $services | Add-Member -MemberType NoteProperty -Name Navigation -Value (Initialize-NavigationService)
            if (-not $services.Navigation) { throw "Failed to initialize NavigationService." }
            Write-Log -Level Debug -Message "NavigationService initialized."
        } else {
            Write-Log -Level Fatal -Message "Initialize-NavigationService not found. Application cannot navigate."
            throw "NavigationService is critical and missing."
        }
        
        if (-not $Silent) { Write-Host "Services initialized successfully." -ForegroundColor Green }
        Write-Log -Level Info -Message "All core services initialized." -Data @{ ServiceCount = $services.PSObject.Properties.Count }
        
        return $services
    } -ErrorHandler {
        param($Exception)
        Write-Log -Level Fatal -Message "Critical error during service initialization: $($Exception.Message)" -Data $Exception.Context -Force
        throw # Re-throw to main error handler
    }
}

function Register-PMCTerminalScreens {
    param(
        [PSCustomObject]$Services,
        [bool]$Silent = $false
    )
    
    Invoke-WithErrorHandling -Component "ScreenRegistration" -Context @{ Operation = "Register-PMCTerminalScreens" } -ScriptBlock {
        if (-not $Services) { throw "Services object is null, cannot register screens." }
        if (-not $Services.Navigation) { throw "Navigation service is null, cannot register screens." }

        Write-Log -Level Trace -Message "Starting screen module loading and route registration."
        if (-not $Silent) { Write-Host "Loading screens and registering routes..." -ForegroundColor Cyan }
        
        $registeredScreens = @()
        
        foreach ($screenName in $script:ScreenModules) {
            $screenPath = Join-Path $script:BasePath "screens\$screenName.psm1"
            
            Write-Log -Level Trace -Message "Processing screen module for registration." -Data @{ ScreenName = $screenName; ScreenPath = $screenPath }
            
            try {
                if (Test-Path $screenPath) {
                    if (-not $Silent) { Write-Host "  Loading $($screenName)..." -ForegroundColor Gray }
                    Import-Module $screenPath -Force -Global -ErrorAction SilentlyContinue
                    
                    # FIX: Add "Helios" prefix to dynamically generated function name
                    $factoryFunctionName = "Get-Helios" + ((($screenName -split "-") | ForEach-Object { 
                        $_.Substring(0,1).ToUpper() + $_.Substring(1) 
                    }) -join "") + "Screen" # e.g., Get-HeliosDashboardScreen, Get-HeliosTaskScreen

                    if (Get-Command -Name $factoryFunctionName -ErrorAction SilentlyContinue) {
                        # Register the route with the NavigationService
                        $path = "/$($screenName -replace '-','/')" # e.g., /dashboard, /task
                        
                        # Special handling for task-screen if it has multiple entry points (as per legacy)
                        if ($screenName -eq "task-screen") {
                            # Assuming Get-TaskScreen is the primary entry for /task
                            $Services.Navigation.RegisterRoute($path, { param($Services) & $factoryFunctionName -Services $Services })
                            Write-Log -Level Debug -Message "Registered route for '$screenName' at '$path' using '$factoryFunctionName'."
                        } else {
                            $Services.Navigation.RegisterRoute($path, { param($Services) & $factoryFunctionName -Services $Services })
                            Write-Log -Level Debug -Message "Registered route for '$screenName' at '$path' using '$factoryFunctionName'."
                        }
                        $registeredScreens += $screenName
                    } else {
                        Write-Log -Level Warn -Message "Expected screen factory function '$factoryFunctionName' not found for module '$screenName'. Skipping route registration."
                    }
                } else { 
                    if (-not $Silent) { Write-Host "  Screen module not found: $screenName at $screenPath (Skipping)" -ForegroundColor Yellow }
                    Write-Log -Level Warn -Message "Screen module file not found, skipping." -Data @{ ScreenName = $screenName; Path = $screenPath }
                }
            } catch { 
                $errorMsg = "Failed to load or register screen '$screenName': $($_.Exception.Message)"
                Write-Log -Level Error -Message $errorMsg -Data @{
                    ScreenName = $screenName
                    ScreenPath = $screenPath
                    Exception = $_.Exception.Message
                    StackTrace = $_.ScriptStackTrace
                }
                if (-not $Silent) { Write-Host "  $errorMsg" -ForegroundColor Red }
            }
        }
        
        if (-not $Silent) { Write-Host "Registered $($registeredScreens.Count) screens successfully." -ForegroundColor Green }
        Write-Log -Level Info -Message "Screens loaded and routes registered." -Data @{ RegisteredCount = $registeredScreens.Count; Screens = $registeredScreens }
        return $registeredScreens
    } -ErrorHandler {
        param($Exception)
        Write-Log -Level Fatal -Message "Critical error during screen registration: $($Exception.Message)" -Data $Exception.Context -Force
        throw # Re-throw to main error handler
    }
}

#endregion

#region --- Main Application Entry Point ---

function Start-PMCTerminal {
    param([bool]$Silent = $false)
    
    Invoke-WithErrorHandling -Component "Start-PMCTerminal" -Context @{ SilentMode = $Silent } -ScriptBlock {
        Write-Log -Level Info -Message "PMC Terminal v5 startup initiated."
        
        # 1. Console Size Check
        $minWidth = 80
        $minHeight = 24
        if ($Host.UI.RawUI) {
            $currentWidth = $Host.UI.RawUI.WindowSize.Width
            $currentHeight = $Host.UI.RawUI.WindowSize.Height
            if ($currentWidth -lt $minWidth -or $currentHeight -lt $minHeight) {
                Write-Host "Console window too small!" -ForegroundColor Red
                Write-Host "Current size: ${currentWidth}x${currentHeight}" -ForegroundColor Yellow
                Write-Host "Minimum required: ${minWidth}x${minHeight}" -ForegroundColor Green
                Write-Host "Please resize your console window and try again." -ForegroundColor White
                Write-Host "Press any key to exit..." -ForegroundColor Gray
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                exit 1
            }
        }
        Write-Log -Level Debug -Message "Console size check passed." -Data @{ Width = $currentWidth; Height = $currentHeight }

        # 2. Load all necessary modules
        $loadedModules = Load-PMCTerminalModules -Silent:$Silent
        Write-Log -Level Info -Message "All core modules loaded: $($loadedModules -join ', ')."

        # 3. Initialize TUI Engine (requires event-system and logger)
        if (Get-Command -Name "Initialize-TuiEngine" -ErrorAction SilentlyContinue) {
            Initialize-TuiEngine
            Write-Log -Level Info -Message "TUI Engine initialized successfully."
        } else {
            throw "TUI Engine initialization function 'Initialize-TuiEngine' not found."
        }

        # 4. Initialize Services
        $services = Initialize-PMCTerminalServices -Silent:$Silent
        # Make services globally accessible for screen factories and TUI engine's event handlers
        # This is the ONLY allowed global variable for services, passed explicitly to components.
        $global:Services = $services 
        Write-Log -Level Info -Message "All services initialized and set to `$global:Services."

        # 5. Register Screens (routes) with Navigation Service
        $registeredScreens = Register-PMCTerminalScreens -Services $services -Silent:$Silent
        Write-Log -Level Info -Message "All screens loaded and routes registered: $($registeredScreens -join ', ')."

        if (-not $Silent) { Write-Host "`nStarting application..." -ForegroundColor Green }
        
        # 6. Navigate to the initial screen
        $startPath = "/dashboard"
        if ($args -contains "-start") {
            $startIndex = [array]::IndexOf($args, "-start")
            if (($startIndex + 1) -lt $args.Count) { 
                $startPath = $args[$startIndex + 1] 
                Write-Log -Level Debug -Message "Custom start path specified." -Data @{ CustomPath = $startPath }
            }
        }
        
        if ($services.Navigation.IsValidRoute($startPath)) {
            Write-Log -Level Info -Message "Navigating to initial screen: $startPath."
            $services.Navigation.GoTo($startPath, $services)
        } else {
            Write-Log -Level Warning -Message "Startup path '$startPath' is not valid. Defaulting to /dashboard."
            $services.Navigation.GoTo("/dashboard", $services)
        }
        
        # 7. Start the main TUI loop
        if (Get-Command -Name "Start-TuiLoop" -ErrorAction SilentlyContinue) {
            Write-Log -Level Info -Message "Starting TUI main loop."
            Start-TuiLoop
        } else {
            throw "TUI main loop function 'Start-TuiLoop' not found."
        }
        
        Write-Log -Level Info -Message "PMC Terminal exited gracefully."
        return $true

    } -ErrorHandler {
        param($Exception, $DetailedError)
        
        # This is the top-level error handler for the application startup.
        # It should provide user-friendly feedback and diagnostic information.
        Write-Host "`n=== CRITICAL FAILURE ===" -ForegroundColor Red
        Write-Host "Fatal error occurred during PMC Terminal startup." -ForegroundColor Red
        
        $errorMessage = if ($Exception.Message) { $Exception.Message } else { "Unknown error" }
        Write-Host "Error: $errorMessage" -ForegroundColor Red
        
        $component = if ($Exception.Context -and $Exception.Context.ContainsKey("Component")) { $Exception.Context.Component } else { "Unknown" }
        Write-Host "Component: $component" -ForegroundColor Yellow
        
        Write-Host "`nDetailed Error Information:" -ForegroundColor Yellow
        if ($DetailedError) {
            Write-Host "Type: $($DetailedError.Type)" -ForegroundColor Gray
            Write-Host "Category: $($DetailedError.Category)" -ForegroundColor Gray
            Write-Host "Location: $($DetailedError.ScriptName):$($DetailedError.LineNumber)" -ForegroundColor Gray
            
            if ($DetailedError.StackTrace -and $DetailedError.StackTrace.Count -gt 0) {
                Write-Host "`nCall Stack (top 5 frames):" -ForegroundColor Yellow
                for ($i = 0; $i -lt [Math]::Min(5, $DetailedError.StackTrace.Count); $i++) {
                    $frame = $DetailedError.StackTrace[$i]
                    Write-Host "  [$i] $($frame.Command) at $($frame.Location)" -ForegroundColor Gray
                }
            }
        }
        
        # Attempt to generate a diagnostic report if logger is available
        if (Get-Command -Name "Get-HeliosDiagnosticReport" -ErrorAction SilentlyContinue) {
            try {
                $report = Get-HeliosDiagnosticReport -IncludeErrorHistory -IncludeLogEntries -LogEntryCount 100
                $reportPath = Join-Path $env:TEMP "helios_crash_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
                $report | ConvertTo-Json -Depth 10 | Set-Content $reportPath -Encoding UTF8
                Write-Host "`nDiagnostic report saved to: $reportPath" -ForegroundColor Yellow
                Write-Log -Level Info -Message "Crash diagnostic report saved." -Data @{ ReportPath = $reportPath } -Force
            } catch {
                Write-Host "Failed to generate diagnostic report: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        } else {
            Write-Host "Diagnostic report generation not available." -ForegroundColor Yellow
        }
        
        Write-Host "`nCheck the log file for more details: $(Get-LogPath)" -ForegroundColor Cyan
        Write-Host "`n=== END CRITICAL FAILURE ===" -ForegroundColor Red
        
        # Do not re-throw here, let the finally block handle graceful exit.
        return $false
    }
}

#endregion

#region --- Main Execution Block ---

$script:Silent = $args -contains "-silent" -or $args -contains "-s"

try {
    # CRITICAL: Pre-load essential modules (exceptions, logger) BEFORE anything else.
    # This ensures Invoke-WithErrorHandling and Write-Log are available immediately.
    $exceptionsModulePath = Join-Path $script:BasePath "modules\exceptions.psm1"
    $loggerModulePath = Join-Path $script:BasePath "modules\logger.psm1"
    
    if (-not (Test-Path $exceptionsModulePath)) { throw "CRITICAL FAILURE: The core exception handling module is missing at '$exceptionsModulePath'. Cannot continue." }
    if (-not (Test-Path $loggerModulePath)) { throw "CRITICAL FAILURE: The core logger module is missing at '$loggerModulePath'. Cannot continue." }
    
    Import-Module $exceptionsModulePath -Force -Global
    Import-Module $loggerModulePath -Force -Global

    # Initialize logger as early as possible
    Initialize-Logger
    Write-Log -Level Info -Message "Logger initialized early in main execution block."
    
    # Provide immediate feedback to the user
    Write-Host "PMC Terminal v5 - Initializing..." -ForegroundColor Cyan
    if (-not $script:Silent) {
        Write-Host "Log files written to: $(Get-LogPath)" -ForegroundColor Green
        Write-Host ""
    }
    
    # Start the terminal application
    $appSuccess = Start-PMCTerminal -Silent:$script:Silent
    
    if (-not $appSuccess) {
        # If Start-PMCTerminal returned $false due to an error, exit with a non-zero code.
        exit 1
    }

} catch {
    # This is the ultimate fallback error handler if Invoke-WithErrorHandling itself fails.
    Write-Host "`n!!! ULTIMATE FALLBACK ERROR HANDLER !!!" -ForegroundColor Red
    Write-Host "An unhandled critical error occurred during PMC Terminal startup." -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Script stack trace:" -ForegroundColor Yellow
    Write-Host $_.ScriptStackTrace -ForegroundColor Gray
    
    # Attempt to save minimal crash information
    try {
        $ultimateFailureInfo = @{
            Timestamp = Get-Date
            UltimateError = $_.Exception.Message
            ErrorType = $_.GetType().FullName
            ProcessId = $PID
            PowerShellVersion = $PSVersionTable.PSVersion.ToString()
            WorkingDirectory = Get-Location
            Arguments = $args
        }
        $ultimatePath = Join-Path $env:TEMP "helios_ultimate_failure_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
        $ultimateFailureInfo | ConvertTo-Json -Depth 5 | Set-Content $ultimatePath -Encoding UTF8
        Write-Host "`nUltimate failure info saved to: $ultimatePath" -ForegroundColor Magenta
    } catch {
        Write-Host "Even ultimate failure logging failed: $($_.Exception.Message)" -ForegroundColor Red
    }
    
    exit 1 # Exit with error code
    
} finally {
    # Final cleanup and user interaction before exiting.
    # This block always runs, regardless of success or failure.
    
    if (Get-Command -Name "Stop-TuiEngine" -ErrorAction SilentlyContinue) { 
        if (-not $script:Silent) { Write-Host "`nShutting down TUI Engine..." -ForegroundColor Gray }
        Write-Log -Level Info -Message "Stopping TUI Engine."
        Stop-TuiEngine 
    }
    
    # Call service-specific cleanup/save methods if they exist
    # Ensure $global:Services exists and the Task service is initialized
    if ($global:Services -is [PSCustomObject] -and $global:Services.PSObject.Properties.Contains('Task') -and $global:Services.Task -and $global:Services.Task.Save) {
        if (-not $script:Silent) { Write-Host "Saving task data..." -ForegroundColor Gray }
        Write-Log -Level Info -Message "Saving TaskService data."
        $global:Services.Task.Save()
    }

    # Clean up event subscriptions if necessary (though screens should handle their own OnExit)
    # This is a general cleanup, but specific screen cleanup is preferred.
    if (Get-Command -Name "Unregister-Event" -ErrorAction SilentlyContinue) {
        # Unregister all engine events created by this session to prevent leaks
        Get-EventSubscriber | Where-Object { $_.SourceIdentifier -like "Helios.*" } | ForEach-Object {
            try {
                Unregister-Event -SourceIdentifier $_.SourceIdentifier -ErrorAction SilentlyContinue
                Write-Log -Level Trace -Message "Unregistered event subscriber: $($_.SourceIdentifier)"
            } catch {
                Write-Log -Level Warn -Message "Failed to unregister event subscriber '$($_.SourceIdentifier)': $($_.Exception.Message)"
            }
        }
    }

    if (-not $script:Silent) { Write-Host "Goodbye!" -ForegroundColor Green }
    Write-Log -Level Info -Message "PMC Terminal application exit complete."
    
    # Exit with 0 if successful, 1 if there was a fatal error.
    # The `exit 1` in the catch blocks handles error exits.
    # If we reach here after a successful `Start-PMCTerminal`, we exit 0.
    # If we reach here after an error that was handled by the `ErrorHandler` of `Start-PMCTerminal`,
    # `appSuccess` will be `$false`, and the `exit 1` above would have been called.
    # So, if we reach this line, it implies success.
    exit 0 
}