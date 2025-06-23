####\screens\dashboard-screen.psm1
# FILE: screens/dashboard-screen.psm1
# PURPOSE: Provides the main dashboard screen for PMC Terminal v5.
#          This screen offers navigation to other parts of the application
#          using a simple menu of Helios buttons. It adheres to the PowerShell-First
#          architectural principles, using PSCustomObject for the screen and
#          direct service method calls for interactions.

using module "$PSScriptRoot/../modules/logger.psm1"
using module "$PSScriptRoot/../modules/exceptions.psm1"
using module "$PSScriptRoot/../ui/helios-components.psm1"
using module "$PSScriptRoot/../ui/helios-panels.psm1"
# Assuming tui-engine provides Get-ThemeColor, Request-TuiRefresh, Request-Focus
# and other core TUI functions.

function Get-HeliosDashboardScreen {
    <#
    .SYNOPSIS
        Creates a new Dashboard screen object for PMC Terminal v5.
    .DESCRIPTION
        This factory function constructs a [PSCustomObject] representing the dashboard screen.
        It sets up the UI layout using Helios panels and components, defines event handlers
        for user interactions (button clicks, key presses), and manages navigation via
        the NavigationService. It's designed to be minimal, focusing on navigation
        to other primary screens like Task Management.
    .PARAMETER Services
        A PSCustomObject containing references to all initialized application services
        (e.g., Task, Navigation, Keybindings). This is crucial for dependency injection.
    .OUTPUTS
        [PSCustomObject] The initialized screen object.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Services # Expecting a PSCustomObject for services
    )

    Invoke-WithErrorHandling -Component "Get-HeliosDashboardScreen" -Context @{} -ScriptBlock {
        Write-Log -Level Trace -Message "Creating Helios Dashboard Screen object."

        # Defensive: Ensure Services object is valid and contains required services
        if (-not $Services) {
            throw "Services object must be provided to Get-HeliosDashboardScreen."
        }
        if (-not $Services.Navigation) {
            throw "NavigationService is missing from the provided Services object."
        }
        if (-not $Services.Keybindings) {
            throw "KeybindingService is missing from the provided Services object."
        }

        $screen = [PSCustomObject]@{
            Name                  = "HeliosDashboardScreen"
            _services             = $Services # Store the services for later use
            _eventSubscriptions   = [System.Collections.ArrayList]::new() # For future event cleanup
            _rootPanel            = $null
            _menuButtons          = [System.Collections.ArrayList]::new() # To manage focus
            _focusedButtonIndex   = 0
            Visible               = $true
            ZIndex                = 0
        }

        #region Private Helper Methods (attached to $screen)

        $buildUiScript = {
            Invoke-WithErrorHandling -Component "$($this.Name)._BuildUI" -Context @{} -ScriptBlock {
                Write-Log -Level Debug -Message "Building UI for Dashboard Screen."

                # Define menu items with their paths and display text
                # Only /task is functional for now, others are placeholders
                $menuItems = @(
                    @{ Text = "1. View Tasks"; Path = "/task"; Enabled = $true }
                    @{ Text = "2. New Time Entry"; Path = "/time-entry"; Enabled = $false }
                    @{ Text = "3. Start Timer"; Path = "/timer-start"; Enabled = $false }
                    @{ Text = "4. View Projects"; Path = "/project"; Enabled = $false }
                    @{ Text = "5. Reports"; Path = "/reports"; Enabled = $false }
                    @{ Text = "6. Settings"; Path = "/settings"; Enabled = $false }
                    @{ Text = "0. Exit Terminal"; Path = "/exit"; Enabled = $true }
                )

                # Create the main root panel for the screen
                $this._rootPanel = New-HeliosStackPanel -Props @{
                    Name        = "DashboardRootPanel"
                    X           = 2
                    Y           = 2
                    Width       = [Math]::Max(60, ($global:TuiState.BufferWidth - 4))
                    Height      = [Math]::Max(20, ($global:TuiState.BufferHeight - 4))
                    ShowBorder  = $true
                    Title       = " PMC Terminal v5 - Main Menu "
                    Orientation = "Vertical"
                    Spacing     = 1
                    Padding     = 2
                    BackgroundColor = (Get-ThemeColor "Background")
                }
                if (-not $this._rootPanel) { throw "Failed to create DashboardRootPanel." }

                # Add an instruction label
                $instructionLabel = New-HeliosLabel -Props @{
                    Name = "InstructionLabel"
                    Text = "Use Arrow Keys, Number Keys, or Enter to Navigate"
                    Width = 60
                    Height = 1
                    ForegroundColor = (Get-ThemeColor "Subtle")
                }
                $this._rootPanel.AddChild($instructionLabel)

                # Create a panel for the menu buttons
                $menuPanel = New-HeliosStackPanel -Props @{
                    Name        = "MenuButtonPanel"
                    Orientation = "Vertical"
                    Spacing     = 1
                    Padding     = 1
                    Width       = $this._rootPanel.Width - 4 # Adjust width for padding
                    Height      = ($menuItems.Count * 3) + 2 # Estimate height (3 lines per button + padding)
                }
                $this._rootPanel.AddChild($menuPanel)

                # Create buttons for each menu item
                foreach ($item in $menuItems) {
                    $buttonText = $item.Text
                    $buttonPath = $item.Path
                    $buttonName = "MenuButton_" + ($buttonPath -replace '[^a-zA-Z0-9]', '')
                    $buttonEnabled = $item.Enabled ?? $true # Default to enabled

                    # Capture $this and $item for the scriptblock closure
                    $currentScreen = $this
                    $currentItem = $item

                    $button = New-HeliosButton -Props @{
                        Name        = $buttonName
                        Text        = $buttonText
                        Width       = $menuPanel.Width - 2 # Button width within menu panel
                        Height      = 3
                        IsFocusable = $buttonEnabled # Only focusable if enabled
                        OnClick     = {
                            Invoke-WithErrorHandling -Component "$($currentScreen.Name).MenuButton.OnClick" -Context @{ Path = $currentItem.Path } -ScriptBlock {
                                if (-not $buttonEnabled) {
                                    Write-Log -Level Info -Message "Attempted to click disabled button: $($currentItem.Path)"
                                    # No notification needed as per requirements
                                    return
                                }
                                Write-Log -Level Info -Message "Dashboard button clicked: $($currentItem.Path)"
                                if ($currentItem.Path -eq "/exit") {
                                    Write-Log -Level Info -Message "Exit requested from Dashboard."
                                    # Assuming Stop-TuiEngine function is available globally for application shutdown
                                    if (Get-Command Stop-TuiEngine -ErrorAction SilentlyContinue) {
                                        Stop-TuiEngine
                                    }
                                } else {
                                    # Direct method call to NavigationService
                                    $currentScreen._services.Navigation.GoTo($currentItem.Path, $currentScreen._services)
                                }
                            }
                        }
                    }
                    $menuPanel.AddChild($button)
                    [void]$this._menuButtons.Add($button) # Add to list for focus management
                }

                # Add a status label at the bottom
                $statusLabel = New-HeliosLabel -Props @{
                    Name = "StatusLabel"
                    Text = "Press ESC to return to this menu from any screen"
                    Width = 60
                    Height = 1
                    ForegroundColor = (Get-ThemeColor "Subtle")
                }
                $this._rootPanel.AddChild($statusLabel)

                Write-Log -Level Debug -Message "Dashboard UI built successfully."
            }
        }
        $screen | Add-Member -MemberType ScriptMethod -Name _BuildUI -Value $buildUiScript

        $setFocusToButton = {
            param([int]$deltaIndex) # deltaIndex: +1 for next, -1 for previous
            Invoke-WithErrorHandling -Component "$($this.Name)._SetFocusToButton" -Context @{ DeltaIndex = $deltaIndex } -ScriptBlock {
                if ($this._menuButtons.Count -eq 0) { return }

                # Get only the currently focusable buttons
                # Using Where-Object and Select-Object to ensure we work with an array of focusable buttons
                $focusableButtons = ($this._menuButtons | Where-Object { $_.IsFocusable }).ToArray()
                if ($focusableButtons.Count -eq 0) {
                    Write-Log -Level Warn -Message "No focusable buttons found on dashboard."
                    return
                }

                # Find the current focused button's index within the *focusable* list
                $currentFocusedButton = if ($this._focusedButtonIndex -ge 0 -and $this._focusedButtonIndex -lt $this._menuButtons.Count) { $this._menuButtons[$this._focusedButtonIndex] } else { $null }
                $currentFocusableIndex = -1
                for ($i = 0; $i -lt $focusableButtons.Count; $i++) {
                    if ($focusableButtons[$i] -eq $currentFocusedButton) {
                        $currentFocusableIndex = $i
                        break
                    }
                }
                
                # If no button was previously focused or the focused one is no longer focusable, default to first focusable
                if ($currentFocusableIndex -eq -1) {
                    $currentFocusableIndex = 0
                }

                # Calculate new focusable index, wrapping around
                $newFocusableIndex = ($currentFocusableIndex + $deltaIndex + $focusableButtons.Count) % $focusableButtons.Count

                # Get the actual button object to focus
                $newButton = $focusableButtons[$newFocusableIndex]

                # If the new button is the same as the old, no change needed
                if ($newButton -eq $currentFocusedButton) { return }

                # Remove focus from old button
                if ($currentFocusedButton -and $currentFocusedButton.PSObject.Properties.Contains('IsFocused')) {
                    $currentFocusedButton.IsFocused = $false
                }

                # Set focus to new button
                if ($newButton -and $newButton.PSObject.Properties.Contains('IsFocused')) {
                    $newButton.IsFocused = $true
                    # Inform TUI engine about new focus via Request-Focus
                    # Request-Focus is provided by focus-manager.psm1, imported by dialog-system.psm1 (which is imported by Start-PMCTerminal)
                    # and also by tui-engine.psm1 directly, so it should be available.
                    Request-Focus -Component $newButton -Reason 'DashboardMenuNavigation'
                    
                    # Update _focusedButtonIndex to the index of the actual button in the _menuButtons list
                    # This ensures _focusedButtonIndex always refers to the correct item in the full list,
                    # even if some items are not focusable.
                    $this._focusedButtonIndex = $this._menuButtons.IndexOf($newButton)
                    Write-Log -Level Trace -Message "Focus set to button index $($this._focusedButtonIndex): $($newButton.Name)"
                }
                Request-TuiRefresh
            }
        }
        $screen | Add-Member -MemberType ScriptMethod -Name _SetFocusToButton -Value $setFocusToButton

        #endregion

        #region Public Methods (Screen Lifecycle)

        $initScript = {
            param(
                [Parameter(Mandatory = $true)]
                [PSCustomObject]$services # Services are passed during screen creation, not Init
            )
            Invoke-WithErrorHandling -Component "$($this.Name).Init" -Context @{} -ScriptBlock {
                Write-Log -Level Info -Message "Initializing Dashboard Screen."
                
                # Services are already set in the factory. This Init method is called by TUI Engine
                # when the screen is pushed. Use it for any logic that needs to run just as the screen becomes active.
                
                # No specific data to refresh for this minimal dashboard, but keep the pattern
                # $this._RefreshData() 
                
                Write-Log -Level Info -Message "Dashboard Screen initialized successfully."
            }
        }
        $screen | Add-Member -MemberType ScriptMethod -Name Init -Value $initScript

        $onEnterScript = {
            Invoke-WithErrorHandling -Component "$($this.Name).OnEnter" -Context @{} -ScriptBlock {
                Write-Log -Level Info -Message "Dashboard OnEnter: Setting initial focus."
                # Set focus to the first focusable button (delta 0 from current, effectively first)
                $this._SetFocusToButton(0) 
                Request-TuiRefresh
            }
        }
        $screen | Add-Member -MemberType ScriptMethod -Name OnEnter -Value $onEnterScript

        $onExitScript = {
            Invoke-WithErrorHandling -Component "$($this.Name).OnExit" -Context @{} -ScriptBlock {
                Write-Log -Level Info -Message "Exiting Dashboard Screen. Cleaning up subscriptions."
                # Clean up any event subscriptions (pattern, even if none for this minimal screen)
                foreach ($sub in $this._eventSubscriptions) {
                    try {
                        Unregister-Event -SubscriptionId $sub.Id
                        Write-Log -Level Debug -Message "Unregistered event subscription: $($sub.Id)"
                    } catch {
                        Write-Log -Level Warn -Message "Failed to unregister event subscription $($sub.Id): $($_.Exception.Message)"
                    }
                }
                $this._eventSubscriptions.Clear()
                Write-Log -Level Info -Message "Dashboard Screen OnExit completed."
            }
        }
        $screen | Add-Member -MemberType ScriptMethod -Name OnExit -Value $onExitScript

        $handleInputScript = {
            param(
                [Parameter(Mandatory = $true)]
                [System.Management.Automation.Host.KeyInfo]$Key
            )
            Invoke-WithErrorHandling -Component "$($this.Name).HandleInput" -Context @{ Key = $Key.Key } -ScriptBlock {
                $keybindingSvc = $this._services.Keybindings
                $handled = $false

                # Handle navigation keys for menu buttons
                if ($keybindingSvc.IsAction('nav.down', $Key)) {
                    $this._SetFocusToButton(1) # Move to next focusable button
                    $handled = $true
                } elseif ($keybindingSvc.IsAction('nav.up', $Key)) {
                    $this._SetFocusToButton(-1) # Move to previous focusable button
                    $handled = $true
                } elseif ($keybindingSvc.IsAction('form.submit', $Key)) { # Enter key
                    # Trigger OnClick for the focused button
                    $focusedButton = $this._menuButtons[$this._focusedButtonIndex]
                    if ($focusedButton -and $focusedButton.OnClick) {
                        # Buttons handle their own OnClick via their internal HandleInput on Enter/Space
                        # So, just calling the OnClick here might be redundant if the button is focused.
                        # However, for consistency with number key handling, we can call it.
                        $focusedButton.OnClick()
                        $handled = $true
                    }
                } elseif ($Key.Character -match '^[0-9]$') {
                    # Handle number key shortcuts
                    $numericInput = [int]$Key.Character.ToString()
                    $targetButton = $null

                    # Find the button by its number prefix (e.g., "1. View Tasks")
                    foreach ($button in $this._menuButtons) {
                        if ($button.IsFocusable -and $button.Text -like "$numericInput.*") {
                            $targetButton = $button
                            break
                        }
                    }

                    if ($targetButton -and $targetButton.OnClick) {
                        # Directly call the OnClick of the target button
                        $targetButton.OnClick()
                        $handled = $true
                    }
                }
                
                # Note: The TUI engine handles global keys like ESC (app.back) for navigation.
                # The dashboard, being a root screen, doesn't necessarily need to pop itself.
                # If it were a sub-screen, it would use $this._services.Navigation.Back() here.

                return $handled
            } -ErrorHandler {
                param($Exception)
                Write-Log -Level Error -Message "Dashboard HandleInput error: $($Exception.Message)" -Data $Exception.Context
                return $false
            }
        }
        $screen | Add-Member -MemberType ScriptMethod -Name HandleInput -Value $handleInputScript

        $renderScript = {
            Invoke-WithErrorHandling -Component "$($this.Name).Render" -Context @{} -ScriptBlock {
                if ($this._rootPanel -and $this._rootPanel.PSObject.Methods.Contains('Render')) {
                    $this._rootPanel.Render()
                } else {
                    Write-Log -Level Warn -Message "Dashboard Render: Root panel not found or missing Render method."
                }
            } -ErrorHandler {
                param($Exception)
                Write-Log -Level Error -Message "Dashboard Render error: $($Exception.Message)" -Data $Exception.Context
            }
        }
        $screen | Add-Member -MemberType ScriptMethod -Name Render -Value $renderScript

        #endregion

        # Build the UI components immediately when the screen object is created
        # This ensures _rootPanel is populated before the screen object is returned,
        # making the RootPanel property available to the TUI engine and focus manager.
        $screen._BuildUI()

        # Expose the root panel for the TUI engine and focus manager as a NoteProperty.
        # Now that _BuildUI has been called, $screen._rootPanel will be a valid object.
        $screen.PSObject.Properties.Add([psnoteproperty]::new('RootPanel', $screen._rootPanel))

        return $screen
    } -ErrorHandler {
        param($Exception)
        Write-Log -Level Fatal -Message "Failed to create Helios Dashboard Screen: $($Exception.Message)" -Data $Exception.Context
        throw # Re-throw to main application error handler
    }
}

Export-ModuleMember -Function Get-HeliosDashboardScreen