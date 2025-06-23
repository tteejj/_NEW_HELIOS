# modules/tui-engine.psm1
# PURPOSE: Core TUI rendering engine implementing the PowerShell-first architecture
# Provides screen management, input processing, and frame rendering with recursive component tree traversal

#region Module Dependencies
Import-Module "$PSScriptRoot\logger.psm1" -Force
Import-Module "$PSScriptRoot\exceptions.psm1" -Force
# NOTE: event-system removed - using PowerShell native eventing

#endregion

#region Core TUI State
# The only global variable allowed per architecture principles
$global:TuiState = [PSCustomObject]@{
    Running = $false
    BufferWidth = 0
    BufferHeight = 0
    FrontBuffer = $null
    BackBuffer = $null
    ScreenStack = New-Object System.Collections.Stack
    CurrentScreen = $null
    IsDirty = $true
    LastActivity = [DateTime]::Now
    LastRenderTime = [DateTime]::MinValue
    RenderStats = @{ 
        LastFrameTime = 0
        FrameCount = 0
        TotalTime = 0
        TargetFPS = 60
    }
    Components = @()
    FocusedComponent = $null
    InputQueue = $null
    InputRunspace = $null
    InputPowerShell = $null
    InputAsyncResult = $null
    CancellationTokenSource = $null
    EventHandlers = @{}
}
#endregion

#region Engine Initialization

function Initialize-TuiEngine {
    param(
        [int]$Width = [Console]::WindowWidth,
        [int]$Height = [Console]::WindowHeight - 1
    )

    Invoke-WithErrorHandling -Component "TuiEngine.Initialize" -Context @{ Operation = "Initialize"; Width = $Width; Height = $Height } -ScriptBlock {
        # Validate parameters
        if ($Width -le 0 -or $Height -le 0) {
            throw "Invalid console dimensions: ${Width}x${Height}"
        }

        Write-Log -Level Info -Message "Initializing TUI Engine: ${Width}x${Height}"

        $global:TuiState.BufferWidth = $Width
        $global:TuiState.BufferHeight = $Height

        # Create 2D arrays for double buffering
        $global:TuiState.FrontBuffer = New-Object 'object[,]' $Height, $Width
        $global:TuiState.BackBuffer = New-Object 'object[,]' $Height, $Width

        # Initialize buffers with empty cells
        for ($y = 0; $y -lt $Height; $y++) {
            for ($x = 0; $x -lt $Width; $x++) {
                $global:TuiState.FrontBuffer[$y, $x] = @{ 
                    Char = ' '
                    FG = [ConsoleColor]::White
                    BG = [ConsoleColor]::Black 
                }
                $global:TuiState.BackBuffer[$y, $x] = @{ 
                    Char = ' '
                    FG = [ConsoleColor]::White
                    BG = [ConsoleColor]::Black 
                }
            }
        }

        # Configure console
        [Console]::CursorVisible = $false
        [Console]::Clear()

        # Initialize input thread
        Initialize-InputThread

        # Register engine event source (using native PowerShell eventing)
        $ErrorActionPreference = 'SilentlyContinue'
        Unregister-Event -SourceIdentifier 'TuiEngine.System' -ErrorAction SilentlyContinue
        $ErrorActionPreference = 'Stop'
        Register-EngineEvent -SourceIdentifier 'TuiEngine.System' -SupportEvent
        
        # Announce initialization
        New-Event -SourceIdentifier 'TuiEngine.System' -EventArguments @{ 
            EventType = 'EngineInitialized'
            Width = $Width
            Height = $Height 
        }

        Write-Log -Level Info -Message "TUI Engine initialized successfully"

    } -ErrorHandler {
        param($Exception)
        Write-Log -Level Error -Message "TUI Engine initialization failed" -Data $Exception
        throw [Helios.ServiceInitializationException]::new( # FIX: Specify full type for custom exception
            "Failed to initialize TUI Engine",
            @{
                OriginalException = $Exception.OriginalError # FIX: Access OriginalError from HeliosException
                Context = $Exception.Context
            },
            $Exception # FIX: Pass original exception as inner
        )
    }
}

function Initialize-InputThread {
    Invoke-WithErrorHandling -Component "TuiEngine.InitializeInput" -Context @{ Operation = "InitializeInputThread" } -ScriptBlock {
        Write-Log -Level Debug -Message "Initializing input thread"

        # Create thread-safe input queue
        try {
            $queueType = [System.Collections.Concurrent.ConcurrentQueue[System.ConsoleKeyInfo]]
            $global:TuiState.InputQueue = New-Object $queueType
        } catch {
            Write-Log -Level Warning -Message "Failed to create ConcurrentQueue, using ArrayList"
            $global:TuiState.InputQueue = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
        }

        # Create cancellation token for clean shutdown
        $global:TuiState.CancellationTokenSource = [System.Threading.CancellationTokenSource]::new()
        $token = $global:TuiState.CancellationTokenSource.Token

        # Create runspace for background input handling
        $runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
        $runspace.Open()
        $runspace.SessionStateProxy.SetVariable('InputQueue', $global:TuiState.InputQueue)
        $runspace.SessionStateProxy.SetVariable('token', $token)

        # Create PowerShell instance for the runspace
        $ps = [System.Management.Automation.PowerShell]::Create()
        $ps.Runspace = $runspace

        # Add input handling script
        $ps.AddScript({
            try {
                while (-not $token.IsCancellationRequested) {
                    if ([Console]::KeyAvailable) {
                        $keyInfo = [Console]::ReadKey($true)
                        
                        if ($InputQueue -is [System.Collections.Concurrent.ConcurrentQueue[System.ConsoleKeyInfo]]) {
                            if ($InputQueue.Count -lt 100) {
                                $InputQueue.Enqueue($keyInfo)
                            }
                        } elseif ($InputQueue -is [System.Collections.ArrayList]) {
                            if ($InputQueue.Count -lt 100) {
                                $InputQueue.Add($keyInfo) | Out-Null
                            }
                        }
                    } else {
                        Start-Sleep -Milliseconds 20
                    }
                }
            } catch [System.Management.Automation.PipelineStoppedException] {
                return
            } catch {
                Write-Warning "Input thread error: $_"
            }
        }) | Out-Null

        # Store references for cleanup
        $global:TuiState.InputRunspace = $runspace
        $global:TuiState.InputPowerShell = $ps
        $global:TuiState.InputAsyncResult = $ps.BeginInvoke()

        Write-Log -Level Debug -Message "Input thread initialized"

    } -ErrorHandler {
        param($Exception)
        Write-Log -Level Error -Message "Failed to initialize input thread" -Data $Exception
        throw # Re-throw as a HeliosException already wrapped by Invoke-WithErrorHandling
    }
}

