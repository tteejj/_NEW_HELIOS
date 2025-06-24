# MODULE: modules/focus-manager.psm1
# PURPOSE: Provides the single source of truth for component focus.
# FIXED VERSION with proper scoping and robust component discovery.

#region Private State
$script:FocusManager = [PSCustomObject]@{
    FocusedComponent = $null
    TabOrder = [System.Collections.Generic.List[object]]::new()
    EventSubscription = $null
    LastScreenProcessed = $null
}
#endregion

#region Private Functions

function Find-FocusableComponents {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$RootComponent
    )

    Write-Log -Level Debug -Message "=== FOCUS MANAGER: Finding focusable components ==="
    Write-Log -Level Debug -Message "Starting from root component: $($RootComponent.Name), Type: $($RootComponent.Type)"

    $focusable = [System.Collections.Generic.List[object]]::new()
    $queue = [System.Collections.Generic.Queue[object]]::new()
    $queue.Enqueue($RootComponent)
    $processedCount = 0

    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        $processedCount++

        if (-not $current) { 
            Write-Log -Level Debug -Message "Skipping null component"
            continue 
        }

        Write-Log -Level Debug -Message "Processing component: $($current.Name), Type: $($current.Type), Visible: $($current.Visible), IsFocusable: $($current.IsFocusable)"

        # Enhanced focusability check with debugging
        $hasIsFocusable = ($current.PSObject.Properties.Name -contains 'IsFocusable')
        $hasVisible = ($current.PSObject.Properties.Name -contains 'Visible')
        $isFocusable = $hasIsFocusable -and $current.IsFocusable
        $isVisible = $hasVisible -and $current.Visible
        
        Write-Log -Level Debug -Message "  HasIsFocusable: $hasIsFocusable, HasVisible: $hasVisible, IsFocusable: $isFocusable, IsVisible: $isVisible"

        if ($isFocusable -and $isVisible) {
            $focusable.Add($current)
            Write-Log -Level Info -Message "Found focusable component: $($current.Name) ($($current.Type))"
        }

        # Recurse into children with enhanced debugging
        if (($current.PSObject.Properties.Name -contains 'Children') -and $current.Children) {
            Write-Log -Level Debug -Message "  Component has $($current.Children.Count) children"
            foreach ($child in $current.Children) {
                if ($child) {
                    $queue.Enqueue($child)
                } else {
                    Write-Log -Level Debug -Message "  Skipping null child"
                }
            }
        } else {
            Write-Log -Level Debug -Message "  Component has no children or Children property"
        }
    }

    Write-Log -Level Info -Message "Focus Manager processed $processedCount components and found $($focusable.Count) focusable components"
    
    # Log all found focusable components
    if ($focusable.Count -gt 0) {
        Write-Log -Level Info -Message "Focusable components found:"
        for ($i = 0; $i -lt $focusable.Count; $i++) {
            $comp = $focusable[$i]
            Write-Log -Level Info -Message "  [$i] $($comp.Name) ($($comp.Type))"
        }
    } else {
        Write-Log -Level Warning -Message "No focusable components found!"
    }
    
    Write-Log -Level Debug -Message "=== END FOCUS MANAGER: Finding focusable components ==="

    return $focusable
}

#endregion

#region Public Functions

