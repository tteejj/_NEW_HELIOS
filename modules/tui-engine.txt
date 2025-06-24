# modules/tui-engine.psm1
# PURPOSE: Core TUI rendering engine implementing the PowerShell-first architecture
# Provides screen management, input processing, and frame rendering with recursive component tree traversal

#region Module Dependencies
#Import-Module "$PSScriptRoot\logger.psm1" -Force
#Import-Module "$PSScriptRoot\exceptions.psm1" -Force
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
        # Note: We don't need Register-EngineEvent here since New-Event will create the source automatically
        
        # Announce initialization
        New-Event -SourceIdentifier 'TuiEngine.System' -EventArguments @{ 
            EventType = 'EngineInitialized'
            Width = $Width
            Height = $Height 
        }

        Write-Log -Level Info -Message "TUI Engine initialized successfully"
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
    }
}

#endregion

#region Main Loop

function Start-TuiLoop {
    param()

    try {
        Invoke-WithErrorHandling -Component "TuiEngine.MainLoop" -Context @{} -ScriptBlock {
            # Initialize if not already done
            if (-not $global:TuiState.BufferWidth -or $global:TuiState.BufferWidth -eq 0) {
                Initialize-TuiEngine
            }

            # Validate we have a screen to display
            if (-not $global:TuiState.CurrentScreen -and $global:TuiState.ScreenStack.Count -eq 0) {
                throw "No screen available to display. Use Navigation.GoTo() before starting the loop."
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

                } catch [Helios.HeliosException] {
                    # Handle recoverable errors
                    $exception = $_.Exception
                    Write-Log -Level Error -Message "TUI Exception occurred: $($exception.Message)" -Data $exception.DetailedContext
                    
                    if (Get-Command -Name "Show-AlertDialog" -ErrorAction SilentlyContinue) {
                        Show-AlertDialog -Title "Application Error" -Message "An operation failed: $($exception.Message)"
                    }
                    
                    $global:TuiState.IsDirty = $true

                } catch {
                    # Handle fatal errors (standard PowerShell errors not wrapped by Invoke-WithErrorHandling)
                    Write-Log -Level Error -Message "Fatal TUI error: $($_.Exception.Message)" -Data $_
                    
                    if (Get-Command -Name "Show-AlertDialog" -ErrorAction SilentlyContinue) {
                        Show-AlertDialog -Title "Fatal Error" -Message "A critical error occurred. The application will now close."
                    }
                    
                    $global:TuiState.Running = $false
                }
            }
        }
    }
    catch {
        # Catch fatal errors from Invoke-WithErrorHandling itself during loop setup
        Write-Log -Level Error -Message "Main loop fatal error" -Data $_.Exception
        throw
    }
    finally {
        Cleanup-TuiEngine
    }
}

