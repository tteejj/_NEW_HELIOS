# FILE: screens/dashboard-screen.psm1
# PURPOSE: Provides the main dashboard screen for PMC Terminal v5.
# FULLY FIXED VERSION with robust component construction and focus management

function Get-HeliosDashboardScreen {
    <#
    .SYNOPSIS
        Creates a new Dashboard screen object for PMC Terminal v5.
    .DESCRIPTION
        This factory function constructs a [PSCustomObject] representing the dashboard screen.
        It sets up the UI layout using Helios panels and components, defines event handlers
        for user interactions (button clicks, key presses), and manages navigation via
        the NavigationService. COMPLETE FIX with guaranteed focus management.
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
        [PSCustomObject]$Services
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
            _services             = $Services
            _isInitialized        = $false 
            _eventSubscriptions   = [System.Collections.ArrayList]::new()
            _rootPanel            = $null
            _menuButtons          = [System.Collections.ArrayList]::new()
            _focusedButtonIndex   = 0
            _componentId          = [Guid]::NewGuid().ToString()
            Visible               = $true
            ZIndex                = 0
        }

        # CRITICAL FIX: Build UI method with comprehensive debugging and proper component construction
        $buildUiScript = {
            Invoke-WithErrorHandling -Component "$($this.Name)._BuildUI" -Context @{} -ScriptBlock {
                Write-Log -Level Debug -Message "Building UI for Dashboard Screen."

                # Define menu items with their paths and display text
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
                    Visible     = $true
                    BackgroundColor = (Get-ThemeColor "Background")
                }
                
                if (-not $this._rootPanel) { 
                    throw "Failed to create DashboardRootPanel." 
                }
                
                Write-Log -Level Debug -Message "Created root panel: $($this._rootPanel.Name), Visible: $($this._rootPanel.Visible)"

                # Add an instruction label
                $instructionLabel = New-HeliosLabel -Props @{
                    Name = "InstructionLabel"
                    Text = "Use Arrow Keys, Number Keys, or Enter to Navigate"
                    Width = 60
                    Height = 1
                    Visible = $true
                    ForegroundColor = (Get-ThemeColor "Subtle")
                }
                $this._rootPanel.AddChild($instructionLabel)
                Write-Log -Level Debug -Message "Added instruction label, root panel children count: $($this._rootPanel.Children.Count)"

                # Create a panel for the menu buttons
                $menuPanel = New-HeliosStackPanel -Props @{
                    Name        = "MenuButtonPanel"
                    Orientation = "Vertical"
                    Spacing     = 1
                    Padding     = 1
                    Width       = $this._rootPanel.Width - 4
                    Height      = ($menuItems.Count * 3) + 2
                    Visible     = $true
                }
                $this._rootPanel.AddChild($menuPanel)
                Write-Log -Level Debug -Message "Added menu panel, root panel children count: $($this._rootPanel.Children.Count)"

                # CRITICAL FIX: Create buttons with explicit debugging and proper closure handling
                $buttonCount = 0
                foreach ($item in $menuItems) {
                    $buttonText = $item.Text
                    $buttonPath = $item.Path
                    $buttonName = "MenuButton_" + ($buttonPath -replace '[^a-zA-Z0-9]', '')
                    $buttonEnabled = if ($null -ne $item.Enabled) { $item.Enabled } else { $true }

                    Write-Log -Level Debug -Message "Creating button: $buttonName, Enabled: $buttonEnabled"

                    # Capture variables for closure with explicit local copies
                    $currentScreen = $this
                    $currentPath = $buttonPath
                    $isEnabled = $buttonEnabled
                    $itemText = $buttonText

                    $button = New-HeliosButton -Props @{
                        Name        = $buttonName
                        Text        = $itemText
                        Width       = $menuPanel.Width - 2
                        Height      = 3
                        Visible     = $true
                        IsFocusable = $isEnabled
                        OnClick     = {
                            Invoke-WithErrorHandling -Component "$($currentScreen.Name).MenuButton.OnClick" -Context @{ Path = $currentPath } -ScriptBlock {
                                if (-not $isEnabled) {
                                    Write-Log -Level Info -Message "Attempted to click disabled button: $currentPath"
                                    return
                                }
                                Write-Log -Level Info -Message "Dashboard button clicked: $currentPath"
                                if ($currentPath -eq "/exit") {
                                    Write-Log -Level Info -Message "Exit requested from Dashboard."
                                    if (Get-Command Stop-TuiEngine -ErrorAction SilentlyContinue) {
                                        Stop-TuiEngine
                                    }
                                } else {
                                    $currentScreen._services.Navigation.GoTo($currentPath, $currentScreen._services)
                                }
                            }
                        }
                    }
                    
                    # CRITICAL: Verify button properties and ensure all required properties exist
                    if (-not $button) {
                        throw "Failed to create button $buttonName"
                    }
                    
                    # Ensure all required properties exist on the button
                    if (($button.PSObject.Properties.Name -notcontains 'IsFocusable')) {
                        $button.PSObject.Properties.Add([psnoteproperty]::new('IsFocusable', $isEnabled))
                    }
                    if (($button.PSObject.Properties.Name -notcontains 'Visible')) {
                        $button.PSObject.Properties.Add([psnoteproperty]::new('Visible', $true))
                    }
                    if (($button.PSObject.Properties.Name -notcontains 'IsFocused')) {
                        $button.PSObject.Properties.Add([psnoteproperty]::new('IsFocused', $false))
                    }
                    
                    Write-Log -Level Debug -Message "Button created - Name: $($button.Name), IsFocusable: $($button.IsFocusable), Visible: $($button.Visible), Type: $($button.Type)"
                    
                    $menuPanel.AddChild($button)
                    [void]$this._menuButtons.Add($button)
                    $buttonCount++
                    
                    Write-Log -Level Debug -Message "Added button $buttonCount to menu panel, panel children count: $($menuPanel.Children.Count)"
                }

                Write-Log -Level Debug -Message "Total buttons created: $buttonCount, Total in _menuButtons: $($this._menuButtons.Count)"

                # Add a status label at the bottom
                $statusLabel = New-HeliosLabel -Props @{
                    Name = "StatusLabel"
                    Text = "Press ESC to return to this menu from any screen"
                    Width = 60
                    Height = 1
                    Visible = $true
                    ForegroundColor = (Get-ThemeColor "Subtle")
                }
                $this._rootPanel.AddChild($statusLabel)

                Write-Log -Level Debug -Message "Dashboard UI built successfully. Root panel children: $($this._rootPanel.Children.Count)"
                
                # DEBUGGING: Log complete component hierarchy
                Write-Log -Level Debug -Message "=== COMPONENT HIERARCHY DEBUG ==="
                Write-Log -Level Debug -Message "Root Panel: $($this._rootPanel.Name), Children: $($this._rootPanel.Children.Count)"
                foreach ($child in $this._rootPanel.Children) {
                    Write-Log -Level Debug -Message "  Child: $($child.Name), Type: $($child.Type), Visible: $($child.Visible), IsFocusable: $($child.IsFocusable)"
                    if ($child.Children) {
                        foreach ($grandchild in $child.Children) {
                            Write-Log -Level Debug -Message "    Grandchild: $($grandchild.Name), Type: $($grandchild.Type), Visible: $($grandchild.Visible), IsFocusable: $($grandchild.IsFocusable)"
                        }
                    }
                }
                Write-Log -Level Debug -Message "=== END COMPONENT HIERARCHY DEBUG ==="
                
                # CRITICAL: Validate that we have focusable components
                $focusableCount = 0
                foreach ($button in $this._menuButtons) {
                    if ($button.IsFocusable -and $button.Visible) {
                        $focusableCount++
                    }
                }
                Write-Log -Level Info -Message "Dashboard has $focusableCount focusable buttons ready for focus management"
                
                if ($focusableCount -eq 0) {
                    Write-Log -Level Error -Message "Dashboard UI built but no focusable components found! This will cause focus issues."
                }
            }
        }
        $screen | Add-Member -MemberType ScriptMethod -Name _BuildUI -Value $buildUiScript

        # ENHANCED: Focus management with multiple fallback strategies
        $setFocusToButton = {
            param([int]$deltaIndex)
            Invoke-WithErrorHandling -Component "$($this.Name)._SetFocusToButton" -Context @{ DeltaIndex = $deltaIndex } -ScriptBlock {
                Write-Log -Level Debug -Message "SetFocusToButton called with delta: $deltaIndex, total buttons: $($this._menuButtons.Count)"
                
                if ($this._menuButtons.Count -eq 0) { 
                    Write-Log -Level Warning -Message "No buttons available for focus"
                    return 
                }

                $focusableButtons = ($this._menuButtons | Where-Object { $_.IsFocusable -and $_.Visible }).ToArray()
                if ($focusableButtons.Count -eq 0) {
                    Write-Log -Level Warning -Message "No focusable buttons found on dashboard."
                    return
                }
                
                Write-Log -Level Debug -Message "Found $($focusableButtons.Count) focusable buttons"

                # Find current focused button index in focusable list
                $currentFocusedButton = if ($this._focusedButtonIndex -ge 0 -and $this._focusedButtonIndex -lt $this._menuButtons.Count) { 
                    $this._menuButtons[$this._focusedButtonIndex] 
                } else { 
                    $null 
                }
                
                $currentFocusableIndex = -1
                for ($i = 0; $i -lt $focusableButtons.Count; $i++) {
                    if ($focusableButtons[$i] -eq $currentFocusedButton) {
                        $currentFocusableIndex = $i
                        break
                    }
                }
                
                if ($currentFocusableIndex -eq -1) {
                    $currentFocusableIndex = 0
                }

                # Calculate new index with wrapping
                $newFocusableIndex = ($currentFocusableIndex + $deltaIndex + $focusableButtons.Count) % $focusableButtons.Count
                $newButton = $focusableButtons[$newFocusableIndex]

                Write-Log -Level Debug -Message "Moving focus from index $currentFocusableIndex to $newFocusableIndex, button: $($newButton.Name)"

                # Remove focus from old button
                if ($currentFocusedButton -and ($currentFocusedButton.PSObject.Properties.Name -contains 'IsFocused')) {
                    $currentFocusedButton.IsFocused = $false
                }

                # Set focus to new button
                if ($newButton -and ($newButton.PSObject.Properties.Name -contains 'IsFocused')) {
                    $newButton.IsFocused = $true
                    
                    # Use focus manager if available
                    if (Get-Command Request-Focus -ErrorAction SilentlyContinue) {
                        Request-Focus -Component $newButton -Reason 'DashboardMenuNavigation'
                    }
                    
                    $this._focusedButtonIndex = $this._menuButtons.IndexOf($newButton)
                    Write-Log -Level Debug -Message "Focus set to button: $($newButton.Name) at index $($this._focusedButtonIndex)"
                }
                
                if (Get-Command Request-TuiRefresh -ErrorAction SilentlyContinue) {
                    Request-TuiRefresh
                }
            }
        }
        $screen | Add-Member -MemberType ScriptMethod -Name _SetFocusToButton -Value $setFocusToButton

        # Screen lifecycle methods
        $initScript = {
            param([Parameter(Mandatory = $true)][PSCustomObject]$services)
            Invoke-WithErrorHandling -Component "$($this.Name).Init" -Context @{} -ScriptBlock {
                Write-Log -Level Info -Message "Initializing Dashboard Screen."
                # Services already set in factory
                Write-Log -Level Info -Message "Dashboard Screen initialized successfully."
            }
        }
        $screen | Add-Member -MemberType ScriptMethod -Name Init -Value $initScript

        $onEnterScript = {
            Invoke-WithErrorHandling -Component "$($this.Name).OnEnter" -Context @{} -ScriptBlock {
                Write-Log -Level Info -Message "Dashboard OnEnter: Setting initial focus."
                
                # CRITICAL FIX: Ensure components are visible and give focus manager time
                Start-Sleep -Milliseconds 150
                
                # Set focus to first focusable button
                if ($this._menuButtons.Count -gt 0) {
                    $this._SetFocusToButton(0)
                }
                
                # Force focus manager refresh if available
                if (Get-Command Force-RefreshFocus -ErrorAction SilentlyContinue) {
                    Start-Sleep -Milliseconds 100
                    Force-RefreshFocus
                }
                
                if (Get-Command Request-TuiRefresh -ErrorAction SilentlyContinue) {
                    Request-TuiRefresh
                }
            }
        }
        $screen | Add-Member -MemberType ScriptMethod -Name OnEnter -Value $onEnterScript

        $onExitScript = {
            Invoke-WithErrorHandling -Component "$($this.Name).OnExit" -Context @{} -ScriptBlock {
                Write-Log -Level Info -Message "Exiting Dashboard Screen. Cleaning up subscriptions."
                foreach ($sub in $this._eventSubscriptions) {
                    try {
                        Unregister-Event -SubscriptionId $sub.Id
                        Write-Log -Level Debug -Message "Unregistered event subscription: $($sub.Id)"
                    } catch {
                        Write-Log -Level Warning -Message "Failed to unregister event subscription $($sub.Id): $($_.Exception.Message)"
                    }
                }
                $this._eventSubscriptions.Clear()
                Write-Log -Level Info -Message "Dashboard Screen OnExit completed."
            }
        }
        $screen | Add-Member -MemberType ScriptMethod -Name OnExit -Value $onExitScript

        $handleInputScript = {
            param([Parameter(Mandatory = $true)][System.ConsoleKeyInfo]$Key)
            Invoke-WithErrorHandling -Component "$($this.Name).HandleInput" -Context @{ Key = $Key.Key } -ScriptBlock {
                $keybindingSvc = $this._services.Keybindings
                $handled = $false

                Write-Log -Level Debug -Message "Dashboard handling input: $($Key.Key)"

                # Handle navigation keys
                if ($keybindingSvc.IsAction('nav.down', $Key)) {
                    $this._SetFocusToButton(1)
                    $handled = $true
                } elseif ($keybindingSvc.IsAction('nav.up', $Key)) {
                    $this._SetFocusToButton(-1)
                    $handled = $true
                } elseif ($keybindingSvc.IsAction('form.submit', $Key)) {
                    if ($this._focusedButtonIndex -ge 0 -and $this._focusedButtonIndex -lt $this._menuButtons.Count) {
                        $focusedButton = $this._menuButtons[$this._focusedButtonIndex]
                        if ($focusedButton -and $focusedButton.OnClick) {
                            $focusedButton.OnClick()
                            $handled = $true
                        }
                    }
                } elseif ($Key.Character -match '^[0-9]$') {
                    $numericInput = [int]$Key.Character.ToString()
                    $targetButton = $null

                    foreach ($button in $this._menuButtons) {
                        if ($button.IsFocusable -and $button.Text -like "$numericInput.*") {
                            $targetButton = $button
                            break
                        }
                    }

                    if ($targetButton -and $targetButton.OnClick) {
                        $targetButton.OnClick()
                        $handled = $true
                    }
                }
                
                return $handled
            }
        }
        $screen | Add-Member -MemberType ScriptMethod -Name HandleInput -Value $handleInputScript

        $renderScript = {
            Invoke-WithErrorHandling -Component "$($this.Name).Render" -Context @{} -ScriptBlock {
                if ($this._rootPanel -and ($this._rootPanel.PSObject.ScriptMethods.Name -contains 'Render')) {
                    $this._rootPanel.Render()
                } else {
                    Write-Log -Level Warning -Message "Dashboard Render: Root panel not found or missing Render method."
                }
            }
        }
        $screen | Add-Member -MemberType ScriptMethod -Name Render -Value $renderScript

        # CRITICAL: Build UI immediately and expose RootPanel
        $screen._BuildUI()
        
        # Verify UI was built correctly
        if (-not $screen._rootPanel) {
            throw "Dashboard screen UI failed to build - no root panel created"
        }
        
        if ($screen._menuButtons.Count -eq 0) {
            throw "Dashboard screen UI failed to build - no menu buttons created"
        }
        
        Write-Log -Level Debug -Message "Dashboard UI built, exposing RootPanel property"
        
        # Add RootPanel as a property for external access
        $screen.PSObject.Properties.Add([psnoteproperty]::new('RootPanel', $screen._rootPanel))
        
        # CRITICAL: Validate that components are properly structured for focus manager
        $focusableComponentCount = 0
        foreach ($button in $screen._menuButtons) {
            if (($button.PSObject.Properties.Name -contains 'IsFocusable') -and $button.IsFocusable -and 
                ($button.PSObject.Properties.Name -contains 'Visible') -and $button.Visible) {
                $focusableComponentCount++
            }
        }
        
        Write-Log -Level Info -Message "Dashboard screen created with $focusableComponentCount focusable components"
        
        if ($focusableComponentCount -eq 0) {
            Write-Log -Level Error -Message "CRITICAL: Dashboard screen has no focusable components!"
        }

        return $screen
    }
}

Export-ModuleMember -Function Get-HeliosDashboardScreen
