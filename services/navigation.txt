# FILE: services/navigation.psm1
# PURPOSE: Provides a centralized service for managing screen navigation and routing.
# This service encapsulates all logic related to moving between different views in the application.

function Initialize-NavigationService {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    Write-Log -Level Debug -Message "Initializing NavigationService..."

    # The service object is a PSCustomObject, encapsulating its own state.
    # _routes: A hashtable mapping URL-like paths to screen factory scriptblocks.
    # _history: A stack to maintain the navigation history for the Back() method.
    $service = [PSCustomObject]@{
        Name     = "NavigationService"
        _routes  = @{}
        _history = [System.Collections.Generic.Stack[string]]::new()
    }

    # Method to register a screen factory for a given path.
    # This allows for a declarative mapping of routes to screens.
    $service | Add-Member -MemberType ScriptMethod -Name RegisterRoute -Value {
        param(
            [Parameter(Mandatory)]
            [string]$Path,

            [Parameter(Mandatory)]
            [scriptblock]$Factory
        )

        Invoke-WithErrorHandling -Component "$($this.Name).RegisterRoute" -ScriptBlock {
            # Defensive programming: Ensure parameters are valid.
            if ([string]::IsNullOrWhiteSpace($Path)) { throw "Route path cannot be null or empty." }
            if ($null -eq $Factory) { throw "Screen factory scriptblock cannot be null." }

            Write-Log -Level Trace -Message "Registering route: $Path"
            $this._routes[$Path.ToLower()] = $Factory
        } -Context @{ Operation = "RegisterRoute"; Path = $Path } -ErrorHandler { # FIX: Changed Context to hashtable
            param($Exception)
            Write-Log -Level Error -Message "Failed to register route '$Path': $($Exception.Message)" -Data $Exception.Context
        }
    }

    # Method to navigate to a registered path. This is the primary way to change screens.
    $service | Add-Member -MemberType ScriptMethod -Name GoTo -Value {
        param(
            [Parameter(Mandatory)]
            [string]$Path,

            [Parameter(Mandatory)]
            [hashtable]$Services
        )

        Invoke-WithErrorHandling -Component "$($this.Name).GoTo" -ScriptBlock {
            # Defensive programming: Ensure parameters are valid.
            if ([string]::IsNullOrWhiteSpace($Path)) { throw "Navigation path cannot be null or empty." }
            if ($null -eq $Services) { throw "Services object cannot be null." }
            if (-not (Get-Command 'Push-Screen' -ErrorAction SilentlyContinue)) {
                throw "TUI Engine function 'Push-Screen' is not available. Ensure tui-engine.psm1 is loaded before services."
            }

            $lookupPath = $Path.ToLower()
            if (-not $this._routes.ContainsKey($lookupPath)) {
                throw "Route not found: '$Path'. Ensure it has been registered."
            }

            Write-Log -Level Info -Message "Navigating to path: $Path"

            # Get the factory scriptblock for the route.
            $factory = $this._routes[$lookupPath]

            # Execute the factory to create the new screen instance, injecting dependencies.
            $screen = & $factory $Services
            if ($null -eq $screen) {
                throw "The screen factory for path '$Path' did not return a valid screen object."
            }

            # Push the new screen onto the TUI engine's screen stack.
            Push-Screen -Screen $screen

            # Add the path to our internal history stack.
            $this._history.Push($Path)
            Write-Log -Level Trace -Message "Navigation history depth: $($this._history.Count)"

        } -Context @{ Operation = "GoTo"; Path = $Path; ServiceCount = $Services.Keys.Count } -ErrorHandler { # FIX: Changed Context to hashtable
            param($Exception)
            Write-Log -Level Error -Message "Navigation failed for path '$Path': $($Exception.Message)" -Data $Exception.Context
            # In a full implementation, this could trigger a user-facing dialog.
        }
    }

    # Method to navigate to the previous screen in the history.
    $service | Add-Member -MemberType ScriptMethod -Name Back -Value {
        Invoke-WithErrorHandling -Component "$($this.Name).Back" -ScriptBlock {
            if (-not (Get-Command 'Pop-Screen' -ErrorAction SilentlyContinue)) {
                throw "TUI Engine function 'Pop-Screen' is not available. Ensure tui-engine.psm1 is loaded before services."
            }

            # Can only go back if there is more than one screen in the stack.
            if ($this._history.Count -le 1) {
                Write-Log -Level Debug -Message "Back navigation requested, but no history to go back to."
                return
            }

            Write-Log -Level Info -Message "Navigating back."

            # Pop the current screen from the TUI engine's stack.
            Pop-Screen

            # Pop the path from our internal history to keep it synchronized.
            [void]$this._history.Pop()
            Write-Log -Level Trace -Message "Navigation history depth: $($this._history.Count)"

        } -Context @{ Operation = "Back" } -ErrorHandler { # FIX: Changed Context to hashtable
            param($Exception)
            Write-Log -Level Error -Message "Back navigation failed: $($Exception.Message)" -Data $Exception.Context
        }
    }

    # FIX: Added IsValidRoute method
    # Method to check if a route is valid.
    $service | Add-Member -MemberType ScriptMethod -Name IsValidRoute -Value {
        param(
            [Parameter(Mandatory)]
            [string]$Path
        )
        Invoke-WithErrorHandling -Component "$($this.Name).IsValidRoute" -ScriptBlock {
            if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
            return $this._routes.ContainsKey($Path.ToLower())
        } -Context @{ Operation = "IsValidRoute"; Path = $Path } -ErrorHandler { # FIX: Changed Context to hashtable
            param($Exception)
            Write-Log -Level Error -Message "Error in IsValidRoute: $($Exception.Message)" -Data $Exception.Context
            return $false
        }
    }


    # --- Pre-register all known application routes ---
    # This centralizes route definitions within the navigation service itself,
    # making it the single source of truth for application navigation paths.
    # The scriptblocks are the "factories" that create screen objects.

    $service.RegisterRoute("/dashboard", {
        param($services)
        Get-HeliosDashboardScreen -Services $services # FIX: Changed function name
    })

    $service.RegisterRoute("/task", {
        param($services)
        Get-HeliosTaskScreen -Services $services # FIX: Changed function name
    })

    $service.RegisterRoute("/time-entry", {
        param($services)
        # Assuming other Helios screens follow the Get-Helios<ScreenName>Screen convention
        Get-HeliosTimeEntryScreen -Services $services # FIX: Changed function name (assuming convention)
    })

    $service.RegisterRoute("/timer-start", {
        param($services)
        Get-HeliosTimerStartScreen -Services $services # FIX: Changed function name (assuming convention)
    })

    $service.RegisterRoute("/project", {
        param($services)
        Get-HeliosProjectManagementScreen -Services $services # FIX: Changed function name (assuming convention)
    })

    $service.RegisterRoute("/reports", {
        param($services)
        Get-HeliosReportsScreen -Services $services # FIX: Changed function name (assuming convention)
    })

    $service.RegisterRoute("/settings", {
        param($services)
        Get-HeliosSettingsScreen -Services $services # FIX: Changed function name (assuming convention)
    })

    Write-Log -Level Debug -Message "NavigationService initialized with $($service._routes.Count) routes."

    return $service
}

Export-ModuleMember -Function "Initialize-NavigationService"