#endregion

#region Main Loop

function Start-TuiLoop {
    param([PSCustomObject]$InitialScreen = $null)

    Invoke-WithErrorHandling -Component "TuiEngine.MainLoop" -Context @{ InitialScreen = $InitialScreen?.Name } -ScriptBlock {
        # Initialize if not already done
        if (-not $global:TuiState.BufferWidth -or $global:TuiState.BufferWidth -eq 0) {
            Initialize-TuiEngine
        }

        if ($InitialScreen) {
            Push-Screen -Screen $InitialScreen
        }

        # Validate we have a screen to display
        if (-not $global:TuiState.CurrentScreen -and $global:TuiState.ScreenStack.Count -eq 0) {
            throw "No screen available to display"
        }

        $global:TuiState.Running = $true
        $frameTime = New-Object System.Diagnostics.Stopwatch
        $targetFrameTime = 1000.0 / $global:TuiState.RenderStats.TargetFPS

        Write-Log -Level Info -Message "Starting TUI main loop"

        while ($global:TuiState.Running) {
            try {
                $frameTime.Restart()

                # Process input
                $hadInput = Process-TuiInput

                # Update dialog system if available
                # NOTE: Update-DialogSystem is not defined in any provided module.
                # If this is intended functionality, it would need to be added
                # to the dialog-system.psm1 module. Commenting out for now to prevent CommandNotFound errors.
                # if (Get-Command -Name "Update-DialogSystem" -ErrorAction SilentlyContinue) {
                #     try { Update-DialogSystem } catch { Write-Log -Level Warning -Message "Dialog update error: $_" }
                # }

                # Render frame if needed
                if ($global:TuiState.IsDirty -or $hadInput) {
                    Render-Frame
                    $global:TuiState.IsDirty = $false
                }

                # Frame timing
                $elapsed = $frameTime.ElapsedMilliseconds
                if ($elapsed -lt $targetFrameTime) {
                    $sleepTime = [Math]::Max(1, $targetFrameTime - $elapsed)
                    Start-Sleep -Milliseconds $sleepTime
                }

            } catch [Helios.HeliosException] { # FIX: Use full exception type
                # Handle recoverable errors
                $exception = $_.Exception
                Write-Log -Level Error -Message "TUI Exception occurred: $($exception.Message)" -Data $exception.DetailedContext # FIX: Access DetailedContext
                
                if (Get-Command -Name "Show-AlertDialog" -ErrorAction SilentlyContinue) {
                    Show-AlertDialog -Title "Application Error" -Message "An operation failed: $($exception.Message)"
                }
                
                $global:TuiState.IsDirty = $true

            } catch {
                # Handle fatal errors (standard PowerShell errors not wrapped by Invoke-WithErrorHandling)
                Write-Log -Level Error -Message "Fatal TUI error: $($_.Exception.Message)" -Data $_ # Data includes ErrorRecord
                
                if (Get-Command -Name "Show-AlertDialog" -ErrorAction SilentlyContinue) {
                    Show-AlertDialog -Title "Fatal Error" -Message "A critical error occurred. The application will now close."
                }
                
                $global:TuiState.Running = $false
            }
        }

    } -ErrorHandler {
        param($Exception)
        Write-Log -Level Error -Message "Main loop error" -Data $Exception
        throw # Re-throw as a HeliosException already wrapped by Invoke-WithErrorHandling
    } -Finally {
        Cleanup-TuiEngine
    }
}

