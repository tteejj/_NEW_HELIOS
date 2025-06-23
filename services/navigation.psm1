# FILE: services/navigation.psm1
# PURPOSE: Provides a centralized service for managing screen navigation and routing.
# This service encapsulates all logic related to moving between different views in the application.

function Initialize-NavigationService {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    Write-Log -Level Debug -Message "Initializing NavigationService..."

    $service = [PSCustomObject]@{
        Name     = "NavigationService"
        _routes  = @{}
        _history = [System.Collections.Generic.Stack[string]]::new()
    }

    $service | Add-Member -MemberType ScriptMethod -Name RegisterRoute -Value {
        param(
            [Parameter(Mandatory)]
            [string]$Path,
            [Parameter(Mandatory)]
            [scriptblock]$Factory
        )

        Invoke-WithErrorHandling -Component "$($this.Name).RegisterRoute" -Context @{ Path = $Path } -ScriptBlock {
            if ([string]::IsNullOrWhiteSpace($Path)) { throw "Route path cannot be null or empty." }
            if ($null -eq $Factory) { throw "Screen factory scriptblock cannot be null." }

            Write-Log -Level Trace -Message "Registering route: $Path"
            $this._routes[$Path.ToLower()] = $Factory
        }
    }

    $service | Add-Member -MemberType ScriptMethod -Name GoTo -Value {
        param(
            [Parameter(Mandatory)]
            [string]$Path,
            [Parameter(Mandatory)]
            [PSCustomObject]$Services
        )

        Invoke-WithErrorHandling -Component "$($this.Name).GoTo" -Context @{ Path = $Path } -ScriptBlock {
            if ([string]::IsNullOrWhiteSpace($Path)) { throw "Navigation path cannot be null or empty." }
            if ($null -eq $Services) { throw "Services object cannot be null." }
            if (-not (Get-Command 'Push-Screen' -ErrorAction SilentlyContinue)) {
                throw "TUI Engine function 'Push-Screen' is not available."
            }

            $lookupPath = $Path.ToLower()
            if (-not $this._routes.ContainsKey($lookupPath)) {
                throw "Route not found: '$Path'. Ensure it has been registered."
            }

            Write-Log -Level Info -Message "Navigating to path: $Path"
            $factory = $this._routes[$lookupPath]
            
            # FIXED: Call the factory scriptblock with proper parameter isolation
            # Use Invoke-Command to ensure only the Services parameter is passed
            $screen = Invoke-Command -ScriptBlock $factory -ArgumentList $Services
            
            if ($null -eq $screen) {
                throw "The screen factory for path '$Path' did not return a valid screen object."
            }

            Push-Screen -Screen $screen -Services $Services
            $this._history.Push($Path)
        }
    }

    $service | Add-Member -MemberType ScriptMethod -Name Back -Value {
        Invoke-WithErrorHandling -Component "$($this.Name).Back" -Context @{} -ScriptBlock {
            if (-not (Get-Command 'Pop-Screen' -ErrorAction SilentlyContinue)) {
                throw "TUI Engine function 'Pop-Screen' is not available."
            }
            if ($this._history.Count -le 1) {
                return
            }
            Pop-Screen
            [void]$this._history.Pop()
        }
    }

    $service | Add-Member -MemberType ScriptMethod -Name IsValidRoute -Value {
        param([string]$Path)
        Invoke-WithErrorHandling -Component "$($this.Name).IsValidRoute" -Context @{ Path = $Path } -ScriptBlock {
            if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
            return $this._routes.ContainsKey($Path.ToLower())
        }
    }

    Write-Log -Level Debug -Message "NavigationService initialized."
    return $service
}

Export-ModuleMember -Function "Initialize-NavigationService"