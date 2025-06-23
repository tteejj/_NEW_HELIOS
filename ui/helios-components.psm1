# Helios Component Library
# Unified UI component library following PowerShell-first architecture
# All components return PSCustomObject with methods attached via Add-Member

#region Basic Components

function global:New-HeliosLabel {
    param([hashtable]$Props = @{})
    
    # Create PSCustomObject
    $component = [PSCustomObject]@{
        # Metadata
        Type = "Label"
        IsFocusable = $false
        
        # Properties (from Props)
        X = if ($null -ne $Props.X) { $Props.X } else { 0 }
        Y = if ($null -ne $Props.Y) { $Props.Y } else { 0 }
        Width = if ($null -ne $Props.Width) { $Props.Width } else { 10 }
        Height = if ($null -ne $Props.Height) { $Props.Height } else { 1 }
        Visible = if ($null -ne $Props.Visible) { $Props.Visible } else { $true }
        ZIndex = if ($null -ne $Props.ZIndex) { $Props.ZIndex } else { 0 }
        Text = if ($null -ne $Props.Text) { $Props.Text } else { "" }
        ForegroundColor = $Props.ForegroundColor
        Name = $Props.Name
    }
    
    # Add Render method
    $component | Add-Member -MemberType ScriptMethod -Name "Render" -Value {
        param()
        Invoke-WithErrorHandling -Component "$($this.Name).Render" -ScriptBlock {
            if (-not $this.Visible) { return }
            
            $fg = if ($this.ForegroundColor) { $this.ForegroundColor } else { Get-ThemeColor "Primary" -Default ([ConsoleColor]::White) }
            Write-BufferString -X $this.X -Y $this.Y -Text $this.Text -ForegroundColor $fg
        } -Context @{ Component = $this.Name } -ErrorHandler {
            param($Exception)
            Write-Log -Level Error -Message "Label Render error: $($Exception.Message)" -Data $Exception.Context
        }
    }
    
    # Add HandleInput method
    $component | Add-Member -MemberType ScriptMethod -Name "HandleInput" -Value {
        param($Key)
        return $false
    }
    
    return $component
}

function global:New-HeliosButton {
    param([hashtable]$Props = @{})
    
    # Create PSCustomObject
    $component = [PSCustomObject]@{
        # Metadata
        Type = "Button"
        IsFocusable = $true
        
        # Properties (from Props)
        X = if ($null -ne $Props.X) { $Props.X } else { 0 }
        Y = if ($null -ne $Props.Y) { $Props.Y } else { 0 }
        Width = if ($null -ne $Props.Width) { $Props.Width } else { 10 }
        Height = if ($null -ne $Props.Height) { $Props.Height } else { 3 }
        Visible = if ($null -ne $Props.Visible) { $Props.Visible } else { $true }
        ZIndex = if ($null -ne $Props.ZIndex) { $Props.ZIndex } else { 0 }
        Text = if ($null -ne $Props.Text) { $Props.Text } else { "Button" }
        Name = $Props.Name
        
        # Internal State
        IsPressed = $false
        IsFocused = $false
        
        # Event Handlers (from Props)
        OnClick = $Props.OnClick
    }
    
    # Add Render method
    $component | Add-Member -MemberType ScriptMethod -Name "Render" -Value {
        param()
        Invoke-WithErrorHandling -Component "$($this.Name).Render" -ScriptBlock {
            if (-not $this.Visible) { return }
            
            $borderColor = if ($this.IsFocused) { 
                Get-ThemeColor "Accent" -Default ([ConsoleColor]::Cyan)
            } else { 
                Get-ThemeColor "Primary" -Default ([ConsoleColor]::White)
            }
            $bgColor = if ($this.IsPressed) { 
                Get-ThemeColor "Accent" -Default ([ConsoleColor]::Cyan)
            } else { 
                Get-ThemeColor "Background" -Default ([ConsoleColor]::Black)
            }
            $fgColor = if ($this.IsPressed) { 
                Get-ThemeColor "Background" -Default ([ConsoleColor]::Black)
            } else { 
                $borderColor 
            }
            
            Write-BufferBox -X $this.X -Y $this.Y -Width $this.Width -Height $this.Height `
                -BorderColor $borderColor -BackgroundColor $bgColor
                
            $textX = $this.X + [Math]::Floor(($this.Width - $this.Text.Length) / 2)
            Write-BufferString -X $textX -Y ($this.Y + 1) -Text $this.Text `
                -ForegroundColor $fgColor -BackgroundColor $bgColor
        } -Context @{ Component = $this.Name } -ErrorHandler {
            param($Exception)
            Write-Log -Level Error -Message "Button Render error: $($Exception.Message)" -Data $Exception.Context
        }
    }
    
    # Add HandleInput method
    $component | Add-Member -MemberType ScriptMethod -Name "HandleInput" -Value {
        param($Key)
        Invoke-WithErrorHandling -Component "$($this.Name).HandleInput" -ScriptBlock {
            if ($Key.Key -in @([ConsoleKey]::Enter, [ConsoleKey]::Spacebar)) {
                if ($this.OnClick) {
                    Invoke-WithErrorHandling -Component "$($this.Name).OnClick" -ScriptBlock {
                        & $this.OnClick
                    } -Context @{ Component = $this.Name; Key = $Key } -ErrorHandler {
                        param($Exception)
                        Write-Log -Level Error -Message "Button OnClick error: $($Exception.Message)" -Data $Exception.Context
                    }
                }
                Request-TuiRefresh
                return $true
            }
            return $false
        } -Context @{ Component = $this.Name; Key = $Key } -ErrorHandler {
            param($Exception)
            Write-Log -Level Error -Message "Button HandleInput error: $($Exception.Message)" -Data $Exception.Context
            return $false
        }
    }
    
    return $component
}