# FIX: Corrected and singular Process-TuiInput function
function Process-TuiInput {
    if (-not $global:TuiState.InputQueue) { return $false }

    $processedAny = $false
    
    Invoke-WithErrorHandling -Component "TuiEngine.ProcessInput" -Context @{ Operation = "ProcessInputQueue" } -ScriptBlock {
        Write-Log -Level Verbose -Message "Processing input queue"

        if ($global:TuiState.InputQueue -is [System.Collections.Concurrent.ConcurrentQueue[System.ConsoleKeyInfo]]) {
            $keyInfo = [System.ConsoleKeyInfo]::new([char]0, [System.ConsoleKey]::None, $false, $false, $false)
            # FIX: Removed [ref] keyword for TryDequeue - pass variable directly for 'out' parameter
            while ($global:TuiState.InputQueue.TryDequeue($keyInfo)) {
                $processedAny = $true
                $global:TuiState.LastActivity = [DateTime]::Now
                Process-SingleKeyInput -keyInfo $keyInfo
            }
        } elseif ($global:TuiState.InputQueue -is [System.Collections.ArrayList]) {
            while ($global:TuiState.InputQueue.Count -gt 0) {
                try {
                    $keyInfo = $global:TuiState.InputQueue[0]
                    $global:TuiState.InputQueue.RemoveAt(0)
                    $processedAny = $true
                    $global:TuiState.LastActivity = [DateTime]::Now
                    Process-SingleKeyInput -keyInfo $keyInfo
                } catch {
                    break
                }
            }
        }

    } -ErrorHandler {
        param($Exception)
        Write-Log -Level Error -Message "Error processing input" -Data $Exception
        Request-TuiRefresh
    }

    return $processedAny
}

function Process-SingleKeyInput {
    param($keyInfo)

    Invoke-WithErrorHandling -Component "TuiEngine.ProcessSingleKey" -Context @{ Key = $keyInfo.Key; Operation = "ProcessSingleKeyInput" } -ScriptBlock {
        # Handle Tab navigation
        if ($keyInfo.Key -eq [ConsoleKey]::Tab) {
            Handle-TabNavigation -Reverse ($keyInfo.Modifiers -band [ConsoleModifiers]::Shift)
            return
        }

        # Let dialog system handle input first
        if ((Get-Command -Name "Handle-DialogInput" -ErrorAction SilentlyContinue) -and 
            (Handle-DialogInput -Key $keyInfo)) {
            return
        }

        # Focused component gets next chance
        # Ensure HandleInput exists as a ScriptMethod (or other callable member type)
        if ($global:TuiState.FocusedComponent -and $global:TuiState.FocusedComponent.PSObject.ScriptMethods['HandleInput']) {
            if ($global:TuiState.FocusedComponent.HandleInput($keyInfo)) { # Direct call, no & needed for ScriptMethod
                return
            }
        }

        # Finally, the screen handles input
        # Ensure HandleInput exists as a ScriptMethod (or other callable member type)
        if ($global:TuiState.CurrentScreen -and $global:TuiState.CurrentScreen.PSObject.ScriptMethods['HandleInput']) {
            $result = $global:TuiState.CurrentScreen.HandleInput($keyInfo) # Direct call, no & needed for ScriptMethod
            switch ($result) {
                "Back" { Pop-Screen }
                "Quit" { 
                    $global:TuiState.Running = $false
                    if ($global:TuiState.CancellationTokenSource) {
                        $global:TuiState.CancellationTokenSource.Cancel()
                    }
                }
            }
        }

    } -ErrorHandler {
        param($Exception)
        Write-Log -Level Warning -Message "Input processing error" -Data $Exception
    }
}

#endregion

#region Frame Rendering - CRITICAL RECURSIVE IMPLEMENTATION