function Process-TuiInput {
    if (-not $global:TuiState.InputQueue) { return $false }

    $processedAny = $false
    
    Invoke-WithErrorHandling -Component "TuiEngine.ProcessInput" -Context @{ Operation = "ProcessInputQueue" } -ScriptBlock {
        Write-Log -Level Verbose -Message "Processing input queue"

        if ($global:TuiState.InputQueue -is [System.Collections.Concurrent.ConcurrentQueue[System.ConsoleKeyInfo]]) {
            $keyInfo = [System.ConsoleKeyInfo]::new([char]0, [System.ConsoleKey]::None, $false, $false, $false)
            while ($global:TuiState.InputQueue.TryDequeue([ref]$keyInfo)) {
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
    }

    return $processedAny
}

function Process-SingleKeyInput {
    param($keyInfo)

    Invoke-WithErrorHandling -Component "TuiEngine.ProcessSingleKey" -Context @{ Key = $keyInfo.Key; Operation = "ProcessSingleKeyInput" } -ScriptBlock {
        Write-Log -Level Debug -Message "Processing key input: Key=$($keyInfo.Key), Char=$($keyInfo.KeyChar), Modifiers=$($keyInfo.Modifiers)"
        
        # Handle Tab navigation
        if ($keyInfo.Key -eq [ConsoleKey]::Tab) {
            if (Get-Command Move-Focus -ErrorAction SilentlyContinue) {
                $moveFocusParams = @{}
                if ($keyInfo.Modifiers -band [ConsoleModifiers]::Shift) {
                    $moveFocusParams.Reverse = $true
                }
                Move-Focus @moveFocusParams
            }
            return
        }

        # Let dialog system handle input first
        if ((Get-Command -Name "Handle-DialogInput" -ErrorAction SilentlyContinue) -and 
            (Handle-DialogInput -Key $keyInfo)) {
            return
        }

        # Focused component gets next chance
        $focusedComponent = if (Get-Command Get-FocusedComponent -ErrorAction SilentlyContinue) { Get-FocusedComponent } else { $null }
        if ($focusedComponent -and ($focusedComponent.PSObject.ScriptMethods.Name -contains 'HandleInput')) {
            Write-Log -Level Debug -Message "Passing input to focused component: $($focusedComponent.Name)"
            if ($focusedComponent.HandleInput($keyInfo)) {
                Write-Log -Level Debug -Message "Input handled by focused component"
                return
            }
        }

        # Finally, the screen handles input
        if ($global:TuiState.CurrentScreen -and ($global:TuiState.CurrentScreen.PSObject.ScriptMethods.Name -contains 'HandleInput')) {
            Write-Log -Level Debug -Message "Passing input to current screen: $($global:TuiState.CurrentScreen.Name)"
            $result = $global:TuiState.CurrentScreen.HandleInput($keyInfo)
            Write-Log -Level Debug -Message "Screen input result: $result"
            switch ($result) {
                "Back" { if(Get-Command Pop-Screen -ErrorAction SilentlyContinue) { Pop-Screen } }
                "Quit" { 
                    $global:TuiState.Running = $false
                    if ($global:TuiState.CancellationTokenSource) {
                        $global:TuiState.CancellationTokenSource.Cancel()
                    }
                }
            }
        }
    }
}

#endregion

#region Frame Rendering - FIXED RECURSIVE IMPLEMENTATION

function Render-Frame {
    Invoke-WithErrorHandling -Component "TuiEngine.RenderFrame" -Context @{ Operation = "RenderFrame" } -ScriptBlock {
        Write-Log -Level Verbose -Message "Starting recursive frame render"

        $bgColor = if (Get-Command -Name "Get-ThemeColor" -ErrorAction SilentlyContinue) {
            Get-ThemeColor "Background" -Default ([ConsoleColor]::Black)
        } else {
            [ConsoleColor]::Black
        }

        Clear-BackBuffer -BackgroundColor $bgColor

        # FIX: Use a simple array instead of generic list to avoid type issues
        $renderQueue = @()

        # FIX: Define the recursive function with proper scoping
        function CollectComponentsRecursive {
            param($component, [ref]$queue)
            
            if (-not $component) { 
                Write-Log -Level Debug -Message "CollectComponentsRecursive: null component"
                return 
            }
            
            # Check visibility
            $isVisible = $true
            if ($component.PSObject.Properties['Visible']) {
                $isVisible = $component.Visible
            }
            
            if (-not $isVisible) { 
                Write-Log -Level Debug -Message "Component $($component.Name ?? $component.Type) is not visible, skipping"
                return 
            }
            
            Write-Log -Level Debug -Message "Collecting component: $($component.Name ?? $component.Type) at X=$($component.X), Y=$($component.Y)"
            
            # Add to render queue
            $queue.Value += $component

            # Call CalculateLayout if available
            if (($component.PSObject.ScriptMethods.Name -contains 'CalculateLayout')) {
                try {
                    Write-Log -Level Debug -Message "Calculating layout for: $($component.Name ?? $component.Type)"
                    $component.CalculateLayout()
                } catch {
                    Write-Log -Level Error -Message "Layout calculation failed for '$($component.Name)'" -Data $_
                }
            }

            # Process children
            if (($component.PSObject.Properties.Name -contains 'Children') -and $component.Children) {
                Write-Log -Level Debug -Message "Processing $($component.Children.Count) children of $($component.Name ?? $component.Type)"
                foreach ($child in $component.Children) {
                    CollectComponentsRecursive -component $child -queue $queue
                }
            }
        }

        # Collect components from current screen
        if ($global:TuiState.CurrentScreen) {
            Write-Log -Level Debug -Message "Current screen: $($global:TuiState.CurrentScreen.Name)"
            
            # Check if screen has RootPanel
            if ($global:TuiState.CurrentScreen.PSObject.Properties['RootPanel'] -and $global:TuiState.CurrentScreen.RootPanel) {
                Write-Log -Level Debug -Message "Found RootPanel on current screen"
                $queueRef = [ref]$renderQueue
                CollectComponentsRecursive -component $global:TuiState.CurrentScreen.RootPanel -queue $queueRef
                $renderQueue = $queueRef.Value
            } else {
                Write-Log -Level Warning -Message "Current screen has no RootPanel property!"
                # Try to render the screen itself if it has a Render method
                if ($global:TuiState.CurrentScreen.PSObject.ScriptMethods.Name -contains 'Render') {
                    $renderQueue += $global:TuiState.CurrentScreen
                }
            }
        } else {
            Write-Log -Level Warning -Message "No current screen set!"
        }

        # Collect dialogs
        if (Get-Command -Name "Get-ActiveDialog" -ErrorAction SilentlyContinue) {
            $currentDialog = Get-ActiveDialog
            if ($currentDialog) {
                Write-Log -Level Debug -Message "Found active dialog"
                $queueRef = [ref]$renderQueue
                CollectComponentsRecursive -component $currentDialog -queue $queueRef
                $renderQueue = $queueRef.Value
            }
        }

        Write-Log -Level Debug -Message "Collected $($renderQueue.Count) components for rendering"

        # Sort by ZIndex and render
        $sortedComponents = $renderQueue | Sort-Object -Property @{
            Expression = { if ($null -ne $_.ZIndex) { $_.ZIndex } else { 0 } }
        }

        foreach ($component in $sortedComponents) {
            if (($component.PSObject.ScriptMethods.Name -contains 'Render')) {
                Write-Log -Level Debug -Message "Rendering component: $($component.Name ?? $component.Type)"
                Invoke-WithErrorHandling -Component "$($component.Name ?? $component.Type).Render" -Context @{ 
                    ComponentType = $component.Type;
                    ComponentName = $component.Name
                } -ScriptBlock {
                    $component.Render()
                }
            } else {
                Write-Log -Level Debug -Message "Component has no Render method: $($component.Name ?? $component.Type)"
            }
        }

        # FIX: Force at least one render for debugging
        if ($renderQueue.Count -eq 0) {
            Write-Log -Level Warning -Message "No components were collected for rendering!"
            # Draw a test pattern to verify rendering works
            Write-BufferString -X 5 -Y 5 -Text "NO COMPONENTS FOUND - CHECK SCREEN SETUP" -ForegroundColor ([ConsoleColor]::Red)
        }

        Render-BufferOptimized
        [Console]::SetCursorPosition($global:TuiState.BufferWidth - 1, $global:TuiState.BufferHeight - 1)
    }
}

function Render-BufferOptimized {
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $outputBuilder = New-Object System.Text.StringBuilder -ArgumentList 20000
    $lastFG = -1
    $lastBG = -1
    
    $forceFullRender = $global:TuiState.RenderStats.FrameCount -eq 0
    
    Invoke-WithErrorHandling -Component "TuiEngine.RenderBuffer" -Context @{ Operation = "RenderBufferOptimized" } -ScriptBlock {
        Write-Log -Level Debug -Message "Starting buffer render (Frame: $($global:TuiState.RenderStats.FrameCount))"
        
        for ($y = 0; $y -lt $global:TuiState.BufferHeight; $y++) {
            $lineChanged = $false
            $lineBuilder = New-Object System.Text.StringBuilder
            
            for ($x = 0; $x -lt $global:TuiState.BufferWidth; $x++) {
                $backCell = $global:TuiState.BackBuffer[$y, $x]
                $frontCell = $global:TuiState.FrontBuffer[$y, $x]
                
                if ($forceFullRender -or
                    $backCell.Char -ne $frontCell.Char -or 
                    $backCell.FG -ne $frontCell.FG -or 
                    $backCell.BG -ne $frontCell.BG) {
                    
                    if (-not $lineChanged) {
                        $lineBuilder.Append("$([char]27)[$($y + 1);1H") | Out-Null
                        $lineChanged = $true
                    }
                    
                    if ($backCell.FG -ne $lastFG -or $backCell.BG -ne $lastBG) {
                        $fgCode = Get-AnsiColorCode $backCell.FG
                        $bgCode = Get-AnsiColorCode $backCell.BG -IsBackground $true
                        $lineBuilder.Append("$([char]27)[${fgCode};${bgCode}m") | Out-Null
                        $lastFG = $backCell.FG
                        $lastBG = $backCell.BG
                    }
                    
                    $lineBuilder.Append($backCell.Char) | Out-Null
                    
                    $global:TuiState.FrontBuffer[$y, $x] = $backCell.Clone()
                } else {
                    if ($lineChanged) {
                        $outputBuilder.Append($lineBuilder.ToString()) | Out-Null
                        $lineBuilder.Clear()
                        $lineChanged = $false
                    }
                    $lastFG = -1
                    $lastBG = -1
                }
            }
            if ($lineChanged) {
                $outputBuilder.Append($lineBuilder.ToString()) | Out-Null
            }
        }
        
        $outputBuilder.Append("$([char]27)[0m") | Out-Null
        
        if ($outputBuilder.Length -gt 4) { # more than just reset code
            Write-Log -Level Debug -Message "Writing $($outputBuilder.Length) characters to console"
            [Console]::Write($outputBuilder.ToString())
        } else {
            Write-Log -Level Debug -Message "No changes to render"
        }
    }
    
    $stopwatch.Stop()
    $global:TuiState.RenderStats.LastFrameTime = $stopwatch.ElapsedMilliseconds
    $global:TuiState.RenderStats.FrameCount++
    $global:TuiState.RenderStats.TotalTime += $stopwatch.ElapsedMilliseconds
}

#endregion

#region Screen Management

function Push-Screen {
    param(
        [PSCustomObject]$Screen,
        [PSCustomObject]$Services
    )
    
    if (-not $Screen) { return }
    
    Invoke-WithErrorHandling -Component "TuiEngine.PushScreen" -Context @{ ScreenName = $Screen.Name } -ScriptBlock {
        Write-Log -Level Debug -Message "Pushing screen: $($Screen.Name)"
        
        $focusedComponent = if (Get-Command Get-FocusedComponent -ErrorAction SilentlyContinue) { Get-FocusedComponent } else { $null }
        if ($focusedComponent -and ($focusedComponent.PSObject.ScriptMethods.Name -contains 'OnBlur')) {
            $focusedComponent.OnBlur()
        }
        
        if ($global:TuiState.CurrentScreen) {
            if ($global:TuiState.CurrentScreen -and ($global:TuiState.CurrentScreen.PSObject.ScriptMethods.Name -contains 'OnExit')) {
                $global:TuiState.CurrentScreen.OnExit()
            }
            $global:TuiState.ScreenStack.Push($global:TuiState.CurrentScreen)
        }
        
        $global:TuiState.CurrentScreen = $Screen
        
        if (($Screen.PSObject.ScriptMethods.Name -contains 'Init') -and -not $Screen._isInitialized) {
            if (-not $Services) { throw "Services object must be provided to initialize a screen."}
            $Screen.Init($Services)
            $Screen._isInitialized = $true
        }
        
        if (($Screen.PSObject.ScriptMethods.Name -contains 'OnEnter')) {
            $Screen.OnEnter()
        }
        
        Request-TuiRefresh
        
        # ENHANCED: Use multiple methods to ensure event data is passed correctly
        try {
            Write-Log -Level Debug -Message "Firing ScreenPushed event for screen: $($Screen.Name)"
            
            # Method 1: Use EventArguments (primary)
            New-Event -SourceIdentifier 'PMC.Navigation.ScreenPushed' -EventArguments @($Screen) -ErrorAction Stop
            
            # Method 2: Also try MessageData as fallback
            New-Event -SourceIdentifier 'PMC.Navigation.ScreenPushed.Fallback' -MessageData $Screen -ErrorAction SilentlyContinue
            
            Write-Log -Level Debug -Message "ScreenPushed event fired successfully"
        } catch {
            Write-Log -Level Error -Message "Failed to fire ScreenPushed event: $_" -Data $_
            # Continue anyway since this shouldn't be fatal
        }
    }
}

function Pop-Screen {
    if ($global:TuiState.ScreenStack.Count -eq 0) { return $false }
    
    Invoke-WithErrorHandling -Component "TuiEngine.PopScreen" -Context @{ Operation = "PopScreen" } -ScriptBlock {
        Write-Log -Level Debug -Message "Popping screen"
        
        $focusedComponent = if (Get-Command Get-FocusedComponent -ErrorAction SilentlyContinue) { Get-FocusedComponent } else { $null }
        if ($focusedComponent -and ($focusedComponent.PSObject.ScriptMethods.Name -contains 'OnBlur')) {
            $focusedComponent.OnBlur()
        }
        
        $screenToExit = $global:TuiState.CurrentScreen
        
        $global:TuiState.CurrentScreen = $global:TuiState.ScreenStack.Pop()
        
        if ($screenToExit -and ($screenToExit.PSObject.ScriptMethods.Name -contains 'OnExit')) {
            $screenToExit.OnExit()
        }
        
        if ($global:TuiState.CurrentScreen -and ($global:TuiState.CurrentScreen.PSObject.ScriptMethods.Name -contains 'OnResume')) {
            $global:TuiState.CurrentScreen.OnResume()
        }
        
        Request-TuiRefresh
        
        # FIX: Use -EventArguments for robust data passing.
        New-Event -SourceIdentifier 'PMC.Navigation.ScreenPopped' -EventArguments @($global:TuiState.CurrentScreen) -ErrorAction SilentlyContinue
        
        return $true
    }
}

#endregion

#region Buffer Operations

function Clear-BackBuffer {
    param([ConsoleColor]$BackgroundColor = [ConsoleColor]::Black)
    
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
        
        $currentX++
    }
}

function Write-BufferChar {
    param(
        [int]$X, 
        [int]$Y, 
        [char]$Char, 
        [ConsoleColor]$ForegroundColor = [ConsoleColor]::White, 
        [ConsoleColor]$BackgroundColor = [ConsoleColor]::Black
    )
    
    if ($Y -lt 0 -or $Y -ge $global:TuiState.BufferHeight) { return }
    if ($X -lt 0 -or $X -ge $global:TuiState.BufferWidth) { return }
    
    $global:TuiState.BackBuffer[$Y, $X] = @{ 
        Char = $Char
        FG = $ForegroundColor
        BG = $BackgroundColor 
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
    
    if ($Width -lt 2 -or $Height -lt 2) { return }
    
    $borders = Get-BorderChars -Style $BorderStyle
    $endX = $X + $Width - 1
    $endY = $Y + $Height - 1

    # Fill background
    for ($row = $Y; $row -le $endY; $row++) {
        for ($col = $X; $col -le $endX; $col++) {
            if ($row -ge 0 -and $row -lt $global:TuiState.BufferHeight -and $col -ge 0 -and $col -lt $global:TuiState.BufferWidth) {
                 if ($row -eq $Y -or $row -eq $endY -or $col -eq $X -or $col -eq $endX) {
                    # This is border, will be drawn later
                 } else {
                    $global:TuiState.BackBuffer[$row, $col] = @{ Char = ' '; FG = [ConsoleColor]::White; BG = $BackgroundColor }
                 }
            }
        }
    }

    # Draw borders
    Write-BufferString -X $X -Y $Y -Text ($borders.TopLeft + ($borders.Horizontal * ($Width - 2)) + $borders.TopRight) -ForegroundColor $BorderColor -BackgroundColor $BackgroundColor
    for ($i = 1; $i -lt ($Height - 1); $i++) {
        Write-BufferString -X $X -Y ($Y + $i) -Text $borders.Vertical -ForegroundColor $BorderColor -BackgroundColor $BackgroundColor
        Write-BufferString -X $endX -Y ($Y + $i) -Text $borders.Vertical -ForegroundColor $BorderColor -BackgroundColor $BackgroundColor
    }
    Write-BufferString -X $X -Y $endY -Text ($borders.BottomLeft + ($borders.Horizontal * ($Width - 2)) + $borders.BottomRight) -ForegroundColor $BorderColor -BackgroundColor $BackgroundColor
    
    # Draw title
    if ($Title) {
        $titleText = " $Title "
        $titleX = $X + [Math]::Floor(($Width - $titleText.Length) / 2)
        Write-BufferString -X $titleX -Y $Y -Text $titleText -ForegroundColor $BorderColor -BackgroundColor $BackgroundColor
    }
}

#endregion

#region Component Focus Management (Delegated to focus-manager)
# The TUI engine no longer directly manages focus, but provides legacy shims for components that might still call them.

function Set-ComponentFocus {
    param([PSCustomObject]$Component)
    if (Get-Command Request-Focus -ErrorAction SilentlyContinue) {
        Request-Focus -Component $Component -Reason "LegacySetComponentFocus"
    }
}

function Handle-TabNavigation {
    param([bool]$Reverse = $false)
    if (Get-Command Move-Focus -ErrorAction SilentlyContinue) {
        Move-Focus -Reverse:$Reverse
    }
}

function Clear-ComponentFocus {
    if (Get-Command Request-Focus -ErrorAction SilentlyContinue) {
        Request-Focus -Component $null -Reason "LegacyClearComponentFocus"
    }
}
#endregion

#region Utility Functions

function Request-TuiRefresh {
    $global:TuiState.IsDirty = $true
}

function Stop-TuiEngine {
    <#
    .SYNOPSIS
        Stops the TUI engine and exits the main loop
    .DESCRIPTION
        Sets the Running flag to false and cancels the input thread,
        causing the main loop to exit gracefully.
    #>
    param()
    
    Invoke-WithErrorHandling -Component "TuiEngine.Stop" -Context @{ Operation = "StopEngine" } -ScriptBlock {
        Write-Log -Level Info -Message "Stopping TUI Engine"
        $global:TuiState.Running = $false
        
        if ($global:TuiState.CancellationTokenSource) {
            try {
                $global:TuiState.CancellationTokenSource.Cancel()
            } catch {
                Write-Log -Level Warning -Message "Error cancelling input thread: $_"
            }
        }
    }
}

function Get-BorderChars {
    param([string]$Style)
    
    $styles = @{
        Single = @{ TopLeft = '┌'; TopRight = '┐'; BottomLeft = '└'; BottomRight = '┘'; Horizontal = '─'; Vertical = '│' }
        Double = @{ TopLeft = '╔'; TopRight = '╗'; BottomLeft = '╚'; BottomRight = '╝'; Horizontal = '═'; Vertical = '║' }
        Rounded = @{ TopLeft = '╭'; TopRight = '╮'; BottomLeft = '╰'; BottomRight = '╯'; Horizontal = '─'; Vertical = '│' }
    }
    
    return $styles[$Style] ?? $styles.Single
}

function Get-AnsiColorCode {
    param([ConsoleColor]$Color, [bool]$IsBackground)
    
    $map = @{
        Black = 30; DarkBlue = 34; DarkGreen = 32; DarkCyan = 36; DarkRed = 31; DarkMagenta = 35; DarkYellow = 33; Gray = 37
        DarkGray = 90; Blue = 94; Green = 92; Cyan = 96; Red = 91; Magenta = 95; Yellow = 93; White = 97
    }
    
    $code = $map[$Color.ToString()]
    if ($IsBackground) {
        return $code + 10
    }
    else {
        return $code
    }
}

function Get-WordWrappedLines {
    param([string]$Text, [int]$MaxWidth)
    
    if ([string]::IsNullOrEmpty($Text) -or $MaxWidth -le 0) { return @() }
    
    $lines = [System.Collections.Generic.List[string]]::new()
    $words = $Text -split '\s+' | Where-Object { $_ }
    $currentLine = ""
    
    foreach ($word in $words) {
        if (($currentLine + $word).Length -le $MaxWidth) {
            $currentLine += "$word "
        } else {
            $lines.Add($currentLine.Trim())
            $currentLine = "$word "
        }
    }
    if ($currentLine) { $lines.Add($currentLine.Trim()) }
    
    return $lines.ToArray()
}

#endregion

#region Cleanup

function Cleanup-TuiEngine {
    Invoke-WithErrorHandling -Component "TuiEngine.Cleanup" -Context @{ Operation = "Cleanup" } -ScriptBlock {
        Write-Log -Level Info -Message "Cleaning up TUI Engine"
        
        if ($global:TuiState.CancellationTokenSource) {
            try { if (-not $global:TuiState.CancellationTokenSource.IsCancellationRequested) { $global:TuiState.CancellationTokenSource.Cancel() } } catch {}
        }

        if ($global:TuiState.InputPowerShell) {
            try { if ($global:TuiState.InputAsyncResult) { $global:TuiState.InputPowerShell.EndInvoke($global:TuiState.InputAsyncResult) } } catch {}
            try { $global:TuiState.InputPowerShell.Dispose() } catch {}
        }
        
        if ($global:TuiState.InputRunspace) {
            try { $global:TuiState.InputRunspace.Dispose() } catch {}
        }
        
        if ($global:TuiState.CancellationTokenSource) {
            try { $global:TuiState.CancellationTokenSource.Dispose() } catch {}
        }

        Cleanup-EventHandlers
        
        try {
            if ([System.Environment]::UserInteractive) {
                [Console]::Write("$([char]27)[0m")
                [Console]::CursorVisible = $true
                [Console]::Clear()
                [Console]::ResetColor()
            }
        } catch {}
    }
}

function Cleanup-EventHandlers {
    if (-not $global:TuiState.EventHandlers) { return }

    foreach ($handlerId in $global:TuiState.EventHandlers.Values) {
        try { Unregister-Event -SubscriptionId $handlerId -ErrorAction SilentlyContinue } catch {}
    }
    $global:TuiState.EventHandlers.Clear()
}

#endregion

Export-ModuleMember -Function @(
    'Initialize-TuiEngine', 'Start-TuiLoop', 'Stop-TuiEngine', 'Request-TuiRefresh', 'Push-Screen', 'Pop-Screen',
    'Write-BufferString', 'Write-BufferChar', 'Write-BufferBox', 'Clear-BackBuffer', 'Set-ComponentFocus',
    'Clear-ComponentFocus', 'Handle-TabNavigation', 'Get-BorderChars', 'Get-AnsiColorCode',
    'Get-WordWrappedLines', 'Render-Frame', 'Cleanup-TuiEngine'
) -Variable 'TuiState'
