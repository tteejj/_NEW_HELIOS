# FILE: services/keybindings.psm1
# PURPOSE: Provides a centralized service for managing application keybindings.
# This service abstracts raw key presses into named actions, allowing for easy
# configuration and preventing hard-coded keys in UI components.

function Initialize-KeybindingService {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    Write-Log -Level Debug -Message "Initializing KeybindingService..."

    # The _keyMap defines all application-wide actions and their corresponding keys.
    # Action names are lowercase for case-insensitive lookups.
    # 'Key' can be a character or a [System.ConsoleKey] enum.
    # 'Modifiers' is an array containing 'Ctrl', 'Alt', or 'Shift'.
    $keyMap = @{
        # Application-level
        "app.quit"        = @{ Key = 'q'; Modifiers = @('Ctrl') }
        "app.back"        = @{ Key = [System.ConsoleKey]::Escape; Modifiers = @() }
        "app.refresh"     = @{ Key = 'r'; Modifiers = @('Ctrl') }
        "app.debuglog"    = @{ Key = [System.ConsoleKey]::F12; Modifiers = @() }
        "app.help"        = @{ Key = [System.ConsoleKey]::F1; Modifiers = @() }

        # List operations
        "list.new"        = @{ Key = 'n'; Modifiers = @() }
        "list.edit"       = @{ Key = 'e'; Modifiers = @() }
        "list.delete"     = @{ Key = [System.ConsoleKey]::Delete; Modifiers = @() }
        "list.toggle"     = @{ Key = [System.ConsoleKey]::Spacebar; Modifiers = @() }
        "list.selectall"  = @{ Key = 'a'; Modifiers = @('Ctrl') }

        # Navigation
        "nav.up"          = @{ Key = [System.ConsoleKey]::UpArrow; Modifiers = @() }
        "nav.down"        = @{ Key = [System.ConsoleKey]::DownArrow; Modifiers = @() }
        "nav.left"        = @{ Key = [System.ConsoleKey]::LeftArrow; Modifiers = @() }
        "nav.right"       = @{ Key = [System.ConsoleKey]::RightArrow; Modifiers = @() }
        "nav.pageup"      = @{ Key = [System.ConsoleKey]::PageUp; Modifiers = @() }
        "nav.pagedown"    = @{ Key = [System.ConsoleKey]::PageDown; Modifiers = @() }
        "nav.home"        = @{ Key = [System.ConsoleKey]::Home; Modifiers = @() }
        "nav.end"         = @{ Key = [System.ConsoleKey]::End; Modifiers = @() }

        # Quick navigation (number keys)
        "quicknav.1"      = @{ Key = '1'; Modifiers = @() }
        "quicknav.2"      = @{ Key = '2'; Modifiers = @() }
        "quicknav.3"      = @{ Key = '3'; Modifiers = @() }
        "quicknav.4"      = @{ Key = '4'; Modifiers = @() }
        "quicknav.5"      = @{ Key = '5'; Modifiers = @() }
        "quicknav.6"      = @{ Key = '6'; Modifiers = @() }
        "quicknav.7"      = @{ Key = '7'; Modifiers = @() }
        "quicknav.8"      = @{ Key = '8'; Modifiers = @() }
        "quicknav.9"      = @{ Key = '9'; Modifiers = @() }

        # Form operations
        "form.submit"     = @{ Key = [System.ConsoleKey]::Enter; Modifiers = @() }
        "form.cancel"     = @{ Key = [System.ConsoleKey]::Escape; Modifiers = @() }

        # Text editing
        "edit.cut"        = @{ Key = 'x'; Modifiers = @('Ctrl') }
        "edit.copy"       = @{ Key = 'c'; Modifiers = @('Ctrl') }
        "edit.paste"      = @{ Key = 'v'; Modifiers = @('Ctrl') }
        "edit.undo"       = @{ Key = 'z'; Modifiers = @('Ctrl') }
        "edit.redo"       = @{ Key = 'y'; Modifiers = @('Ctrl') }
    }

    # The service object is a PSCustomObject, encapsulating its own state.
    $service = [PSCustomObject]@{
        Name    = "KeybindingService"
        _keyMap = $keyMap
    }

    # The primary method for UI components to check if a key press matches a named action.
    $service | Add-Member -MemberType ScriptMethod -Name IsAction -Value {
        param(
            [Parameter(Mandatory)]
            [string]$ActionName,

            [Parameter(Mandatory)]
            [System.ConsoleKeyInfo]$KeyInfo
        )

        return Invoke-WithErrorHandling -Component "$($this.Name).IsAction" -ScriptBlock {
            # Defensive programming: Ensure parameters are valid.
            if ([string]::IsNullOrWhiteSpace($ActionName) -or $null -eq $KeyInfo) {
                return $false
            }

            $lookupAction = $ActionName.ToLower()
            if (-not $this._keyMap.ContainsKey($lookupAction)) {
                Write-Log -Level Trace -Message "Action '$lookupAction' not found in key map."
                return $false
            }

            $binding = $this._keyMap[$lookupAction]

            # 1. Match the key itself (character or special key)
            $keyMatches = $false
            if ($binding.Key -is [System.ConsoleKey]) {
                $keyMatches = ($KeyInfo.Key -eq $binding.Key)
            }
            elseif ($binding.Key -is [string] -and $binding.Key.Length -eq 1) {
                # Case-insensitive comparison for character keys
                $keyMatches = $KeyInfo.KeyChar.ToString().Equals($binding.Key, [System.StringComparison]::InvariantCultureIgnoreCase)
            }

            if (-not $keyMatches) {
                return $false
            }

            # 2. Match modifiers EXACTLY. The pressed state must equal the required state.
            $requiredModifiers = [System.Collections.ArrayList]($binding.Modifiers ?? @())
            $hasCtrl = ($KeyInfo.Modifiers -band [System.ConsoleModifiers]::Control) -ne 0
            $hasAlt = ($KeyInfo.Modifiers -band [System.ConsoleModifiers]::Alt) -ne 0
            $hasShift = ($KeyInfo.Modifiers -band [System.ConsoleModifiers]::Shift) -ne 0

            $ctrlRequired = $requiredModifiers.Contains('Ctrl')
            $altRequired = $requiredModifiers.Contains('Alt')
            $shiftRequired = $requiredModifiers.Contains('Shift')

            if (($hasCtrl -ne $ctrlRequired) -or ($hasAlt -ne $altRequired) -or ($hasShift -ne $shiftRequired)) {
                return $false
            }

            # If both key and modifiers match, the action is confirmed.
            Write-Log -Level Trace -Message "Key press matched action '$lookupAction'."
            return $true

        } -Context @{ ActionName = $ActionName; Key = $KeyInfo.Key; Modifiers = $KeyInfo.Modifiers } -ErrorHandler {
            param($Exception)
            Write-Log -Level Error -Message "Error in IsAction: $($Exception.Message)" -Data $Exception.Context
            return $false # Ensure a boolean is always returned
        }
    }

    Write-Log -Level Debug -Message "KeybindingService initialized with $($service._keyMap.Count) actions."

    return $service
}

Export-ModuleMember -Function "Initialize-KeybindingService"