function Render-Frame {
    Invoke-WithErrorHandling -Component "TuiEngine.RenderFrame" -Context @{ Operation = "RenderFrame" } -ScriptBlock {
        Write-Log -Level Verbose -Message "Starting recursive frame render"

        # Get background color
        $bgColor = if (Get-Command -Name "Get-ThemeColor" -ErrorAction SilentlyContinue) {
            Get-ThemeColor "Background"
        } else {
            [ConsoleColor]::Black
        }

        # Clear the back buffer
        Clear-BackBuffer -BackgroundColor $bgColor

        # 1. Render screen chrome (header, footer, etc.)
        if ($global:TuiState.CurrentScreen -and $global:TuiState.CurrentScreen.PSObject.ScriptMethods['Render']) {
            $global:TuiState.CurrentScreen.Render() # Direct call, no & needed for ScriptMethod
        }

        # 2. COLLECT all visible components recursively
        $renderQueue = [System.Collections.Generic.List[PSCustomObject]]::new()

        # Define the recursive collection function
        $collectComponents = {
            param($component)
            
            if (-not $component -or $component.Visible -eq $false) { return }

            # Add component to render queue
            $renderQueue.Add($component)

            Write-Log -Level Debug -Message "Collected component: Type=$($component.Type), Name=$($component.Name), Pos=($($component.X),$($component.Y)), ZIndex=$($component.ZIndex), Children=$($component.Children.Count)"

            # Check if this is a panel and needs layout calculation
            # Ensure CalculateLayout exists as a ScriptMethod (or other callable member type)
            if ($component.PSObject.ScriptMethods['CalculateLayout']) {
                try {
                    Write-Log -Level Debug -Message "Calculating layout for panel: $($component.Name)"
                    [void]($component.CalculateLayout()) # Direct call, no & needed for ScriptMethod
                } catch {
                    Write-Log -Level Error -Message "Layout calculation failed for '$($component.Name)'" -Data $_
                }
            }

            # Recursively collect children
            if ($component.Children -and $component.Children.Count -gt 0) {
                foreach ($child in $component.Children) {
                    & $collectComponents $child
                }
            }
        }

        # Start collection from screen's children
        if ($global:TuiState.CurrentScreen -and $global:TuiState.CurrentScreen.Children) {
            Write-Log -Level Debug -Message "Starting collection from screen children: Count=$($global:TuiState.CurrentScreen.Children.Count)"
            foreach ($child in $global:TuiState.CurrentScreen.Children) {
                & $collectComponents $child
            }
        }

        # Also collect from any active dialogs
        # FIX: Changed Get-CurrentDialog to Get-ActiveDialog, as exported by dialog-system.psm1
        if (Get-Command -Name "Get-ActiveDialog" -ErrorAction SilentlyContinue) {
            $currentDialog = Get-ActiveDialog
            if ($currentDialog) {
                Write-Log -Level Debug -Message "Collecting dialog components"
                & $collectComponents $currentDialog
            }
        }

        # 3. SORT components by ZIndex
        $sortedComponents = $renderQueue | Sort-Object -Property @{
            Expression = { if ($null -ne $_.ZIndex) { $_.ZIndex } else { 0 } }
        }

        Write-Log -Level Debug -Message "Rendering $($sortedComponents.Count) components sorted by ZIndex"

        # 4. RENDER each component
        foreach ($component in $sortedComponents) {
            # Ensure Render exists as a ScriptMethod (or other callable member type)
            if ($component.PSObject.ScriptMethods['Render']) {
                Invoke-WithErrorHandling -Component "$($component.Name ?? $component.Type).Render" -Context @{ 
                    Operation = "RenderComponent";
                    ComponentType = $component.Type;
                    ComponentName = $component.Name
                } -ScriptBlock {
                    $component.Render() # Direct call, no & needed for ScriptMethod
                } -ErrorHandler {
                    param($Exception)
                    Write-Log -Level Error -Message "Component render error" -Data $Exception
                    throw [Helios.ComponentRenderException]::new( # FIX: Specify full type for custom exception
                        "Failed to render component '$($Exception.Context.ComponentName ?? $Exception.Context.ComponentType)'",
                        @{
                            FailingComponent = $component
                            OriginalException = $Exception.OriginalError # FIX: Access OriginalError from HeliosException
                        },
                        $Exception # FIX: Pass original exception as inner
                    )
                }
            }
        }

        # 5. Swap buffers and display
        Render-BufferOptimized

        # Position cursor out of the way
        [Console]::SetCursorPosition($global:TuiState.BufferWidth - 1, $global:TuiState.BufferHeight - 1)

    } -ErrorHandler {
        param($Exception)
        Write-Log -Level Error -Message "Fatal frame render error" -Data $Exception
        throw # Re-throw as a HeliosException already wrapped by Invoke-WithErrorHandling
    }
}

function Render-BufferOptimized {
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $outputBuilder = New-Object System.Text.StringBuilder -ArgumentList 20000
    $lastFG = -1
    $lastBG = -1
    
    $forceFullRender = $global:TuiState.RenderStats.FrameCount -eq 0
    
    Invoke-WithErrorHandling -Component "TuiEngine.RenderBuffer" -Context @{ Operation = "RenderBufferOptimized" } -ScriptBlock {
        # Build ANSI output with change detection
        for ($y = 0; $y -lt $global:TuiState.BufferHeight; $y++) {
            $outputBuilder.Append("$([char]27)[$($y + 1);1H") | Out-Null
            
            for ($x = 0; $x -lt $global:TuiState.BufferWidth; $x++) {
                $backCell = $global:TuiState.BackBuffer[$y, $x]
                $frontCell = $global:TuiState.FrontBuffer[$y, $x]
                
                # Skip unchanged cells unless forcing full render
                if (-not $forceFullRender -and
                    $backCell.Char -eq $frontCell.Char -and 
                    $backCell.FG -eq $frontCell.FG -and 
                    $backCell.BG -eq $frontCell.BG) {
                    continue
                }
                
                # Position cursor if we skipped cells
                if ($x -gt 0 -and $outputBuilder.Length -gt 0) {
                    $outputBuilder.Append("$([char]27)[$($y + 1);$($x + 1)H") | Out-Null
                }
                
                # Update colors if changed
                if ($backCell.FG -ne $lastFG -or $backCell.BG -ne $lastBG) {
                    $fgCode = Get-AnsiColorCode $backCell.FG
                    $bgCode = Get-AnsiColorCode $backCell.BG -IsBackground $true
                    $outputBuilder.Append("$([char]27)[${fgCode};${bgCode}m") | Out-Null
                    $lastFG = $backCell.FG
                    $lastBG = $backCell.BG
                }
                
                $outputBuilder.Append($backCell.Char) | Out-Null
                
                # Update front buffer
                $global:TuiState.FrontBuffer[$y, $x] = @{
                    Char = $backCell.Char
                    FG = $backCell.FG
                    BG = $backCell.BG
                }
            }
        }
        
        # Reset ANSI formatting
        $outputBuilder.Append("$([char]27)[0m") | Out-Null
        
        # Write to console
        if ($outputBuilder.Length -gt 0) {
            [Console]::Write($outputBuilder.ToString())
        }
        
    } -ErrorHandler {
        param($Exception)
        Write-Log -Level Warning -Message "Render buffer error" -Data $Exception
    }
    
    # Update stats
    $stopwatch.Stop()
    $global:TuiState.RenderStats.LastFrameTime = $stopwatch.ElapsedMilliseconds
    $global:TuiState.RenderStats.FrameCount++
    $global:TuiState.RenderStats.TotalTime += $stopwatch.ElapsedMilliseconds
}

#endregion

#region Screen Management