function Initialize-FocusManager {
    [CmdletBinding()]
    param()

    Invoke-WithErrorHandling -Component 'FocusManager.Initialize' -Context @{} -ScriptBlock {
        Write-Log -Level Info -Message "Initializing Focus Manager..."

        $sourceIdentifier = 'PMC.Navigation.ScreenPushed'

        # Unregister any previous subscription
        if ($script:FocusManager.EventSubscription) {
            Unregister-Event -SubscriptionId $script:FocusManager.EventSubscription.Id
            Write-Log -Level Debug -Message "Unregistered existing Focus Manager event subscription."
        }

        # Create enhanced event handler with proper scoping and fallback logic
        $handler = {
            param($Event)
            
            try {
                Write-Log -Level Debug -Message "Focus Manager received ScreenPushed event"
                
                $screen = $null
                
                # Try multiple ways to get the screen object
                if ($Event.SourceArgs -and $Event.SourceArgs.Count -gt 0) {
                    $screen = $Event.SourceArgs[0]
                    Write-Log -Level Debug -Message "Got screen from SourceArgs: $($screen.Name)"
                } elseif ($Event.MessageData) {
                    $screen = $Event.MessageData
                    Write-Log -Level Debug -Message "Got screen from MessageData: $($screen.Name)"
                } elseif ($global:TuiState -and $global:TuiState.CurrentScreen) {
                    $screen = $global:TuiState.CurrentScreen
                    Write-Log -Level Debug -Message "Got screen from global TUI state: $($screen.Name)"
                } else {
                    Write-Log -Level Warning -Message 'ScreenPushed event received but no screen could be found.'
                    return
                }
                
                if ($screen) {
                    Write-Log -Level Info -Message "Focus Manager processing screen: $($screen.Name)"
                    
                    # Add small delay to ensure screen is fully ready
                    Start-Sleep -Milliseconds 150
                    
                    # Call the public Update-TabOrderAndFocus function
                    Update-TabOrderAndFocus -Screen $screen
                } else {
                    Write-Log -Level Warning -Message 'ScreenPushed event received but screen object is null.'
                }
            } catch {
                Write-Log -Level Error -Message "Error in Focus Manager event handler: $_" -Data $_
            }
        }

        # Register the event handler for primary event
        $subscription = Register-EngineEvent -SourceIdentifier $sourceIdentifier -Action $handler
        $script:FocusManager.EventSubscription = $subscription
        
        # ENHANCED: Also register for fallback event
        try {
            $fallbackSubscription = Register-EngineEvent -SourceIdentifier 'PMC.Navigation.ScreenPushed.Fallback' -Action $handler
            Write-Log -Level Debug -Message "Also subscribed to fallback ScreenPushed event"
        } catch {
            Write-Log -Level Warning -Message "Failed to subscribe to fallback event: $_"
        }

        Write-Log -Level Info -Message "Focus Manager initialized and subscribed to '$sourceIdentifier'."
    }
}