function global:New-HeliosTextBox {
    param([hashtable]$Props = @{})
    
    # Create PSCustomObject
    $component = [PSCustomObject]@{
        # Metadata
        Type = "TextBox"
        IsFocusable = $true
        
        # Properties (from Props)
        X = if ($null -ne $Props.X) { $Props.X } else { 0 }
        Y = if ($null -ne $Props.Y) { $Props.Y } else { 0 }
        Width = if ($null -ne $Props.Width) { $Props.Width } else { 20 }
        Height = if ($null -ne $Props.Height) { $Props.Height } else { 3 }
        Visible = if ($null -ne $Props.Visible) { $Props.Visible } else { $true }
        ZIndex = if ($null -ne $Props.ZIndex) { $Props.ZIndex } else { 0 }
        Text = if ($null -ne $Props.Text) { $Props.Text } else { "" }
        Placeholder = if ($null -ne $Props.Placeholder) { $Props.Placeholder } else { "" }
        MaxLength = if ($null -ne $Props.MaxLength) { $Props.MaxLength } else { 100 }
        Name = $Props.Name
        
        # Internal State
        CursorPosition = if ($null -ne $Props.CursorPosition) { $Props.CursorPosition } else { 0 }
        IsFocused = $false
        
        # Event Handlers (from Props)
        OnChange = $Props.OnChange
    }
    
    # Add Render method
    $component | Add-Member -MemberType ScriptMethod -Name "Render" -Value {
        param()
        Invoke-WithErrorHandling -Component "$($this.Name).Render" -ScriptBlock {
            if (-not $this.Visible) { return }
            
            $borderColor = if ($this.IsFocused) { 
                Get-ThemeColor "Accent" -Default ([ConsoleColor]::Cyan)
            } else { 
                Get-ThemeColor "Secondary" -Default ([ConsoleColor]::DarkGray)
            }
            Write-BufferBox -X $this.X -Y $this.Y -Width $this.Width -Height 3 -BorderColor $borderColor
            
            $displayText = if ($this.Text) { $this.Text } else { "" }
            if ([string]::IsNullOrEmpty($displayText) -and -not $this.IsFocused) { 
                $displayText = if ($this.Placeholder) { $this.Placeholder } else { "" }
            }
            
            $maxDisplayLength = $this.Width - 4
            if ($displayText.Length -gt $maxDisplayLength) {
                $displayText = $displayText.Substring(0, $maxDisplayLength)
            }
            
            Write-BufferString -X ($this.X + 2) -Y ($this.Y + 1) -Text $displayText
            
            if ($this.IsFocused -and $this.CursorPosition -le $displayText.Length) {
                $cursorX = $this.X + 2 + $this.CursorPosition
                Write-BufferString -X $cursorX -Y ($this.Y + 1) -Text "_" `
                    -BackgroundColor (Get-ThemeColor "Accent" -Default ([ConsoleColor]::Cyan))
            }
        } -Context @{ Component = $this.Name } -ErrorHandler {
            param($Exception)
            Write-Log -Level Error -Message "TextBox Render error: $($Exception.Message)" -Data $Exception.Context
        }
    }
    
    # Add HandleInput method
    $component | Add-Member -MemberType ScriptMethod -Name "HandleInput" -Value {
        param($Key)
        Invoke-WithErrorHandling -Component "$($this.Name).HandleInput" -ScriptBlock {
            $text = if ($this.Text) { $this.Text } else { "" }
            $cursorPos = if ($null -ne $this.CursorPosition) { $this.CursorPosition } else { 0 }
            $oldText = $text
            
            switch ($Key.Key) {
                ([ConsoleKey]::Backspace) { 
                    if ($cursorPos -gt 0) { 
                        $text = $text.Remove($cursorPos - 1, 1)
                        $cursorPos-- 
                    }
                }
                ([ConsoleKey]::Delete) { 
                    if ($cursorPos -lt $text.Length) { 
                        $text = $text.Remove($cursorPos, 1) 
                    }
                }
                ([ConsoleKey]::LeftArrow) { 
                    if ($cursorPos -gt 0) { $cursorPos-- }
                }
                ([ConsoleKey]::RightArrow) { 
                    if ($cursorPos -lt $text.Length) { $cursorPos++ }
                }
                ([ConsoleKey]::Home) { $cursorPos = 0 }
                ([ConsoleKey]::End) { $cursorPos = $text.Length }
                ([ConsoleKey]::V) {
                    # Handle Ctrl+V (paste)
                    if ($Key.Modifiers -band [ConsoleModifiers]::Control) {
                        try {
                            # Get clipboard text (Windows only)
                            $clipboardText = if (Get-Command Get-Clipboard -ErrorAction SilentlyContinue) {
                                Get-Clipboard -Format Text -ErrorAction SilentlyContinue
                            } else {
                                $null
                            }
                            
                            if ($clipboardText) {
                                # Remove newlines for single-line textbox
                                $clipboardText = $clipboardText -replace '[\r\n]+', ' '
                                
                                # Insert as much as will fit
                                $remainingSpace = $this.MaxLength - $text.Length
                                if ($remainingSpace -gt 0) {
                                    $toInsert = if ($clipboardText.Length -gt $remainingSpace) {
                                        $clipboardText.Substring(0, $remainingSpace)
                                    } else {
                                        $clipboardText
                                    }
                                    
                                    $text = $text.Insert($cursorPos, $toInsert)
                                    $cursorPos += $toInsert.Length
                                }
                            }
                        } catch {
                            # Silently ignore clipboard errors
                            Write-Log -Level Warning -Message "TextBox clipboard paste error: $_" -Data @{ Component = $this.Name }
                        }
                    } else {
                        # Regular 'V' key
                        if (-not [char]::IsControl($Key.KeyChar) -and $text.Length -lt $this.MaxLength) {
                            $text = $text.Insert($cursorPos, $Key.KeyChar)
                            $cursorPos++
                        } else {
                            return $false
                        }
                    }
                }
                default {
                    if ($Key.KeyChar -and -not [char]::IsControl($Key.KeyChar) -and $text.Length -lt $this.MaxLength) {
                        $text = $text.Insert($cursorPos, $Key.KeyChar)
                        $cursorPos++
                    } else { 
                        return $false 
                    }
                }
            }
            
            if ($text -ne $oldText -or $cursorPos -ne $this.CursorPosition) {
                $this.Text = $text
                $this.CursorPosition = $cursorPos
                
                if ($this.OnChange) { 
                    Invoke-WithErrorHandling -Component "$($this.Name).OnChange" -ScriptBlock {
                        & $this.OnChange -NewValue $text
                    } -Context @{ Component = $this.Name; NewValue = $text } -ErrorHandler {
                        param($Exception)
                        Write-Log -Level Error -Message "TextBox OnChange error: $($Exception.Message)" -Data $Exception.Context
                    }
                }
                Request-TuiRefresh
            }
            return $true
        } -Context @{ Component = $this.Name; Key = $Key } -ErrorHandler {
            param($Exception)
            Write-Log -Level Error -Message "TextBox HandleInput error: $($Exception.Message)" -Data $Exception.Context
            return $false
        }
    }
    
    return $component
}

function global:New-HeliosCheckBox {
    param([hashtable]$Props = @{})
    
    # Create PSCustomObject
    $component = [PSCustomObject]@{
        # Metadata
        Type = "CheckBox"
        IsFocusable = $true
        
        # Properties (from Props)
        X = if ($null -ne $Props.X) { $Props.X } else { 0 }
        Y = if ($null -ne $Props.Y) { $Props.Y } else { 0 }
        Width = if ($null -ne $Props.Width) { $Props.Width } else { 20 }
        Height = if ($null -ne $Props.Height) { $Props.Height } else { 1 }
        Visible = if ($null -ne $Props.Visible) { $Props.Visible } else { $true }
        ZIndex = if ($null -ne $Props.ZIndex) { $Props.ZIndex } else { 0 }
        Text = if ($null -ne $Props.Text) { $Props.Text } else { "Checkbox" }
        Checked = if ($null -ne $Props.Checked) { $Props.Checked } else { $false }
        Name = $Props.Name
        
        # Internal State
        IsFocused = $false
        
        # Event Handlers (from Props)
        OnChange = $Props.OnChange
    }
    
    # Add Render method
    $component | Add-Member -MemberType ScriptMethod -Name "Render" -Value {
        param()
        Invoke-WithErrorHandling -Component "$($this.Name).Render" -ScriptBlock {
            if (-not $this.Visible) { return }
            
            $fg = if ($this.IsFocused) { 
                Get-ThemeColor "Accent" -Default ([ConsoleColor]::Cyan)
            } else { 
                Get-ThemeColor "Primary" -Default ([ConsoleColor]::White)
            }
            $checkbox = if ($this.Checked) { "[X]" } else { "[ ]" }
            Write-BufferString -X $this.X -Y $this.Y -Text "$checkbox $($this.Text)" -ForegroundColor $fg
        } -Context @{ Component = $this.Name } -ErrorHandler {
            param($Exception)
            Write-Log -Level Error -Message "CheckBox Render error: $($Exception.Message)" -Data $Exception.Context
        }
    }
    
    # Add HandleInput method
    $component | Add-Member -MemberType ScriptMethod -Name "HandleInput" -Value {
        param($Key)
        Invoke-WithErrorHandling -Component "$($this.Name).HandleInput" -ScriptBlock {
            if ($Key.Key -in @([ConsoleKey]::Enter, [ConsoleKey]::Spacebar)) {
                $this.Checked = -not $this.Checked
                
                if ($this.OnChange) { 
                    Invoke-WithErrorHandling -Component "$($this.Name).OnChange" -ScriptBlock {
                        & $this.OnChange -NewValue $this.Checked 
                    } -Context @{ Component = $this.Name; NewValue = $this.Checked } -ErrorHandler {
                        param($Exception)
                        Write-Log -Level Error -Message "CheckBox OnChange error: $($Exception.Message)" -Data $Exception.Context
                    }
                }
                Request-TuiRefresh
                return $true
            }
            return $false
        } -Context @{ Component = $this.Name; Key = $Key } -ErrorHandler {
            param($Exception)
            Write-Log -Level Error -Message "CheckBox HandleInput error: $($Exception.Message)" -Data $Exception.Context
            return $false
        }
    }
    
    return $component
}

function global:New-HeliosProgressBar {
    param([hashtable]$Props = @{})
    
    # Create PSCustomObject
    $component = [PSCustomObject]@{
        # Metadata
        Type = "ProgressBar"
        IsFocusable = $false
        
        # Properties (from Props)
        X = if ($null -ne $Props.X) { $Props.X } else { 0 }
        Y = if ($null -ne $Props.Y) { $Props.Y } else { 0 }
        Width = if ($null -ne $Props.Width) { $Props.Width } else { 20 }
        Height = if ($null -ne $Props.Height) { $Props.Height } else { 1 }
        Visible = if ($null -ne $Props.Visible) { $Props.Visible } else { $true }
        ZIndex = if ($null -ne $Props.ZIndex) { $Props.ZIndex } else { 0 }
        Value = if ($null -ne $Props.Value) { $Props.Value } else { 0 }
        Max = if ($null -ne $Props.Max) { $Props.Max } else { 100 }
        ShowPercent = if ($null -ne $Props.ShowPercent) { $Props.ShowPercent } else { $false }
        Name = $Props.Name
    }
    
    # Add Render method
    $component | Add-Member -MemberType ScriptMethod -Name "Render" -Value {
        param()
        Invoke-WithErrorHandling -Component "$($this.Name).Render" -ScriptBlock {
            if (-not $this.Visible) { return }
            
            $percent = [Math]::Min(100, [Math]::Max(0, ($this.Value / $this.Max) * 100))
            $filled = [Math]::Floor(($this.Width - 2) * ($percent / 100))
            $empty = ($this.Width - 2) - $filled
            
            $bar = "█" * $filled + "░" * $empty
            Write-BufferString -X $this.X -Y $this.Y -Text "[$bar]" -ForegroundColor (Get-ThemeColor "Accent" -Default ([ConsoleColor]::Cyan))
            
            if ($this.ShowPercent) {
                $percentText = "$([Math]::Round($percent))%"
                $textX = $this.X + [Math]::Floor(($this.Width - $percentText.Length) / 2)
                Write-BufferString -X $textX -Y $this.Y -Text $percentText -ForegroundColor (Get-ThemeColor "Primary" -Default ([ConsoleColor]::White))
            }
        } -Context @{ Component = $this.Name } -ErrorHandler {
            param($Exception)
            Write-Log -Level Error -Message "ProgressBar Render error: $($Exception.Message)" -Data $Exception.Context
        }
    }
    
    # Add HandleInput method
    $component | Add-Member -MemberType ScriptMethod -Name "HandleInput" -Value {
        param($Key)
        return $false
    }
    
    return $component
}

function global:New-HeliosTextArea {
    param([hashtable]$Props = @{})
    
    # Create PSCustomObject
    $component = [PSCustomObject]@{
        # Metadata
        Type = "TextArea"
        IsFocusable = $true
        
        # Properties (from Props)
        X = if ($null -ne $Props.X) { $Props.X } else { 0 }
        Y = if ($null -ne $Props.Y) { $Props.Y } else { 0 }
        Width = if ($null -ne $Props.Width) { $Props.Width } else { 40 }
        Height = if ($null -ne $Props.Height) { $Props.Height } else { 6 }
        Visible = if ($null -ne $Props.Visible) { $Props.Visible } else { $true }
        ZIndex = if ($null -ne $Props.ZIndex) { $Props.ZIndex } else { 0 }
        Text = if ($null -ne $Props.Text) { $Props.Text } else { "" }
        Placeholder = if ($null -ne $Props.Placeholder) { $Props.Placeholder } else { "Enter text..." }
        WrapText = if ($null -ne $Props.WrapText) { $Props.WrapText } else { $true }
        Name = $Props.Name
        
        # Internal State
        Lines = @((if ($null -ne $Props.Text) { $Props.Text } else { "" }) -split "`n")
        CursorX = 0
        CursorY = 0
        ScrollOffset = 0
        IsFocused = $false
        
        # Event Handlers (from Props)
        OnChange = $Props.OnChange
    }
    
    # Add Render method
    $component | Add-Member -MemberType ScriptMethod -Name "Render" -Value {
        param()
        Invoke-WithErrorHandling -Component "$($this.Name).Render" -ScriptBlock {
            if (-not $this.Visible) { return }
            
            $borderColor = if ($this.IsFocused) { 
                Get-ThemeColor "Accent" -Default ([ConsoleColor]::Cyan)
            } else { 
                Get-ThemeColor "Secondary" -Default ([ConsoleColor]::DarkGray)
            }
            Write-BufferBox -X $this.X -Y $this.Y -Width $this.Width -Height $this.Height -BorderColor $borderColor
            
            $innerWidth = $this.Width - 4
            $innerHeight = $this.Height - 2
            $displayLines = @()
            if ($this.Lines.Count -eq 0) { $this.Lines = @("") }
            
            foreach ($line in $this.Lines) {
                if ($this.WrapText -and $line.Length -gt $innerWidth) {
                    for ($i = 0; $i -lt $line.Length; $i += $innerWidth) {
                        $displayLines += $line.Substring($i, [Math]::Min($innerWidth, $line.Length - $i))
                    }
                } else { 
                    $displayLines += $line 
                }
            }
            
            if ($displayLines.Count -eq 1 -and $displayLines[0] -eq "" -and -not $this.IsFocused) {
                Write-BufferString -X ($this.X + 2) -Y ($this.Y + 1) -Text $this.Placeholder
                return
            }
            
            $startLine = $this.ScrollOffset
            $endLine = [Math]::Min($displayLines.Count - 1, $startLine + $innerHeight - 1)
            
            for ($i = $startLine; $i -le $endLine; $i++) {
                $y = $this.Y + 1 + ($i - $startLine)
                $line = $displayLines[$i]
                Write-BufferString -X ($this.X + 2) -Y $y -Text $line
            }
            
            if ($this.IsFocused -and $this.CursorY -ge $startLine -and $this.CursorY -le $endLine) {
                $cursorScreenY = $this.Y + 1 + ($this.CursorY - $startLine)
                $cursorX = [Math]::Min($this.CursorX, $displayLines[$this.CursorY].Length)
                Write-BufferString -X ($this.X + 2 + $cursorX) -Y $cursorScreenY -Text "_" `
                    -BackgroundColor (Get-ThemeColor "Accent" -Default ([ConsoleColor]::Cyan))
            }
            
            if ($displayLines.Count -gt $innerHeight) {
                $scrollbarHeight = $innerHeight
                $scrollPosition = [Math]::Floor(($this.ScrollOffset / ($displayLines.Count - $innerHeight)) * ($scrollbarHeight - 1))
                for ($i = 0; $i -lt $scrollbarHeight; $i++) {
                    $char = if ($i -eq $scrollPosition) { "█" } else { "│" }
                    $color = if ($i -eq $scrollPosition) { 
                        Get-ThemeColor "Accent" -Default ([ConsoleColor]::Cyan)
                    } else { 
                        Get-ThemeColor "Subtle" -Default ([ConsoleColor]::DarkGray)
                    }
                    Write-BufferString -X ($this.X + $this.Width - 2) -Y ($this.Y + 1 + $i) -Text $char -ForegroundColor $color
                }
            }
        } -Context @{ Component = $this.Name } -ErrorHandler {
            param($Exception)
            Write-Log -Level Error -Message "TextArea Render error: $($Exception.Message)" -Data $Exception.Context
        }
    }
    
    # Add HandleInput method
    $component | Add-Member -MemberType ScriptMethod -Name "HandleInput" -Value {
        param($Key)
        Invoke-WithErrorHandling -Component "$($this.Name).HandleInput" -ScriptBlock {
            $lines = $this.Lines
            $cursorY = $this.CursorY
            $cursorX = $this.CursorX
            $innerHeight = $this.Height - 2
            
            switch ($Key.Key) {
                ([ConsoleKey]::UpArrow) {
                    if ($cursorY -gt 0) {
                        $cursorY--
                        $cursorX = [Math]::Min($cursorX, $lines[$cursorY].Length)
                        if ($cursorY -lt $this.ScrollOffset) { 
                            $this.ScrollOffset = $cursorY 
                        }
                    }
                }
                ([ConsoleKey]::DownArrow) {
                    if ($cursorY -lt $lines.Count - 1) {
                        $cursorY++
                        $cursorX = [Math]::Min($cursorX, $lines[$cursorY].Length)
                        if ($cursorY -ge $this.ScrollOffset + $innerHeight) { 
                            $this.ScrollOffset = $cursorY - $innerHeight + 1 
                        }
                    }
                }
                ([ConsoleKey]::LeftArrow) {
                    if ($cursorX -gt 0) { 
                        $cursorX-- 
                    } elseif ($cursorY -gt 0) { 
                        $cursorY--
                        $cursorX = $lines[$cursorY].Length 
                    }
                }
                ([ConsoleKey]::RightArrow) {
                    if ($cursorX -lt $lines[$cursorY].Length) { 
                        $cursorX++ 
                    } elseif ($cursorY -lt $lines.Count - 1) { 
                        $cursorY++
                        $cursorX = 0 
                    }
                }
                ([ConsoleKey]::Home) { $cursorX = 0 }
                ([ConsoleKey]::End) { $cursorX = $lines[$cursorY].Length }
                ([ConsoleKey]::Enter) {
                    $currentLine = $lines[$cursorY]
                    $beforeCursor = $currentLine.Substring(0, $cursorX)
                    $afterCursor = $currentLine.Substring($cursorX)
                    $lines[$cursorY] = $beforeCursor
                    $lines = @($lines[0..$cursorY]) + @($afterCursor) + @($lines[($cursorY + 1)..($lines.Count - 1)])
                    $cursorY++
                    $cursorX = 0
                    if ($cursorY -ge $this.ScrollOffset + $innerHeight) { 
                        $this.ScrollOffset = $cursorY - $innerHeight + 1 
                    }
                }
                ([ConsoleKey]::Backspace) {
                    if ($cursorX -gt 0) { 
                        $lines[$cursorY] = $lines[$cursorY].Remove($cursorX - 1, 1)
                        $cursorX-- 
                    } elseif ($cursorY -gt 0) {
                        $prevLineLength = $lines[$cursorY - 1].Length
                        $lines[$cursorY - 1] += $lines[$cursorY]
                        $newLines = @()
                        for ($i = 0; $i -lt $lines.Count; $i++) { 
                            if ($i -ne $cursorY) { $newLines += $lines[$i] } 
                        }
                        $lines = $newLines
                        $cursorY--
                        $cursorX = $prevLineLength
                    }
                }
                ([ConsoleKey]::Delete) {
                    if ($cursorX -lt $lines[$cursorY].Length) { 
                        $lines[$cursorY] = $lines[$cursorY].Remove($cursorX, 1) 
                    } elseif ($cursorY -lt $lines.Count - 1) {
                        $lines[$cursorY] += $lines[$cursorY + 1]
                        $newLines = @()
                        for ($i = 0; $i -lt $lines.Count; $i++) { 
                            if ($i -ne ($cursorY + 1)) { $newLines += $lines[$i] } 
                        }
                        $lines = $newLines
                    }
                }
                ([ConsoleKey]::V) {
                    # Handle Ctrl+V (paste)
                    if ($Key.Modifiers -band [ConsoleModifiers]::Control) {
                        try {
                            # Get clipboard text (Windows only)
                            $clipboardText = if (Get-Command Get-Clipboard -ErrorAction SilentlyContinue) {
                                Get-Clipboard -Format Text -ErrorAction SilentlyContinue
                            } else {
                                $null
                            }
                            
                            if ($clipboardText) {
                                # Split clipboard text into lines
                                $clipboardLines = $clipboardText -split '[\r\n]+'
                                
                                if ($clipboardLines.Count -eq 1) {
                                    # Single line paste - insert at cursor
                                    $lines[$cursorY] = $lines[$cursorY].Insert($cursorX, $clipboardLines[0])
                                    $cursorX += $clipboardLines[0].Length
                                } else {
                                    # Multi-line paste
                                    $currentLine = $lines[$cursorY]
                                    $beforeCursor = $currentLine.Substring(0, $cursorX)
                                    $afterCursor = $currentLine.Substring($cursorX)
                                    
                                    # First line
                                    $lines[$cursorY] = $beforeCursor + $clipboardLines[0]
                                    
                                    # Insert middle lines
                                    $insertLines = @()
                                    for ($i = 1; $i -lt $clipboardLines.Count - 1; $i++) {
                                        $insertLines += $clipboardLines[$i]
                                    }
                                    
                                    # Last line
                                    $lastLine = $clipboardLines[-1] + $afterCursor
                                    $insertLines += $lastLine
                                    
                                    # Insert all new lines
                                    $newLines = @()
                                    for ($i = 0; $i -le $cursorY; $i++) {
                                        $newLines += $lines[$i]
                                    }
                                    $newLines += $insertLines
                                    for ($i = $cursorY + 1; $i -lt $lines.Count; $i++) {
                                        $newLines += $lines[$i]
                                    }
                                    
                                    $lines = $newLines
                                    $cursorY += $clipboardLines.Count - 1
                                    $cursorX = $clipboardLines[-1].Length
                                }
                                
                                # Adjust scroll if needed
                                $innerHeight = $this.Height - 2
                                if ($cursorY -ge $this.ScrollOffset + $innerHeight) { 
                                    $this.ScrollOffset = $cursorY - $innerHeight + 1 
                                }
                            }
                        } catch {
                            # Silently ignore clipboard errors
                            Write-Log -Level Warning -Message "TextArea clipboard paste error: $_" -Data @{ Component = $this.Name }
                        }
                    } else {
                        # Regular 'V' key
                        if (-not [char]::IsControl($Key.KeyChar)) {
                            $lines[$cursorY] = $lines[$cursorY].Insert($cursorX, $Key.KeyChar)
                            $cursorX++
                        } else {
                            return $false
                        }
                    }
                }
                default {
                    if ($Key.KeyChar -and -not [char]::IsControl($Key.KeyChar)) {
                        $lines[$cursorY] = $lines[$cursorY].Insert($cursorX, $Key.KeyChar)
                        $cursorX++
                    } else { 
                        return $false 
                    }
                }
            }
            
            $this.Lines = $lines
            $this.CursorX = $cursorX
            $this.CursorY = $cursorY
            $this.Text = $lines -join "`n"
            
            if ($this.OnChange) { 
                Invoke-WithErrorHandling -Component "$($this.Name).OnChange" -ScriptBlock {
                    & $this.OnChange -NewValue $this.Text 
                } -Context @{ Component = $this.Name; NewValue = $this.Text } -ErrorHandler {
                    param($Exception)
                    Write-Log -Level Error -Message "TextArea OnChange error: $($Exception.Message)" -Data $Exception.Context
                }
            }
            Request-TuiRefresh
            return $true
        } -Context @{ Component = $this.Name; Key = $Key } -ErrorHandler {
            param($Exception)
            Write-Log -Level Error -Message "TextArea HandleInput error: $($Exception.Message)" -Data $Exception.Context
            return $false
        }
    }
    
    return $component
}

#endregion

#region DateTime Components

function global:New-HeliosCalendarPicker {
    param([hashtable]$Props = @{})
    
    # Create PSCustomObject
    $component = [PSCustomObject]@{
        Type = "CalendarPicker"
        X = if ($null -ne $Props.X) { $Props.X } else { 0 }
        Y = if ($null -ne $Props.Y) { $Props.Y } else { 0 }
        Width = if ($null -ne $Props.Width) { $Props.Width } else { 30 }
        Height = if ($null -ne $Props.Height) { $Props.Height } else { 10 }
        Value = if ($null -ne $Props.Value) { $Props.Value } else { (Get-Date) }
        Mode = if ($null -ne $Props.Mode) { $Props.Mode } else { "Date" } # Date, DateTime, Time
        IsFocusable = $true
        IsFocused = $false
        CurrentView = "Day"  # Day, Month, Year
        SelectedDate = if ($null -ne $Props.Value) { $Props.Value } else { (Get-Date) }
        ViewDate = if ($null -ne $Props.Value) { $Props.Value } else { (Get-Date) }
        Name = $Props.Name
        OnChange = $Props.OnChange
        OnSelect = $Props.OnSelect
    }
    
    # Add Render method
    $component | Add-Member -MemberType ScriptMethod -Name "Render" -Value {
        param()
        Invoke-WithErrorHandling -Component "$($this.Name).Render" -ScriptBlock {
            $borderColor = if ($this.IsFocused) { 
                Get-ThemeColor "Accent" -Default ([ConsoleColor]::Cyan)
            } else { 
                Get-ThemeColor "Border" -Default ([ConsoleColor]::DarkGray)
            }
            
            # Main container
            Write-BufferBox -X $this.X -Y $this.Y -Width $this.Width -Height $this.Height `
                -BorderColor $borderColor -Title " Calendar "
            
            # Header with navigation
            $headerY = $this.Y + 1
            $monthYear = $this.ViewDate.ToString("MMMM yyyy")
            $headerX = $this.X + [Math]::Floor(($this.Width - $monthYear.Length) / 2)
            
            Write-BufferString -X ($this.X + 2) -Y $headerY -Text "◄" -ForegroundColor $borderColor
            Write-BufferString -X $headerX -Y $headerY -Text $monthYear -ForegroundColor (Get-ThemeColor "Header" -Default ([ConsoleColor]::Cyan))
            Write-BufferString -X ($this.X + $this.Width - 3) -Y $headerY -Text "►" -ForegroundColor $borderColor
            
            # Day headers
            $dayHeaderY = $headerY + 2
            $days = @("Su", "Mo", "Tu", "We", "Th", "Fr", "Sa")
            $dayWidth = 4
            $startX = $this.X + 2
            
            for ($i = 0; $i -lt $days.Count; $i++) {
                Write-BufferString -X ($startX + ($i * $dayWidth)) -Y $dayHeaderY `
                    -Text $days[$i] -ForegroundColor (Get-ThemeColor "Subtle" -Default ([ConsoleColor]::DarkGray))
            }
            
            # Calendar grid
            $firstDay = Get-Date -Year $this.ViewDate.Year -Month $this.ViewDate.Month -Day 1
            $startDayOfWeek = [int]$firstDay.DayOfWeek
            $daysInMonth = [DateTime]::DaysInMonth($this.ViewDate.Year, $this.ViewDate.Month)
            
            $currentDay = 1
            $calendarY = $dayHeaderY + 1
            
            for ($week = 0; $week -lt 6; $week++) {
                if ($currentDay -gt $daysInMonth) { break }
                
                for ($dayOfWeek = 0; $dayOfWeek -lt 7; $dayOfWeek++) {
                    $x = $startX + ($dayOfWeek * $dayWidth)
                    
                    if ($week -eq 0 -and $dayOfWeek -lt $startDayOfWeek) {
                        continue
                    }
                    
                    if ($currentDay -le $daysInMonth) {
                        $isSelected = ($currentDay -eq $this.SelectedDate.Day -and 
                                     $this.ViewDate.Month -eq $this.SelectedDate.Month -and 
                                     $this.ViewDate.Year -eq $this.SelectedDate.Year)
                        
                        $isToday = ($currentDay -eq (Get-Date).Day -and 
                                  $this.ViewDate.Month -eq (Get-Date).Month -and 
                                  $this.ViewDate.Year -eq (Get-Date).Year)
                        
                        $fg = if ($isSelected) { 
                            Get-ThemeColor "Background" -Default ([ConsoleColor]::Black)
                        } elseif ($isToday) { 
                            Get-ThemeColor "Accent" -Default ([ConsoleColor]::Cyan)
                        } else { 
                            Get-ThemeColor "Primary" -Default ([ConsoleColor]::White)
                        }
                        
                        $bg = if ($isSelected) { 
                            Get-ThemeColor "Accent" -Default ([ConsoleColor]::Cyan)
                        } else { 
                            Get-ThemeColor "Background" -Default ([ConsoleColor]::Black)
                        }
                        
                        $dayText = $currentDay.ToString().PadLeft(2)
                        Write-BufferString -X $x -Y ($calendarY + $week) -Text $dayText `
                            -ForegroundColor $fg -BackgroundColor $bg
                        
                        $currentDay++
                    }
                }
            }
            
            # Time picker if in DateTime mode
            if ($this.Mode -eq "DateTime") {
                $timeY = $this.Y + $this.Height - 2
                $timeStr = $this.SelectedDate.ToString("HH:mm")
                Write-BufferString -X ($this.X + 2) -Y $timeY -Text "Time: $timeStr" `
                    -ForegroundColor (Get-ThemeColor "Primary" -Default ([ConsoleColor]::White))
            }
        } -Context @{ Component = $this.Name } -ErrorHandler {
            param($Exception)
            Write-Log -Level Error -Message "CalendarPicker Render error: $($Exception.Message)" -Data $Exception.Context
        }
    }
    
    # Add HandleInput method
    $component | Add-Member -MemberType ScriptMethod -Name "HandleInput" -Value {
        param($Key)
        Invoke-WithErrorHandling -Component "$($this.Name).HandleInput" -ScriptBlock {
            $handled = $true
            $date = $this.SelectedDate
            $viewDate = $this.ViewDate
            
            switch ($Key.Key) {
                ([ConsoleKey]::LeftArrow) {
                    if ($Key.Modifiers -band [ConsoleModifiers]::Control) {
                        # Previous month
                        $this.ViewDate = $viewDate.AddMonths(-1)
                    } else {
                        # Previous day
                        $date = $date.AddDays(-1)
                        if ($date.Month -ne $viewDate.Month) {
                            $this.ViewDate = $date
                        }
                    }
                }
                ([ConsoleKey]::RightArrow) {
                    if ($Key.Modifiers -band [ConsoleModifiers]::Control) {
                        # Next month
                        $this.ViewDate = $viewDate.AddMonths(1)
                    } else {
                        # Next day
                        $date = $date.AddDays(1)
                        if ($date.Month -ne $viewDate.Month) {
                            $this.ViewDate = $date
                        }
                    }
                }
                ([ConsoleKey]::UpArrow) {
                    $date = $date.AddDays(-7)
                    if ($date.Month -ne $viewDate.Month) {
                        $this.ViewDate = $date
                    }
                }
                ([ConsoleKey]::DownArrow) {
                    $date = $date.AddDays(7)
                    if ($date.Month -ne $viewDate.Month) {
                        $this.ViewDate = $date
                    }
                }
                ([ConsoleKey]::PageUp) {
                    $this.ViewDate = $viewDate.AddMonths(-1)
                    $date = Get-Date -Year $this.ViewDate.Year -Month $this.ViewDate.Month `
                        -Day ([Math]::Min($date.Day, [DateTime]::DaysInMonth($this.ViewDate.Year, $this.ViewDate.Month)))
                }
                ([ConsoleKey]::PageDown) {
                    $this.ViewDate = $viewDate.AddMonths(1)
                    $date = Get-Date -Year $this.ViewDate.Year -Month $this.ViewDate.Month `
                        -Day ([Math]::Min($date.Day, [DateTime]::DaysInMonth($this.ViewDate.Year, $this.ViewDate.Month)))
                }
                ([ConsoleKey]::Home) {
                    $date = Get-Date
                    $this.ViewDate = $date
                }
                ([ConsoleKey]::Enter) {
                    if ($this.OnSelect) {
                        Invoke-WithErrorHandling -Component "$($this.Name).OnSelect" -ScriptBlock {
                            & $this.OnSelect -Date $date
                        } -Context @{ Component = $this.Name; SelectedDate = $date } -ErrorHandler {
                            param($Exception)
                            Write-Log -Level Error -Message "CalendarPicker OnSelect error: $($Exception.Message)" -Data $Exception.Context
                        }
                    }
                }
                default {
                    $handled = $false
                }
            }
            
            if ($handled) {
                $this.SelectedDate = $date
                if ($this.OnChange) {
                    Invoke-WithErrorHandling -Component "$($this.Name).OnChange" -ScriptBlock {
                        & $this.OnChange -NewValue $date
                    } -Context @{ Component = $this.Name; NewValue = $date } -ErrorHandler {
                        param($Exception)
                        Write-Log -Level Error -Message "CalendarPicker OnChange error: $($Exception.Message)" -Data $Exception.Context
                    }
                }
                Request-TuiRefresh
            }
            
            return $handled
        } -Context @{ Component = $this.Name; Key = $Key } -ErrorHandler {
            param($Exception)
            Write-Log -Level Error -Message "CalendarPicker HandleInput error: $($Exception.Message)" -Data $Exception.Context
            return $false
        }
    }
    
    return $component
}

function global:New-HeliosTimePicker {
    param([hashtable]$Props = @{})
    
    # Create PSCustomObject
    $component = [PSCustomObject]@{
        # Metadata
        Type = "TimePicker"
        IsFocusable = $true
        IsFocused = $false
        
        # Properties (from Props)
        X = if ($null -ne $Props.X) { $Props.X } else { 0 }
        Y = if ($null -ne $Props.Y) { $Props.Y } else { 0 }
        Width = if ($null -ne $Props.Width) { $Props.Width } else { 15 }
        Height = if ($null -ne $Props.Height) { $Props.Height } else { 3 }
        Visible = if ($null -ne $Props.Visible) { $Props.Visible } else { $true }
        ZIndex = if ($null -ne $Props.ZIndex) { $Props.ZIndex } else { 0 }
        Hour = if ($null -ne $Props.Hour) { $Props.Hour } else { 0 }
        Minute = if ($null -ne $Props.Minute) { $Props.Minute } else { 0 }
        Format24H = if ($null -ne $Props.Format24H) { $Props.Format24H } else { $true }
        Name = $Props.Name
        
        # Event Handlers (from Props)
        OnChange = $Props.OnChange
    }
    
    # Add Render method
    $component | Add-Member -MemberType ScriptMethod -Name "Render" -Value {
        param()
        Invoke-WithErrorHandling -Component "$($this.Name).Render" -ScriptBlock {
            if (-not $this.Visible) { return }
            
            $borderColor = if ($this.IsFocused) { 
                Get-ThemeColor "Accent" -Default ([ConsoleColor]::Cyan)
            } else { 
                Get-ThemeColor "Secondary" -Default ([ConsoleColor]::DarkGray)
            }
            Write-BufferBox -X $this.X -Y $this.Y -Width $this.Width -Height 3 -BorderColor $borderColor
            
            if ($this.Format24H) { 
                $timeStr = "{0:D2}:{1:D2}" -f $this.Hour, $this.Minute 
            } else {
                $displayHour = if ($this.Hour -eq 0) { 12 } elseif ($this.Hour -gt 12) { $this.Hour - 12 } else { $this.Hour }
                $ampm = if ($this.Hour -lt 12) { "AM" } else { "PM" }
                $timeStr = "{0:D2}:{1:D2} {2}" -f $displayHour, $this.Minute, $ampm
            }
            
            # Truncate time string if too long
            $maxLength = $this.Width - 6
            if ($timeStr.Length -gt $maxLength) {
                $timeStr = $timeStr.Substring(0, $maxLength)
            }
            
            Write-BufferString -X ($this.X + 2) -Y ($this.Y + 1) -Text $timeStr
            if ($this.IsFocused -and $this.Width -ge 6) { 
                Write-BufferString -X ($this.X + $this.Width - 4) -Y ($this.Y + 1) -Text "⏰" -ForegroundColor $borderColor 
            }
        } -Context @{ Component = $this.Name } -ErrorHandler {
            param($Exception)
            Write-Log -Level Error -Message "TimePicker Render error: $($Exception.Message)" -Data $Exception.Context
        }
    }
    
    # Add HandleInput method
    $component | Add-Member -MemberType ScriptMethod -Name "HandleInput" -Value {
        param($Key)
        Invoke-WithErrorHandling -Component "$($this.Name).HandleInput" -ScriptBlock {
            $handled = $true
            $hour = $this.Hour
            $minute = $this.Minute
            
            switch ($Key.Key) {
                ([ConsoleKey]::UpArrow) { 
                    $minute = ($minute + 15) % 60
                    if ($minute -eq 0) { $hour = ($hour + 1) % 24 } 
                }
                ([ConsoleKey]::DownArrow) { 
                    $minute = ($minute - 15 + 60) % 60
                    if ($minute -eq 45) { $hour = ($hour - 1 + 24) % 24 } 
                }
                ([ConsoleKey]::LeftArrow)  { $hour = ($hour - 1 + 24) % 24 }
                ([ConsoleKey]::RightArrow) { $hour = ($hour + 1) % 24 }
                default { $handled = $false }
            }
            
            if ($handled) {
                $this.Hour = $hour
                $this.Minute = $minute
                
                if ($this.OnChange) { 
                    Invoke-WithErrorHandling -Component "$($this.Name).OnChange" -ScriptBlock {
                        & $this.OnChange -NewHour $hour -NewMinute $minute 
                    } -Context @{ Component = $this.Name; NewHour = $hour; NewMinute = $minute } -ErrorHandler {
                        param($Exception)
                        Write-Log -Level Error -Message "TimePicker OnChange error: $($Exception.Message)" -Data $Exception.Context
                    }
                }
                Request-TuiRefresh
            }
            return $handled
        } -Context @{ Component = $this.Name; Key = $Key } -ErrorHandler {
            param($Exception)
            Write-Log -Level Error -Message "TimePicker HandleInput error: $($Exception.Message)" -Data $Exception.Context
            return $false
        }
    }
    
    return $component
}

#endregion