function Push-Screen {
    param([PSCustomObject]$Screen)
    
    if (-not $Screen) { return }
    
    Invoke-WithErrorHandling -Component "TuiEngine.PushScreen" -Context @{ Operation = "PushScreen"; ScreenName = $Screen.Name } -ScriptBlock {
        Write-Log -Level Debug -Message "Pushing screen: $($Screen.Name)"
        
        # Handle focus cleanup
        # Ensure OnBlur exists as a ScriptMethod (or other callable member type)
        if ($global:TuiState.FocusedComponent -and $global:TuiState.FocusedComponent.PSObject.ScriptMethods['OnBlur']) {
            $global:TuiState.FocusedComponent.OnBlur() # Direct call, no & needed for ScriptMethod
        }
        
        # Exit current screen
        if ($global:TuiState.CurrentScreen) {
            # Ensure OnExit exists as a ScriptMethod (or other callable member type)
            if ($global:TuiState.CurrentScreen.PSObject.ScriptMethods['OnExit']) {
                $global:TuiState.CurrentScreen.OnExit() # Direct call, no & needed for ScriptMethod
            }
            $global:TuiState.ScreenStack.Push($global:TuiState.CurrentScreen)
        }
        
        # Set new screen
        $global:TuiState.CurrentScreen = $Screen
        $global:TuiState.FocusedComponent = $null
        
        # Initialize new screen
        # Ensure Init exists as a ScriptMethod (or other callable member type)
        if ($Screen.PSObject.ScriptMethods['Init']) {
            if ($Screen._services) {
                $Screen.Init -services $Screen._services # Direct call, no & needed for ScriptMethod
            } else {
                $Screen.Init() # Direct call, no & needed for ScriptMethod
            }
        }
        
        Request-TuiRefresh
        
        # Publish event (using native PowerShell eventing)
        New-Event -SourceIdentifier 'TuiEngine.System' -EventArguments @{ 
            EventType = 'ScreenPushed'
            ScreenName = $Screen.Name 
        }
        
    } -ErrorHandler {
        param($Exception)
        Write-Log -Level Error -Message "Failed to push screen" -Data $Exception
        throw [Helios.ServiceInitializationException]::new( # FIX: Specify full type for custom exception
            "Failed to initialize screen '$($Exception.Context.ScreenName)'",
            @{
                FailingScreen = $Screen
                OriginalException = $Exception.OriginalError # FIX: Access OriginalError from HeliosException
            },
            $Exception # FIX: Pass original exception as inner
        )
    }
}

function Pop-Screen {
    if ($global:TuiState.ScreenStack.Count -eq 0) { return $false }
    
    Invoke-WithErrorHandling -Component "TuiEngine.PopScreen" -Context @{ Operation = "PopScreen" } -ScriptBlock {
        Write-Log -Level Debug -Message "Popping screen"
        
        # Handle focus cleanup
        # Ensure OnBlur exists as a ScriptMethod (or other callable member type)
        if ($global:TuiState.FocusedComponent -and $global:TuiState.FocusedComponent.PSObject.ScriptMethods['OnBlur']) {
            $global:TuiState.FocusedComponent.OnBlur() # Direct call, no & needed for ScriptMethod
        }
        
        # Store screen to exit
        $screenToExit = $global:TuiState.CurrentScreen
        
        # Pop new screen from stack
        $global:TuiState.CurrentScreen = $global:TuiState.ScreenStack.Pop()
        $global:TuiState.FocusedComponent = $null
        
        # Call lifecycle hooks
        # Ensure OnExit exists as a ScriptMethod (or other callable member type)
        if ($screenToExit -and $screenToExit.PSObject.ScriptMethods['OnExit']) {
            $screenToExit.OnExit() # Direct call, no & needed for ScriptMethod
        }
        
        # Ensure OnResume exists as a ScriptMethod (or other callable member type)
        if ($global:TuiState.CurrentScreen -and $global:TuiState.CurrentScreen.PSObject.ScriptMethods['OnResume']) {
            $global:TuiState.CurrentScreen.OnResume() # Direct call, no & needed for ScriptMethod
        }
        
        # Restore focus if tracked (Note: Set-ComponentFocus is internal to TuiEngine)
        if ($global:TuiState.CurrentScreen.LastFocusedComponent) {
            Set-ComponentFocus -Component $global:TuiState.CurrentScreen.LastFocusedComponent
        }
        
        Request-TuiRefresh
        
        # Publish event (using native PowerShell eventing)
        New-Event -SourceIdentifier 'TuiEngine.System' -EventArguments @{ 
            EventType = 'ScreenPopped'
            ScreenName = $global:TuiState.CurrentScreen.Name 
        }
        
        return $true
        
    } -ErrorHandler {
        param($Exception)
        Write-Log -Level Warning -Message "Pop screen error" -Data $Exception
        return $false
    }
}

#endregion

#region Buffer Operations

function Clear-BackBuffer {
    param([ConsoleColor]$BackgroundColor = [ConsoleColor]::Black)
    
    # Clear entire back buffer
    for ($y = 0; $y -lt $global:TuiState.BufferHeight; $y++) {
        for ($x = 0; $x -lt $global:TuiState.BufferWidth; $x++) {
            $global:TuiState.BackBuffer[$y, $x] = @{ 
                Char = ' '
                FG = [ConsoleColor]::White
                BG = $BackgroundColor 
            }
        }
    }
}

