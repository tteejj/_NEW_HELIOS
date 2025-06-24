# Helios Component Library
# Unified UI component library following PowerShell-first architecture
# All components return PSCustomObject with methods attached via Add-Member

#region Basic Components
function New-HeliosLabel {
param([hashtable]$Props = @{})
# Create PSCustomObject
$component = [PSCustomObject]@{
    # Metadata
    Type = "Label"
    IsFocusable = $false
    Parent = $null
    LayoutProps = @{}
    
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

# Add methods using Add-Member for explicit ScriptMethod type
$component | Add-Member -MemberType ScriptMethod -Name "Render" -Value {
    param()
    Invoke-WithErrorHandling -Component "$($this.Name).Render" -ScriptBlock {
        if (-not $this.Visible) { return }
        
        $fg = if ($this.ForegroundColor) { $this.ForegroundColor } else { Get-ThemeColor "Primary" -Default ([ConsoleColor]::White) }
        Write-BufferString -X $this.X -Y $this.Y -Text $this.Text -ForegroundColor $fg
    } -Context @{ Component = $this.Name }
}

$component | Add-Member -MemberType ScriptMethod -Name "HandleInput" -Value {
    param($Key)
    return $false
}

return $component
}
function New-HeliosButton {
param([hashtable]$Props = @{})
# Create PSCustomObject
$component = [PSCustomObject]@{
    # Metadata
    Type = "Button"
    IsFocusable = if ($null -ne $Props.IsFocusable) { $Props.IsFocusable } else { $true }
    Parent = $null
    LayoutProps = @{}
    
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

# Add methods using Add-Member for explicit ScriptMethod type
$component | Add-Member -MemberType ScriptMethod -Name "Render" -Value {
    param()
    Invoke-WithErrorHandling -Component "$($this.Name).Render" -ScriptBlock {
        if (-not $this.Visible) { return }
        
        # Determine colors based on button state
        if (-not $this.IsFocusable) {
            # Disabled button appearance
            $borderColor = Get-ThemeColor "Subtle" -Default ([ConsoleColor]::DarkGray)
            $bgColor = Get-ThemeColor "Background" -Default ([ConsoleColor]::Black)
            $fgColor = Get-ThemeColor "Subtle" -Default ([ConsoleColor]::DarkGray)
        } elseif ($this.IsPressed) {
            $borderColor = Get-ThemeColor "Accent" -Default ([ConsoleColor]::Cyan)
            $bgColor = Get-ThemeColor "Accent" -Default ([ConsoleColor]::Cyan)
            $fgColor = Get-ThemeColor "Background" -Default ([ConsoleColor]::Black)
        } elseif ($this.IsFocused) {
            $borderColor = Get-ThemeColor "Accent" -Default ([ConsoleColor]::Cyan)
            $bgColor = Get-ThemeColor "Background" -Default ([ConsoleColor]::Black)
            $fgColor = Get-ThemeColor "Accent" -Default ([ConsoleColor]::Cyan)
        } else {
            $borderColor = Get-ThemeColor "Primary" -Default ([ConsoleColor]::White)
            $bgColor = Get-ThemeColor "Background" -Default ([ConsoleColor]::Black)
            $fgColor = Get-ThemeColor "Primary" -Default ([ConsoleColor]::White)
        }
        
        Write-BufferBox -X $this.X -Y $this.Y -Width $this.Width -Height $this.Height `
            -BorderColor $borderColor -BackgroundColor $bgColor
            
        $textX = $this.X + [Math]::Floor(($this.Width - $this.Text.Length) / 2)
        Write-BufferString -X $textX -Y ($this.Y + 1) -Text $this.Text `
            -ForegroundColor $fgColor -BackgroundColor $bgColor
    } -Context @{ Component = $this.Name }
}

$component | Add-Member -MemberType ScriptMethod -Name "HandleInput" -Value {
    param($Key)
    Invoke-WithErrorHandling -Component "$($this.Name).HandleInput" -ScriptBlock {
        # Ignore input if button is disabled
        if (-not $this.IsFocusable) {
            return $false
        }
        
        if ($Key.Key -in @([ConsoleKey]::Enter, [ConsoleKey]::Spacebar)) {
            if ($this.OnClick) {
                Invoke-WithErrorHandling -Component "$($this.Name).OnClick" -ScriptBlock {
                    & $this.OnClick
                } -Context @{ Component = $this.Name; Key = $Key }
            }
            Request-TuiRefresh
            return $true
        }
        return $false
    } -Context @{ Component = $this.Name; Key = $Key }
}

return $component
}
function New-HeliosTextBox {
param([hashtable]$Props = @{})
# Create PSCustomObject
$component = [PSCustomObject]@{
    # Metadata
    Type = "TextBox"
    IsFocusable = $true
    Parent = $null
    LayoutProps = @{}
    
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

# Add methods using Add-Member for explicit ScriptMethod type
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
            $displayText = $displayText.Substring(0, [Math]::Max(0, $maxDisplayLength))
        }
        
        Write-BufferString -X ($this.X + 2) -Y ($this.Y + 1) -Text $displayText
        
        if ($this.IsFocused -and $this.CursorPosition -le $displayText.Length) {
            $cursorX = $this.X + 2 + $this.CursorPosition
            Write-BufferString -X $cursorX -Y ($this.Y + 1) -Text "_" `
                -BackgroundColor (Get-ThemeColor "Accent" -Default ([ConsoleColor]::Cyan))
        }
    } -Context @{ Component = $this.Name }
}

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
                if ($Key.Modifiers -band [System.ConsoleModifiers]::Control) {
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
                    if ($Key.KeyChar -and -not [char]::IsControl($Key.KeyChar) -and $text.Length -lt $this.MaxLength) {
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
                } -Context @{ Component = $this.Name; NewValue = $text }
            }
            Request-TuiRefresh
        }
        return $true
    } -Context @{ Component = $this.Name; Key = $Key }
}

return $component
}
function New-HeliosCheckBox {
param([hashtable]$Props = @{})
# Create PSCustomObject
$component = [PSCustomObject]@{
    # Metadata
    Type = "CheckBox"
    IsFocusable = $true
    Parent = $null
    LayoutProps = @{}
    
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

# Add methods using Add-Member for explicit ScriptMethod type
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
    } -Context @{ Component = $this.Name }
}

$component | Add-Member -MemberType ScriptMethod -Name "HandleInput" -Value {
    param($Key)
    Invoke-WithErrorHandling -Component "$($this.Name).HandleInput" -ScriptBlock {
        if ($Key.Key -in @([ConsoleKey]::Enter, [ConsoleKey]::Spacebar)) {
            $this.Checked = -not $this.Checked
            
            if ($this.OnChange) { 
                Invoke-WithErrorHandling -Component "$($this.Name).OnChange" -ScriptBlock {
                    & $this.OnChange -NewValue $this.Checked 
                } -Context @{ Component = $this.Name; NewValue = $this.Checked }
            }
            Request-TuiRefresh
            return $true
        }
        return $false
    } -Context @{ Component = $this.Name; Key = $Key }
}

return $component
}
function New-HeliosProgressBar {
param([hashtable]$Props = @{})
# Create PSCustomObject
$component = [PSCustomObject]@{
    # Metadata
    Type = "ProgressBar"
    IsFocusable = $false
    Parent = $null
    LayoutProps = @{}
    
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

# Add methods using Add-Member for explicit ScriptMethod type
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
    } -Context @{ Component = $this.Name }
}

$component | Add-Member -MemberType ScriptMethod -Name "HandleInput" -Value {
    param($Key)
    return $false
}

return $component
}
function New-HeliosTextArea {
param([hashtable]$Props = @{})
# Create PSCustomObject
$component = [PSCustomObject]@{
    # Metadata
    Type = "TextArea"
    IsFocusable = $true
    Parent = $null
    LayoutProps = @{}
    
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

# Add methods using Add-Member for explicit ScriptMethod type
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
    } -Context @{ Component = $this.Name }
}

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
                if ($Key.Modifiers -band [System.ConsoleModifiers]::Control) {
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
                    if ($Key.KeyChar -and -not [char]::IsControl($Key.KeyChar)) {
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
            } -Context @{ Component = $this.Name; NewValue = $this.Text }
        }
        Request-TuiRefresh
        return $true
    } -Context @{ Component = $this.Name; Key = $Key }
}

return $component
}
#endregion
#region DateTime Components
function New-HeliosCalendarPicker {
param([hashtable]$Props = @{})
# Create PSCustomObject
$component = [PSCustomObject]@{
    Type = "CalendarPicker"
    Parent = $null
    LayoutProps = @{}
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

# Add methods using Add-Member for explicit ScriptMethod type
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
    } -Context @{ Component = $this.Name }
}

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
                    } -Context @{ Component = $this.Name; SelectedDate = $date }
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
                } -Context @{ Component = $this.Name; NewValue = $date }
            }
            Request-TuiRefresh
        }
        
        return $handled
    } -Context @{ Component = $this.Name; Key = $Key }
}

return $component
}
function New-HeliosTimePicker {
param([hashtable]$Props = @{})
# Create PSCustomObject
$component = [PSCustomObject]@{
    # Metadata
    Type = "TimePicker"
    IsFocusable = $true
    IsFocused = $false
    Parent = $null
    LayoutProps = @{}
    
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

# Add methods using Add-Member for explicit ScriptMethod type
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
            $timeStr = $timeStr.Substring(0, [Math]::Max(0, $maxLength)) # Fixed: Ensure substring length is non-negative
        }
        
        Write-BufferString -X ($this.X + 2) -Y ($this.Y + 1) -Text $timeStr
        if ($this.IsFocused -and $this.Width -ge 6) { 
            Write-BufferString -X ($this.X + $this.Width - 4) -Y ($this.Y + 1) -Text "⏰" -ForegroundColor $borderColor 
        }
    } -Context @{ Component = $this.Name }
}

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
                } -Context @{ Component = $this.Name; NewHour = $hour; NewMinute = $minute }
            }
            Request-TuiRefresh
        }
        return $handled
    } -Context @{ Component = $this.Name; Key = $Key }
}

return $component
}
#endregion
#region Data Display Components
function New-HeliosDataTable {
param([hashtable]$Props = @{})
# Create PSCustomObject
$component = [PSCustomObject]@{
    # Metadata
    Type = "DataTable"
    IsFocusable = if ($null -ne $Props.IsFocusable) { $Props.IsFocusable } else { $true }
    Parent = $null
    LayoutProps = @{}
    
    # Properties (from Props)
    X = if ($null -ne $Props.X) { $Props.X } else { 0 }
    Y = if ($null -ne $Props.Y) { $Props.Y } else { 0 }
    Width = if ($null -ne $Props.Width) { $Props.Width } else { 80 }
    Height = if ($null -ne $Props.Height) { $Props.Height } else { 20 }
    Visible = if ($null -ne $Props.Visible) { $Props.Visible } else { $true }
    ZIndex = if ($null -ne $Props.ZIndex) { $Props.ZIndex } else { 0 }
    Name = $Props.Name
    Title = $Props.Title
    
    # Data & Columns
    Data = if ($null -ne $Props.Data) { @($Props.Data) } else { @() }
    Columns = if ($null -ne $Props.Columns) { @($Props.Columns) } else { @() }
    
    # Behavior Options
    ShowBorder = if ($null -ne $Props.ShowBorder) { $Props.ShowBorder } else { $true }
    ShowHeader = if ($null -ne $Props.ShowHeader) { $Props.ShowHeader } else { $true }
    ShowFooter = if ($null -ne $Props.ShowFooter) { $Props.ShowFooter } else { $true }
    ShowRowNumbers = if ($null -ne $Props.ShowRowNumbers) { $Props.ShowRowNumbers } else { $false }
    AllowSort = if ($null -ne $Props.AllowSort) { $Props.AllowSort } else { $true }
    AllowFilter = if ($null -ne $Props.AllowFilter) { $Props.AllowFilter } else { $true }
    AllowSelection = if ($null -ne $Props.AllowSelection) { $Props.AllowSelection } else { $true }
    MultiSelect = if ($null -ne $Props.MultiSelect) { $Props.MultiSelect } else { $false }
    
    # Internal State
    IsFocused = $false
    SelectedRow = 0
    SortColumn = $null
    SortDirection = "Ascending"
    FilterText = ""
    FilterColumn = $null
    FilterMode = $false
    PageSize = 1
    CurrentPage = 0
    SelectedRows = @()
    
    # Derived Data (internal)
    FilteredData = @()
    ProcessedData = @()
    
    # Event Handlers (from Props)
    OnAction = $Props.OnAction
    OnRowSelect = $Props.OnRowSelect
    OnSelectionChange = $Props.OnSelectionChange
}

# Add methods using Add-Member for explicit ScriptMethod type
$component | Add-Member -MemberType ScriptMethod -Name "ProcessData" -Value {
    param()
    Invoke-WithErrorHandling -Component "$($this.Name).ProcessData" -ScriptBlock {
        # Filter data
        if ([string]::IsNullOrWhiteSpace($this.FilterText)) {
            $this.FilteredData = $this.Data
        } else {
            if ($this.FilterColumn) {
                $this.FilteredData = @($this.Data | Where-Object { $_."$($this.FilterColumn)" -like "*$($this.FilterText)*"" })
            } else {
                $this.FilteredData = @($this.Data | Where-Object {
                    $row = $_
                    $matched = $false
                    foreach ($col in $this.Columns) {
                        if ($col.Filterable -ne $false -and $row."$($col.Name)" -like "*$($this.FilterText)*") {
                            $matched = $true; break
                        }
                    }
                    $matched
                })
            }
        }
        
        # Sort data
        if ($this.SortColumn -and $this.AllowSort) {
            $this.ProcessedData = $this.FilteredData | Sort-Object -Property $this.SortColumn -Descending:($this.SortDirection -eq "Descending")
        } else {
            $this.ProcessedData = $this.FilteredData
        }
        
        # Calculate page size
        $headerLines = if ($this.ShowHeader) { 2 } else { 0 }
        $footerLines = if ($this.ShowFooter) { 1 } else { 0 }
        $filterLines = if ($this.AllowFilter) { 1 } else { 0 }
        $borderAdjust = if ($this.ShowBorder) { 2 } else { 0 }
        $availableHeight = $this.Height - $headerLines - $footerLines - $filterLines - $borderAdjust
        $this.PageSize = [Math]::Max(1, $availableHeight)
        
        # Reset selection and page if out of bounds
        if ($this.SelectedRow -ge @($this.ProcessedData).Count) {
            $this.SelectedRow = [Math]::Max(0, @($this.ProcessedData).Count - 1)
        }
        $totalPages = if (@($this.ProcessedData).Count -gt 0) { [Math]::Ceiling(@($this.ProcessedData).Count / $this.PageSize) } else { 1 }
        if ($this.CurrentPage -ge $totalPages) {
            $this.CurrentPage = [Math]::Max(0, $totalPages - 1)
        }
    } -Context @{ Component = $this.Name }
}

$component | Add-Member -MemberType ScriptMethod -Name "UpdateData" -Value {
    param([array]$NewData)
    Invoke-WithErrorHandling -Component "$($this.Name).UpdateData" -ScriptBlock {
        $this.Data = @($NewData)
        $this.ProcessData()
        Request-TuiRefresh
    } -Context @{ Component = $this.Name }
}

$component | Add-Member -MemberType ScriptMethod -Name "Render" -Value {
    param()
    Invoke-WithErrorHandling -Component "$($this.Name).Render" -ScriptBlock {
        if (-not $this.Visible) { return }

        # Initialize layout variables
        $contentX = $this.X
        $contentY = $this.Y
        $contentWidth = $this.Width
        $contentHeight = $this.Height
        
        # Draw border if enabled
        if ($this.ShowBorder) {
            $borderColor = if ($this.IsFocused) { 
                Get-ThemeColor "Accent" -Default ([ConsoleColor]::Cyan)
            } else { 
                Get-ThemeColor "Border" -Default ([ConsoleColor]::DarkGray)
            }
            $titleText = if ($this.Title) { " $($this.Title) " } else { " Data Table " }
            Write-BufferBox -X $this.X -Y $this.Y -Width $this.Width -Height $this.Height `
                -BorderColor $borderColor -Title $titleText
            $contentX++
            $contentY++
            $contentWidth -= 2
            $contentHeight -= 2
        }
        
        $currentY = $contentY
        $innerWidth = $contentWidth
        
        # Filter row
        if ($this.AllowFilter) {
            $filterBg = if ($this.FilterMode) { 
                Get-ThemeColor "Accent" -Default ([ConsoleColor]::Cyan)
            } else { 
                Get-ThemeColor "Background" -Default ([ConsoleColor]::Black)
            }
            $filterFg = if ($this.FilterMode) { 
                Get-ThemeColor "Background" -Default ([ConsoleColor]::Black)
            } else { 
                Get-ThemeColor "Primary" -Default ([ConsoleColor]::White)
            }
            $filterDisplayText = if ([string]::IsNullOrEmpty($this.FilterText)) { 
                "Filter: (Ctrl+F to edit)" 
            } else { 
                "Filter: $($this.FilterText)" 
            }
            Write-BufferString -X $contentX -Y $currentY -Text $filterDisplayText.PadRight($innerWidth) `
                -ForegroundColor $filterFg -BackgroundColor $filterBg
            $currentY++
        }
        
        # Calculate column widths
        $definedWidth = ($this.Columns | Where-Object Width | Measure-Object -Property Width -Sum).Sum
        if ($null -eq $definedWidth) { $definedWidth = 0 }
        $flexCols = @($this.Columns | Where-Object { -not $_.Width })
        $rowNumWidth = if ($this.ShowRowNumbers) { 5 } else { 0 }
        $remaining = $innerWidth - $definedWidth - $rowNumWidth - [Math]::Max(0, $this.Columns.Count - 1)
        $flexWidth = if ($flexCols.Count -gt 0) { 
            [Math]::Floor($remaining / $flexCols.Count) 
        } else { 
            0 
        }
        
        foreach ($col in $this.Columns) { 
            $col.CalculatedWidth = if ($col.Width) { 
                $col.Width 
            } else { 
                [Math]::Max(5, $flexWidth) 
            } 
        }
        
        # Header
        $dataAreaY = $currentY
        if ($this.ShowHeader) {
            $headerX = $contentX
            if ($this.ShowRowNumbers) {
                Write-BufferString -X $headerX -Y $currentY -Text "#".PadRight(4) `
                    -ForegroundColor (Get-ThemeColor "Header" -Default ([ConsoleColor]::Cyan))
                $headerX += 5
            }
            foreach ($col in $this.Columns) {
                $headerText = if ($col.Header) { $col.Header } else { $col.Name }
                if ($this.AllowSort -and $col.Sortable -ne $false -and $col.Name -eq $this.SortColumn) {
                    $headerText += if ($this.SortDirection -eq "Ascending") { " ▲" } else { " ▼" }
                }
                if ($headerText.Length -gt $col.CalculatedWidth) { 
                    $headerText = $headerText.Substring(0, [Math]::Max(0, $col.CalculatedWidth - 1)) + "…" 
                }
                Write-BufferString -X $headerX -Y $currentY -Text $headerText.PadRight($col.CalculatedWidth) `
                    -ForegroundColor (Get-ThemeColor "Header" -Default ([ConsoleColor]::Cyan))
                $headerX += $col.CalculatedWidth + 1
            }
            $currentY++
            $dataAreaY++
            Write-BufferString -X $contentX -Y $currentY -Text ("─" * $innerWidth) `
                -ForegroundColor (Get-ThemeColor "Border" -Default ([ConsoleColor]::DarkGray))
            $currentY++
            $dataAreaY++
        }

        # Data rows
        $startIdx = $this.CurrentPage * $this.PageSize
        $endIdx = [Math]::Min($startIdx + $this.PageSize - 1, @($this.ProcessedData).Count - 1)
        
        $footerOffset = if ($this.ShowFooter) { 1 } else { 0 }
        $dataAreaBottom = $contentY + $contentHeight - $footerOffset

        for ($i = $startIdx; $i -le $endIdx; $i++) {
            $row = $this.ProcessedData[$i]
            if (-not $row) { continue }
            
            $rowY = $dataAreaY + ($i - $startIdx)
            if ($rowY -ge $dataAreaBottom) { break }
            
            $rowX = $contentX
            $isSelected = ($this.IsFocused -and (($this.MultiSelect -and $this.SelectedRows -contains $i) -or (-not $this.MultiSelect -and $i -eq $this.SelectedRow)))
            $rowBg = if ($isSelected) { 
                Get-ThemeColor "Accent" -Default ([ConsoleColor]::Cyan)
            } else { 
                Get-ThemeColor "Background" -Default ([ConsoleColor]::Black)
            }
            $rowFg = if ($isSelected) { 
                Get-ThemeColor "Background" -Default ([ConsoleColor]::Black)
            } else { 
                Get-ThemeColor "Primary" -Default ([ConsoleColor]::White)
            }
            
            if ($isSelected) { 
                Write-BufferString -X $rowX -Y $rowY -Text (" " * $innerWidth) -BackgroundColor $rowBg 
            }
            
            if ($this.ShowRowNumbers) { 
                Write-BufferString -X $rowX -Y $rowY -Text ($i + 1).ToString().PadRight(4) `
                    -ForegroundColor (Get-ThemeColor "Subtle" -Default ([ConsoleColor]::DarkGray)) `
                    -BackgroundColor $rowBg
                $rowX += 5 
            }
            
            foreach ($col in $this.Columns) {
                $value = $row."$($col.Name)"
                $displayValue = if ($col.Format) { 
                    & $col.Format $value 
                } else { 
                    "$value" 
                }
                if ($displayValue.Length -gt $col.CalculatedWidth) { 
                    $displayValue = $displayValue.Substring(0, [Math]::Max(0, $col.CalculatedWidth - 1)) + "…" 
                }
                $cellFg = if ($col.Color -and -not $isSelected) { 
                    Get-ThemeColor (& $col.Color $value $row) -Default $rowFg
                } else { 
                    $rowFg 
                }
                Write-BufferString -X $rowX -Y $rowY -Text $displayValue.PadRight($col.CalculatedWidth) `
                    -ForegroundColor $cellFg -BackgroundColor $rowBg
                $rowX += $col.CalculatedWidth + 1
            }
        }
        
        # Empty state
        if (@($this.ProcessedData).Count -eq 0) {
            $emptyMessage = if ($this.FilterText) { 
                "No results match the filter" 
            } else { 
                "No data to display" 
            }
            $msgX = $contentX + [Math]::Floor(($contentWidth - $emptyMessage.Length) / 2)
            $msgY = $dataAreaY + [Math]::Floor(($dataAreaBottom - $dataAreaY) / 2)
            Write-BufferString -X $msgX -Y $msgY -Text $emptyMessage `
                -ForegroundColor (Get-ThemeColor "Subtle" -Default ([ConsoleColor]::DarkGray))
        }
        
        # Footer
        if ($this.ShowFooter) {
            $footerY = $contentY + $contentHeight - 1
            $statusText = "$(@($this.ProcessedData).Count) rows"
            if ($this.FilterText) { 
                $statusText += " (filtered)" 
            }
            if ($this.MultiSelect) { 
                $statusText += " | $(@($this.SelectedRows).Count) selected" 
            }
            Write-BufferString -X $contentX -Y $footerY -Text $statusText `
                -ForegroundColor (Get-ThemeColor "Subtle" -Default ([ConsoleColor]::DarkGray))
            
            $totalPages = if (@($this.ProcessedData).Count -gt 0) { 
                [Math]::Ceiling(@($this.ProcessedData).Count / $this.PageSize) 
            } else { 
                1 
            }
            if ($totalPages -gt 1) {
                $pageText = "Page $($this.CurrentPage + 1)/$totalPages"
                Write-BufferString -X ($contentX + $contentWidth - $pageText.Length) -Y $footerY `
                    -Text $pageText -ForegroundColor (Get-ThemeColor "Info" -Default ([ConsoleColor]::Cyan))
            }
        }
    } -Context @{ Component = $this.Name }
}

$component | Add-Member -MemberType ScriptMethod -Name "HandleInput" -Value {
    param($Key)
    Invoke-WithErrorHandling -Component "$($this.Name).HandleInput" -ScriptBlock {
        # Handle filter mode input
        if ($this.FilterMode) {
            switch ($Key.Key) {
                ([ConsoleKey]::Escape) { 
                    $this.FilterMode = $false
                    Request-TuiRefresh
                    return $true 
                }
                ([ConsoleKey]::Enter)  { 
                    $this.FilterMode = $false
                    Request-TuiRefresh
                    return $true 
                }
                ([ConsoleKey]::Backspace) {
                    if ($this.FilterText.Length -gt 0) {
                        $this.FilterText = $this.FilterText.Substring(0, $this.FilterText.Length - 1)
                        $this.ProcessData()
                        Request-TuiRefresh
                    }
                    return $true
                }
                default {
                    if ($Key.KeyChar -and -not [char]::IsControl($Key.KeyChar)) {
                        $this.FilterText += $Key.KeyChar
                        $this.ProcessData()
                        Request-TuiRefresh
                        return $true
                    }
                }
            }
            return $false
        }
        
        # Calculate pagination info
        $totalPages = if (@($this.ProcessedData).Count -gt 0) { 
            [Math]::Ceiling(@($this.ProcessedData).Count / $this.PageSize) 
        } else { 
            1 
        }
        $selectedItem = if (@($this.ProcessedData).Count -gt 0 -and $this.SelectedRow -ge 0 -and $this.SelectedRow -lt @($this.ProcessedData).Count) { 
            $this.ProcessedData[$this.SelectedRow] 
        } else { 
            $null 
        }

        # Handle regular input
        switch ($Key.Key) {
            ([ConsoleKey]::UpArrow) {
                if ($this.SelectedRow -gt 0) {
                    $this.SelectedRow--
                    if ($this.SelectedRow -lt ($this.CurrentPage * $this.PageSize)) { 
                        $this.CurrentPage-- 
                    }
                    Request-TuiRefresh
                }
                return $true
            }
            ([ConsoleKey]::DownArrow) {
                if ($this.SelectedRow -lt (@($this.ProcessedData).Count - 1)) {
                    $this.SelectedRow++
                    if ($this.SelectedRow -ge (($this.CurrentPage + 1) * $this.PageSize)) { 
                        $this.CurrentPage++ 
                    }
                    Request-TuiRefresh
                }
                return $true
            }
            ([ConsoleKey]::PageUp) { 
                if ($this.CurrentPage -gt 0) { 
                    $this.CurrentPage--
                    $this.SelectedRow = $this.CurrentPage * $this.PageSize
                    Request-TuiRefresh 
                }
                return $true 
            }
            ([ConsoleKey]::PageDown) { 
                if ($this.CurrentPage -lt ($totalPages - 1)) { 
                    $this.CurrentPage++
                    $this.SelectedRow = $this.CurrentPage * $this.PageSize
                    Request-TuiRefresh 
                }
                return $true 
            }
            ([ConsoleKey]::Home) { 
                $this.SelectedRow = 0
                $this.CurrentPage = 0
                Request-TuiRefresh
                return $true 
            }
            ([ConsoleKey]::End) { 
                $this.SelectedRow = @($this.ProcessedData).Count - 1
                $this.CurrentPage = [Math]::Max(0, $totalPages - 1)
                Request-TuiRefresh
                return $true 
            }
            
            ([ConsoleKey]::Enter) {
                if ($this.OnAction -and $selectedItem) {
                    Invoke-WithErrorHandling -Component "$($this.Name).OnAction" -ScriptBlock {
                        & $this.OnAction -Action 'select' -Item $selectedItem
                    } -Context @{ Component = $this.Name; Action = 'select'; Item = $selectedItem }
                }
                return $true
            }
            ([ConsoleKey]::E) {
                if ($this.OnAction -and $selectedItem) {
                    Invoke-WithErrorHandling -Component "$($this.Name).OnAction" -ScriptBlock {
                        & $this.OnAction -Action 'select' -Item $selectedItem
                    } -Context @{ Component = $this.Name; Action = 'select'; Item = $selectedItem }
                }
                return $true
            }
            ([ConsoleKey]::Delete) {
                if ($this.OnAction -and $selectedItem) {
                    Invoke-WithErrorHandling -Component "$($this.Name).OnAction" -ScriptBlock {
                        & $this.OnAction -Action 'delete' -Item $selectedItem
                    } -Context @{ Component = $this.Name; Action = 'delete'; Item = $selectedItem }
                }
                return $true
            }

            ([ConsoleKey]::F) { 
                if (($Key.Modifiers -band [ConsoleModifiers]::Control) -and $this.AllowFilter) { 
                    $this.FilterMode = $true
                    Request-TuiRefresh
                    return $true 
                } 
            }
            default {
                if ($Key.KeyChar -match '\d' -and $this.AllowSort) {
                    $colIndex = [int]$Key.KeyChar.ToString() - 1
                    if ($colIndex -ge 0 -and $colIndex -lt $this.Columns.Count -and ($this.Columns[$colIndex].Sortable -ne $false)) {
                        $colName = $this.Columns[$colIndex].Name
                        if ($this.SortColumn -eq $colName) {
                            # Toggle direction
                            if ($this.SortDirection -eq 'Ascending') {
                                $this.SortDirection = 'Descending'
                            }
                            else {
                                $this.SortDirection = 'Ascending'
                            }
                        }
                        else {
                            # Sort by new column
                            $this.SortColumn = $colName
                            $this.SortDirection = 'Ascending'
                        }
                        $this.ProcessData()
                        Request-TuiRefresh
                        return $true
                    }
                }
            }
        }
        return $false
    } -Context @{ Component = $this.Name; Key = $Key }
}

$component.ProcessData()
return $component
}
#endregion
Export-ModuleMember -Function @(
'New-HeliosLabel',
'New-HeliosButton',
'New-HeliosTextBox',
'New-HeliosCheckBox',
'New-HeliosProgressBar',
'New-HeliosTextArea',
'New-HeliosCalendarPicker',
'New-HeliosTimePicker',
'New-HeliosDataTable'
)