function Update-TabOrderAndFocus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Screen
    )

    Invoke-WithErrorHandling -Component 'FocusManager.UpdateTabOrderAndFocus' -Context @{ ScreenName = $Screen.Name } -ScriptBlock {
        Write-Log -Level Info -Message "Updating tab order for screen '$($Screen.Name)'"

        # Clear previous state
        $script:FocusManager.TabOrder.Clear()
        Request-Focus -Component $null -Reason 'ScreenChange'

        if (-not $Screen.RootPanel) {
            Write-Log -Level Error -Message "Screen '$($Screen.Name)' has no RootPanel. Cannot establish focus."
            return
        }

        Write-Log -Level Debug -Message "Screen RootPanel: $($Screen.RootPanel.Name), Type: $($Screen.RootPanel.Type)"

        # ENHANCED: Add delay to ensure UI is fully constructed
        Start-Sleep -Milliseconds 100

        # Find all focusable components and establish the new tab order
        $focusableComponents = @(Find-FocusableComponents -RootComponent $Screen.RootPanel)
        
        if ($focusableComponents.Count -gt 0) {
            $script:FocusManager.TabOrder.AddRange($focusableComponents)
            Write-Log -Level Info -Message "Added $($script:FocusManager.TabOrder.Count) focusable components to tab order"
            
            # Set focus to the first component
            Request-Focus -Component $script:FocusManager.TabOrder[0] -Reason 'InitialFocus'
        } else {
            Write-Log -Level Warning -Message "No focusable components found on screen '$($Screen.Name)'"
            
            # FALLBACK: Try to manually find buttons using screen's _menuButtons property
            Write-Log -Level Debug -Message "Attempting fallback component discovery..."
            if (($Screen.PSObject.Properties.Name -contains '_menuButtons') -and $Screen._menuButtons -and $Screen._menuButtons.Count -gt 0) {
                Write-Log -Level Info -Message "Found $($Screen._menuButtons.Count) buttons via fallback method"
                foreach ($button in $Screen._menuButtons) {
                    if (($button.PSObject.Properties.Name -contains 'IsFocusable') -and $button.IsFocusable -and 
                        ($button.PSObject.Properties.Name -contains 'Visible') -and $button.Visible) {
                        $script:FocusManager.TabOrder.Add($button)
                        Write-Log -Level Info -Message "Added fallback button: $($button.Name)"
                    }
                }
                
                if ($script:FocusManager.TabOrder.Count -gt 0) {
                    Request-Focus -Component $script:FocusManager.TabOrder[0] -Reason 'FallbackInitialFocus'
                    Write-Log -Level Info -Message "Set focus using fallback method"
                }
            }
            
            # FINAL FALLBACK: Try global TUI state current screen
            if ($script:FocusManager.TabOrder.Count -eq 0 -and $global:TuiState -and $global:TuiState.CurrentScreen) {
                Write-Log -Level Debug -Message "Attempting global TUI state fallback..."
                $currentScreen = $global:TuiState.CurrentScreen
                if (($currentScreen.PSObject.Properties.Name -contains '_menuButtons') -and $currentScreen._menuButtons) {
                    foreach ($button in $currentScreen._menuButtons) {
                        if (($button.PSObject.Properties.Name -contains 'IsFocusable') -and $button.IsFocusable -and 
                            ($button.PSObject.Properties.Name -contains 'Visible') -and $button.Visible) {
                            $script:FocusManager.TabOrder.Add($button)
                            Write-Log -Level Info -Message "Added global fallback button: $($button.Name)"
                        }
                    }
                    
                    if ($script:FocusManager.TabOrder.Count -gt 0) {
                        Request-Focus -Component $script:FocusManager.TabOrder[0] -Reason 'GlobalFallbackInitialFocus'
                        Write-Log -Level Info -Message "Set focus using global fallback method"
                    }
                }
            }
        }
        
        # Store this screen as processed to prevent duplicate processing
        $script:FocusManager.LastScreenProcessed = $Screen
    }
}

function Request-Focus {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [PSCustomObject]$Component,
        [string]$Reason = 'DirectRequest'
    )

    Invoke-WithErrorHandling -Component 'FocusManager.RequestFocus' -Context @{ 
        TargetComponent = if ($Component) { $Component.Name } else { 'null' }
        Reason = $Reason 
    } -ScriptBlock {
        Write-Log -Level Debug -Message "Request-Focus called for component: $(if ($Component) { $Component.Name } else { 'null' }), Reason: $Reason"
        
        # Enhanced focusability check
        if ($Component -and ($Component.PSObject.Properties.Name -contains 'IsFocusable') -and -not $Component.IsFocusable) {
            Write-Log -Level Debug -Message "Request-Focus ignored for non-focusable component '$($Component.Name)'"
            return
        }

        $oldFocused = $script:FocusManager.FocusedComponent

        # If focus is not changing, do nothing
        if ($oldFocused -and $Component -and ($oldFocused.Name -eq $Component.Name)) {
            Write-Log -Level Debug -Message "Focus not changing, already on $($Component.Name)"
            return
        }

        # Blur the previously focused component
        if ($oldFocused) {
            Write-Log -Level Debug -Message "Blurring previous component: $($oldFocused.Name)"
            if (($oldFocused.PSObject.Properties.Name -contains 'IsFocused')) {
                $oldFocused.IsFocused = $false
            }
            if (($oldFocused.PSObject.ScriptMethods.Name -contains 'OnBlur')) {
                try {
                    $oldFocused.OnBlur()
                    Write-Log -Level Trace -Message "Called OnBlur for component '$($oldFocused.Name)'"
                } catch {
                    Write-Log -Level Error -Message "Error in OnBlur for component '$($oldFocused.Name)': $_" -Data $_
                }
            }
        }

        # Update the state to the new component
        $script:FocusManager.FocusedComponent = $Component
        Write-Log -Level Info -Message "Focus changed from '$(if ($oldFocused) { $oldFocused.Name } else { 'null' })' to '$(if ($Component) { $Component.Name } else { 'null' })' (Reason: $Reason)"

        # Focus the new component
        if ($Component) {
            Write-Log -Level Debug -Message "Focusing new component: $($Component.Name)"
            if (($Component.PSObject.Properties.Name -contains 'IsFocused')) {
                $Component.IsFocused = $true
            }
            if (($Component.PSObject.ScriptMethods.Name -contains 'OnFocus')) {
                try {
                    $Component.OnFocus()
                    Write-Log -Level Trace -Message "Called OnFocus for component '$($Component.Name)'"
                } catch {
                    Write-Log -Level Error -Message "Error in OnFocus for component '$($Component.Name)': $_" -Data $_
                }
            }
        }
        
        # Request UI refresh
        if (Get-Command Request-TuiRefresh -ErrorAction SilentlyContinue) {
            Request-TuiRefresh
        }
    }
}