function Write-BufferString {
    param(
        [int]$X, 
        [int]$Y, 
        [string]$Text, 
        [ConsoleColor]$ForegroundColor = [ConsoleColor]::White, 
        [ConsoleColor]$BackgroundColor = [ConsoleColor]::Black
    )
    
    if ($Y -lt 0 -or $Y -ge $global:TuiState.BufferHeight) { return }
    if ([string]::IsNullOrEmpty($Text)) { return }
    
    $currentX = $X
    foreach ($char in $Text.ToCharArray()) {
        if ($currentX -ge $global:TuiState.BufferWidth) { break }

        if ($currentX -ge 0) {
            $global:TuiState.BackBuffer[$Y, $currentX] = @{ 
                Char = $char
                FG = $ForegroundColor
                BG = $BackgroundColor 
            }
        }
        
        # Handle wide characters
        # Check if the character is considered wide (e.g., East Asian width)
        # This regex broadly covers CJK Unified Ideographs, Hangul Syllables, etc.
        if ($char -match '[\u1100-\u11FF\u2E80-\uA4CF\uAC00-\uD7A3\uF900-\uFAFF\uFE30-\uFE4F\uFF00-\uFFEF]') {
            $currentX += 2
            if ($currentX -lt $global:TuiState.BufferWidth -and $currentX -gt 0) {
                # Ensure the space for wide characters is also filled with the background color
                $global:TuiState.BackBuffer[$Y, $currentX - 1] = @{ 
                    Char = ' '
                    FG = $ForegroundColor # Use the same FG/BG for the blank space
                    BG = $BackgroundColor 
                }
            }
        } else {
            $currentX++
        }
    }
}

function Write-BufferBox {
    param(
        [int]$X, 
        [int]$Y, 
        [int]$Width, 
        [int]$Height, 
        [string]$BorderStyle = "Single", 
        [ConsoleColor]$BorderColor = [ConsoleColor]::White, 
        [ConsoleColor]$BackgroundColor = [ConsoleColor]::Black, 
        [string]$Title = ""
    )
    
    # Defensive checks for dimensions
    if ($Width -lt 2 -or $Height -lt 2) { return } # Minimum size for a box with borders
    
    $borders = Get-BorderChars -Style $BorderStyle
    
    # Calculate effective coordinates considering bounds
    $startX = [Math]::Max(0, $X)
    $startY = [Math]::Max(0, $Y)
    $endX = [Math]::Min($global:TuiState.BufferWidth - 1, $X + $Width - 1)
    $endY = [Math]::Min($global:TuiState.BufferHeight - 1, $Y + $Height - 1)
    
    $actualWidth = $endX - $startX + 1
    $actualHeight = $endY - $startY + 1
    
    if ($actualWidth -lt 2 -or $actualHeight -lt 2) { return } # Box too small after clipping

    # Fill background first within the actual bounds
    for ($row = $startY; $row -le $endY; $row++) {
        for ($col = $startX; $col -le $endX; $col++) {
            $global:TuiState.BackBuffer[$row, $col] = @{ 
                Char = ' '; FG = [ConsoleColor]::White; BG = $BackgroundColor 
            }
        }
    }

    # Top border
    if ($actualHeight -ge 1) { # Ensure there's space for a top border
        if ($startX -le $endX) {
            Write-BufferString -X $startX -Y $startY -Text $borders.TopLeft -ForegroundColor $BorderColor -BackgroundColor $BackgroundColor
        }
        if ($startX + 1 -le $endX - 1) {
            Write-BufferString -X ($startX + 1) -Y $startY -Text ($borders.Horizontal * ($actualWidth - 2)) -ForegroundColor $BorderColor -BackgroundColor $BackgroundColor
        }
        if ($startX -le $endX -1) {
            Write-BufferString -X $endX -Y $startY -Text $borders.TopRight -ForegroundColor $BorderColor -BackgroundColor $BackgroundColor
        }
    }
    
    # Title if provided
    if ($Title) {
        $titleText = " $Title "
        $displayTitleWidth = $actualWidth - 2 # Space inside borders
        
        if ($titleText.Length -gt $displayTitleWidth) {
            $maxLength = [Math]::Max(0, $displayTitleWidth - 3) # Account for "..."
            if ($maxLength -ge 0) {
                $titleText = $titleText.Substring(0, $maxLength) + "..."
            } else {
                $titleText = "" # Not enough space for "..."
            }
        }
        
        $titleX = $startX + [Math]::Floor(($actualWidth - $titleText.Length) / 2)
        # Ensure title starts and ends within horizontal border area
        $titleX = [Math]::Max($startX + 1, [Math]::Min($endX - $titleText.Length, $titleX))

        Write-BufferString -X $titleX -Y $startY -Text $titleText `
            -ForegroundColor $BorderColor -BackgroundColor $BackgroundColor
    }
    
    # Sides and fill (from second row to second-to-last row)
    for ($i = 1; $i -lt ($actualHeight - 1); $i++) {
        $currentRowY = $startY + $i
        if ($currentRowY -gt $endY) { break } # Should not happen if loop limits are correct
        
        # Left vertical border
        Write-BufferString -X $startX -Y $currentRowY -Text $borders.Vertical `
            -ForegroundColor $BorderColor -BackgroundColor $BackgroundColor
        
        # Fill inner content area
        if ($actualWidth - 2 -gt 0) {
            Write-BufferString -X ($startX + 1) -Y $currentRowY -Text (' ' * ($actualWidth - 2)) `
                -BackgroundColor $BackgroundColor
        }
        
        # Right vertical border
        Write-BufferString -X $endX -Y $currentRowY -Text $borders.Vertical `
            -ForegroundColor $BorderColor -BackgroundColor $BackgroundColor
    }
    
    # Bottom border
    if ($actualHeight -ge 1) { # Ensure there's space for a bottom border
        $bottomY = $endY
        if ($bottomY -ge $startY) { # Ensure bottomY is valid
            if ($startX -le $endX) {
                Write-BufferString -X $startX -Y $bottomY `
                    -Text $borders.BottomLeft -ForegroundColor $BorderColor -BackgroundColor $BackgroundColor
            }
            if ($startX + 1 -le $endX - 1) {
                Write-BufferString -X ($startX + 1) -Y $bottomY `
                    -Text ($borders.Horizontal * ($actualWidth - 2)) -ForegroundColor $BorderColor -BackgroundColor $BackgroundColor
            }
            if ($startX -le $endX -1) {
                Write-BufferString -X $endX -Y $bottomY `
                    -Text $borders.BottomRight -ForegroundColor $BorderColor -BackgroundColor $BackgroundColor
            }
        }
    }
}

#endregion

#region Component Focus Management

function Set-ComponentFocus {
    param([PSCustomObject]$Component)
    
    Invoke-WithErrorHandling -Component "TuiEngine.SetFocus" -Context @{ Operation = "SetComponentFocus"; ComponentName = $Component?.Name } -ScriptBlock {
        # Blur current focused component
        if ($global:TuiState.FocusedComponent -and 
            $global:TuiState.FocusedComponent -ne $Component) {
            $global:TuiState.FocusedComponent.IsFocused = $false
            # Ensure OnBlur exists as a ScriptMethod (or other callable member type)
            if ($global:TuiState.FocusedComponent.PSObject.ScriptMethods['OnBlur']) {
                $global:TuiState.FocusedComponent.OnBlur() # Direct call, no & needed for ScriptMethod
            }
        }

        # Clear focus if null component
        if ($null -eq $Component) {
            $global:TuiState.FocusedComponent = $null
            Request-TuiRefresh
            return
        }

        # Validate component can be focused
        if ($Component.PSObject.Properties['IsFocusable'] -and $Component.IsFocusable -ne $true -or 
            $Component.PSObject.Properties['Visible'] -and $Component.Visible -ne $true) {
            Write-Log -Level Debug -Message "Set-ComponentFocus ignored for non-focusable or invisible component '$($Component.Name)'"
            return
        }

        # Set new focus
        $global:TuiState.FocusedComponent = $Component
        $Component.IsFocused = $true
        
        # Ensure OnFocus exists as a ScriptMethod (or other callable member type)
        if ($Component.PSObject.ScriptMethods['OnFocus']) {
            $Component.OnFocus() # Direct call, no & needed for ScriptMethod
        }
        
        Request-TuiRefresh
        
    } -ErrorHandler {
        param($Exception)
        Write-Log -Level Warning -Message "Set focus error" -Data $Exception
    }
}

function Handle-TabNavigation {
    param([bool]$Reverse = $false)
    
    Invoke-WithErrorHandling -Component "TuiEngine.TabNavigation" -Context @{ Operation = "HandleTabNavigation"; Reverse = $Reverse } -ScriptBlock {
        $currentScreen = $global:TuiState.CurrentScreen
        if (-not $currentScreen) { return }

        $focusable = @() # Local variable for this function call
        
        $findFocusable = {
            param($component)
            # Ensure IsFocusable and Visible properties exist before checking them
            if ($component -and 
                $component.PSObject.Properties['IsFocusable'] -and $component.IsFocusable -eq $true -and 
                $component.PSObject.Properties['Visible'] -and $component.Visible -eq $true) {
                $focusable += $component 
            }
            if ($component -and $component.PSObject.Properties['Children'] -and $component.Children) {
                foreach ($child in $component.Children) {
                    & $findFocusable -component $child
                }
            }
        }
        
        # Start from screen's RootPanel (if available) or children directly
        # Changed logic to always start traversal from CurrentScreen.RootPanel, consistent with focus-manager and dialog-system
        if ($currentScreen.RootPanel) {
            & $findFocusable -component $currentScreen.RootPanel
        } elseif ($currentScreen.Children) { # Fallback for screens without a dedicated RootPanel
            foreach ($child in $currentScreen.Children) {
                & $findFocusable -component $child
            }
        }

        if ($focusable.Count -eq 0) {
            Write-Log -Level Debug -Message "No focusable components found on current screen for tab navigation."
            return
        }

        # Sort by Y then X for a natural tab order
        $sortedFocusable = $focusable | Sort-Object { $_.Y }, { $_.X }

        # Find current index
        $currentIndex = [array]::IndexOf($sortedFocusable, $global:TuiState.FocusedComponent)
        
        # Calculate next index
        $nextIndex = 0
        if ($currentIndex -ne -1) {
            $direction = if ($Reverse) { -1 } else { 1 }
            $nextIndex = ($currentIndex + $direction + $sortedFocusable.Count) % $sortedFocusable.Count
        } else {
            # If no component is currently focused, start from the beginning (or end if reversing)
            $nextIndex = if ($Reverse) { $sortedFocusable.Count - 1 } else { 0 }
        }

        Set-ComponentFocus -Component $sortedFocusable[$nextIndex]
        
    } -ErrorHandler {
        param($Exception)
        Write-Log -Level Warning -Message "Tab navigation error" -Data $Exception
    }
}

function Clear-ComponentFocus {
    Set-ComponentFocus -Component $null
}

#endregion

#region Utility Functions

function Request-TuiRefresh {
    $global:TuiState.IsDirty = $true
}

function Get-BorderChars {
    param([string]$Style)
    
    $styles = @{
        Single = @{
            TopLeft = '┌'; TopRight = '┐'
            BottomLeft = '└'; BottomRight = '┘'
            Horizontal = '─'; Vertical = '│'
        }
        Double = @{
            TopLeft = '╔'; TopRight = '╗'
            BottomLeft = '╚'; BottomRight = '╝'
            Horizontal = '═'; Vertical = '║'
        }
        Rounded = @{
            TopLeft = '╭'; TopRight = '╮'
            BottomLeft = '╰'; BottomRight = '╯'
            Horizontal = '─'; Vertical = '│'
        }
    }
    
    if ($styles.ContainsKey($Style)) {
        return $styles[$Style]
    } else {
        return $styles.Single
    }
}

function Get-AnsiColorCode {
    param(
        [ConsoleColor]$Color,
        [bool]$IsBackground
    )
    
    $map = @{
        Black = 30; DarkBlue = 34; DarkGreen = 32; DarkCyan = 36
        DarkRed = 31; DarkMagenta = 35; DarkYellow = 33; Gray = 37
        DarkGray = 90; Blue = 94; Green = 92; Cyan = 96
        Red = 91; Magenta = 95; Yellow = 93; White = 97
    }
    
    $code = $map[$Color.ToString()]
    if ($IsBackground) {
        return $code + 10
    } else {
        return $code
    }
}

function Get-WordWrappedLines {
    param(
        [string]$Text,
        [int]$MaxWidth
    )
    
    if ([string]::IsNullOrEmpty($Text) -or $MaxWidth -le 0) { return @() }
    
    $lines = @()
    # Split by whitespace, but keep original spaces for reconstruction if possible
    # This regex splits by one or more whitespace characters, so original spacing is lost
    $words = $Text -split '\s+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } # Remove empty strings from split
    
    $sb = New-Object System.Text.StringBuilder
    
    foreach ($word in $words) {
        if ($sb.Length -eq 0) {
            [void]$sb.Append($word)
        } elseif (($sb.Length + 1 + $word.Length) -le $MaxWidth) {
            [void]$sb.Append(' ')
            [void]$sb.Append($word)
        } else {
            # If adding the next word with a space exceeds max width
            $lines += $sb.ToString()
            [void]$sb.Clear()
            [void]$sb.Append($word)
        }
    }
    
    if ($sb.Length -gt 0) {
        $lines += $sb.ToString()
    }
    
    return $lines
}

#endregion

#region Cleanup

function Cleanup-TuiEngine {
    Invoke-WithErrorHandling -Component "TuiEngine.Cleanup" -Context @{ Operation = "Cleanup" } -ScriptBlock {
        Write-Log -Level Info -Message "Cleaning up TUI Engine"
        
        # Cancel input thread
        if ($global:TuiState.CancellationTokenSource) {
            try {
                if (-not $global:TuiState.CancellationTokenSource.IsCancellationRequested) {
                    $global:TuiState.CancellationTokenSource.Cancel()
                }
            } catch {}
        }

        # Clean up PowerShell instance
        if ($global:TuiState.InputPowerShell) {
            if ($global:TuiState.InputAsyncResult) {
                try { $global:TuiState.InputPowerShell.EndInvoke($global:TuiState.InputAsyncResult) } catch {}
            }
            try { $global:TuiState.InputPowerShell.Dispose() } catch {}
        }
        
        # Clean up runspace
        if ($global:TuiState.InputRunspace) {
            try { $global:TuiState.InputRunspace.Dispose() } catch {}
        }
        
        # Dispose cancellation token
        if ($global:TuiState.CancellationTokenSource) {
            try { $global:TuiState.CancellationTokenSource.Dispose() } catch {}
        }

        # Clean up event handlers
        Cleanup-EventHandlers
        
        # Reset console
        try {
            if ([System.Environment]::UserInteractive) {
                [Console]::Write("$([char]27)[0m")
                [Console]::CursorVisible = $true
                [Console]::Clear()
                [Console]::ResetColor()
            }
        } catch {}
        
    } -ErrorHandler {
        param($Exception)
        Write-Log -Level Warning -Message "Cleanup error" -Data $Exception
    }
}

function Cleanup-EventHandlers {
    if (-not $global:TuiState.EventHandlers) { return }

    foreach ($handlerId in $global:TuiState.EventHandlers.Values) {
        try { 
            Unregister-Event -SubscriptionId $handlerId -ErrorAction SilentlyContinue
        } catch {}
    }
    
    $global:TuiState.EventHandlers.Clear()
}

#endregion

# Export functions
Export-ModuleMember -Function @(
    'Initialize-TuiEngine',
    'Start-TuiLoop',
    'Request-TuiRefresh',
    'Push-Screen',
    'Pop-Screen',
    'Write-BufferString',
    'Write-BufferBox',
    'Clear-BackBuffer',
    'Set-ComponentFocus',
    'Clear-ComponentFocus',
    'Handle-TabNavigation',
    'Get-BorderChars',
    'Get-AnsiColorCode',
    'Get-WordWrappedLines',
    'Render-Frame',
    'Cleanup-TuiEngine'
) -Variable @('TuiState')