function Move-Focus {
    [CmdletBinding()]
    param([switch]$Reverse)

    Invoke-WithErrorHandling -Component 'FocusManager.MoveFocus' -Context @{ Reverse = $Reverse.IsPresent } -ScriptBlock {
        $tabOrder = $script:FocusManager.TabOrder
        Write-Log -Level Debug -Message "Move-Focus called, Reverse: $($Reverse.IsPresent), TabOrder count: $($tabOrder.Count)"
        
        if ($tabOrder.Count -eq 0) {
            Write-Log -Level Warning -Message "Move-Focus called, but there are no focusable components."
            
            # FALLBACK: Try to refresh focus from current screen
            if ($global:TuiState -and $global:TuiState.CurrentScreen) {
                Write-Log -Level Debug -Message "Attempting to refresh focus from current screen..."
                Update-TabOrderAndFocus -Screen $global:TuiState.CurrentScreen
                
                if ($script:FocusManager.TabOrder.Count -gt 0) {
                    Write-Log -Level Info -Message "Focus refresh successful, retrying Move-Focus"
                    Move-Focus -Reverse:$Reverse.IsPresent
                }
            }
            return
        }

        $currentFocused = $script:FocusManager.FocusedComponent
        $currentIndex = -1
        if ($currentFocused) {
            $currentIndex = $tabOrder.IndexOf($currentFocused)
            Write-Log -Level Debug -Message "Current focused component: $($currentFocused.Name) at index $currentIndex"
        } else {
            Write-Log -Level Debug -Message "No component currently focused"
        }

        $nextIndex = 0
        if ($currentIndex -eq -1) {
            $nextIndex = if ($Reverse) { $tabOrder.Count - 1 } else { 0 }
        } else {
            $increment = if ($Reverse) { -1 } else { 1 }
            $nextIndex = ($currentIndex + $increment + $tabOrder.Count) % $tabOrder.Count
        }

        $nextComponent = $tabOrder[$nextIndex]
        Write-Log -Level Debug -Message "Moving focus to index $nextIndex, component: $($nextComponent.Name)"
        
        Request-Focus -Component $nextComponent -Reason ('TabNavigation' + $(if ($Reverse) { 'Reverse' } else { '' }))
    }
}

function Get-FocusedComponent {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()
    return $script:FocusManager.FocusedComponent
}

function Force-RefreshFocus {
    [CmdletBinding()]
    param()
    
    Invoke-WithErrorHandling -Component 'FocusManager.ForceRefreshFocus' -Context @{} -ScriptBlock {
        Write-Log -Level Info -Message "Force-RefreshFocus called"
        
        if ($global:TuiState -and $global:TuiState.CurrentScreen) {
            Write-Log -Level Debug -Message "Refreshing focus for current screen: $($global:TuiState.CurrentScreen.Name)"
            Update-TabOrderAndFocus -Screen $global:TuiState.CurrentScreen
        } else {
            Write-Log -Level Warning -Message "No current screen available for focus refresh"
        }
    }
}

#endregion

Export-ModuleMember -Function Initialize-FocusManager, Request-Focus, Move-Focus, Get-FocusedComponent, Force-RefreshFocus, Update-TabOrderAndFocus
