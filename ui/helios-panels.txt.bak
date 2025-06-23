# FILE: ui/helios-panels.psm1
# PURPOSE: Provides a suite of declarative layout panels for UI construction,
# refactored to use a PowerShell-idiomatic PSCustomObject model.

#region Internal Functions

# Internal helper function to create the base panel object with common properties and methods.
# Not exported.
function New-HeliosBasePanel {
    param(
        [hashtable]$Props
    )

    # All panels are PSCustomObjects. Properties are initialized with defaults
    # using the null-coalescing operator for conciseness.
    $panel = [PSCustomObject]@{
        Type            = "Panel"
        Name            = $Props.Name ?? "Panel_$([Guid]::NewGuid().ToString('N').Substring(0,8))"
        X               = $Props.X ?? 0
        Y               = $Props.Y ?? 0
        Width           = $Props.Width ?? 40
        Height          = $Props.Height ?? 20
        Visible         = $Props.Visible ?? $true
        IsFocusable     = $Props.IsFocusable ?? $false
        ZIndex          = $Props.ZIndex ?? 0
        Children        = [System.Collections.ArrayList]@() # Use ArrayList for efficient Add/Remove
        Parent          = $null
        LayoutProps     = $Props.LayoutProps ?? @{}
        ShowBorder      = $Props.ShowBorder ?? $false
        BorderStyle     = $Props.BorderStyle ?? "Single"  # Single, Double, Rounded
        BorderColor     = $Props.BorderColor ?? "Border" # Theme color name
        Title           = $Props.Title
        Padding         = $Props.Padding ?? 0
        Margin          = $Props.Margin ?? 0
        BackgroundColor = $Props.BackgroundColor
        ForegroundColor = $Props.ForegroundColor
        _isDirty        = $true
        _cachedLayout   = $null
    }

    # Add methods using Add-Member for discoverability and clean $object.Method() syntax.
    # The automatic $this variable refers to the panel object itself.

    $panel | Add-Member -MemberType ScriptMethod -Name AddChild -Value {
        param($Child, [hashtable]$LayoutProps = @{})
        Invoke-WithErrorHandling -Component "$($this.Name).AddChild" -ScriptBlock {
            if (-not $Child) { throw "Cannot add a null or empty child to a panel." }

            $Child.Parent = $this
            $Child.LayoutProps = $LayoutProps
            [void]$this.Children.Add($Child)
            $this.InvalidateLayout()

            # Propagate visibility from parent
            if (-not $this.Visible) {
                $Child.Visible = $false
            }
        } -Context @{ Parent = $this.Name; ChildType = $Child.Type; ChildName = $Child.Name } -ErrorHandler {
            param($Exception)
            Write-Log -Level Error -Message "Panel AddChild error: $($Exception.Message)" -Data $Exception.Context
        }
    }

    $panel | Add-Member -MemberType ScriptMethod -Name RemoveChild -Value {
        param($Child)
        Invoke-WithErrorHandling -Component "$($this.Name).RemoveChild" -ScriptBlock {
            $this.Children.Remove($Child)
            if ($Child.Parent -eq $this) {
                $Child.Parent = $null
            }
            $this.InvalidateLayout()
        } -Context @{ Parent = $this.Name; ChildType = $Child.Type; ChildName = $Child.Name } -ErrorHandler {
            param($Exception)
            Write-Log -Level Error -Message "Panel RemoveChild error: $($Exception.Message)" -Data $Exception.Context
        }
    }

    $panel | Add-Member -MemberType ScriptMethod -Name ClearChildren -Value {
        Invoke-WithErrorHandling -Component "$($this.Name).ClearChildren" -ScriptBlock {
            foreach ($child in $this.Children) {
                $child.Parent = $null
            }
            $this.Children.Clear()
            $this.InvalidateLayout()
        } -Context @{ Parent = $this.Name } -ErrorHandler {
            param($Exception)
            Write-Log -Level Error -Message "Panel ClearChildren error: $($Exception.Message)" -Data $Exception.Context
        }
    }

    $panel | Add-Member -MemberType ScriptMethod -Name Show -Value {
        Invoke-WithErrorHandling -Component "$($this.Name).Show" -ScriptBlock {
            if ($this.Visible) { return }
            $this.Visible = $true
            foreach ($child in $this.Children) {
                if ($child.PSObject.Methods['Show']) { $child.Show() } else { $child.Visible = $true }
            }
            $this.InvalidateLayout() # Visibility change affects layout
        } -Context @{ Panel = $this.Name } -ErrorHandler {
            param($Exception)
            Write-Log -Level Error -Message "Panel Show error: $($Exception.Message)" -Data $Exception.Context
        }
    }

    $panel | Add-Member -MemberType ScriptMethod -Name Hide -Value {
        Invoke-WithErrorHandling -Component "$($this.Name).Hide" -ScriptBlock {
            if (-not $this.Visible) { return }
            $this.Visible = $false
            foreach ($child in $this.Children) {
                if ($child.PSObject.Methods['Hide']) { $child.Hide() } else { $child.Visible = $false }
            }
            $this.InvalidateLayout() # Visibility change affects layout
        } -Context @{ Panel = $this.Name } -ErrorHandler {
            param($Exception)
            Write-Log -Level Error -Message "Panel Hide error: $($Exception.Message)" -Data $Exception.Context
        }
    }

    $panel | Add-Member -MemberType ScriptMethod -Name HandleInput -Value {
        param($Key)
        # Panels typically don't handle input directly but delegate to children.
        # This can be overridden for special behavior.
        return $false
    }

    $panel | Add-Member -MemberType ScriptMethod -Name GetContentBounds -Value {
        Invoke-WithErrorHandling -Component "$($this.Name).GetContentBounds" -ScriptBlock {
            $borderOffset = if ($this.ShowBorder) { 1 } else { 0 }
            $totalMargin = $this.Margin * 2
            $totalPadding = $this.Padding * 2
            $totalBorder = $borderOffset * 2

            return [PSCustomObject]@{
                X      = $this.X + $this.Margin + $this.Padding + $borderOffset
                Y      = $this.Y + $this.Margin + $this.Padding + $borderOffset
                Width  = $this.Width - $totalMargin - $totalPadding - $totalBorder
                Height = $this.Height - $totalMargin - $totalPadding - $totalBorder
            }
        } -Context @{ Panel = $this.Name } -ErrorHandler {
            param($Exception)
            Write-Log -Level Error -Message "Panel GetContentBounds error: $($Exception.Message)" -Data $Exception.Context
            return [PSCustomObject]@{ X = $this.X; Y = $this.Y; Width = $this.Width; Height = $this.Height } # Fallback
        }
    }

    $panel | Add-Member -MemberType ScriptMethod -Name InvalidateLayout -Value {
        Invoke-WithErrorHandling -Component "$($this.Name).InvalidateLayout" -ScriptBlock {
            $this._isDirty = $true
            # Propagate invalidation up the visual tree to the root
            if ($this.Parent -and $this.Parent.PSObject.Methods['InvalidateLayout']) {
                $this.Parent.InvalidateLayout()
            }
        } -Context @{ Panel = $this.Name } -ErrorHandler {
            param($Exception)
            Write-Log -Level Error -Message "Panel InvalidateLayout error: $($Exception.Message)" -Data $Exception.Context
        }
    }

    return $panel
}

#endregion

#region Public Panel Factories

function New-HeliosStackPanel {
    [CmdletBinding()]
    param(
        [hashtable]$Props = @{}
    )

    $panel = New-HeliosBasePanel -Props $Props
    $panel.Type = "StackPanel"
    $panel.PSObject.Properties.Add([psnoteproperty]::new('Orientation', ($Props.Orientation ?? 'Vertical')))
    $panel.PSObject.Properties.Add([psnoteproperty]::new('Spacing', ($Props.Spacing ?? 1)))
    $panel.PSObject.Properties.Add([psnoteproperty]::new('HorizontalAlignment', ($Props.HorizontalAlignment ?? 'Stretch'))) # Left, Center, Right, Stretch
    $panel.PSObject.Properties.Add([psnoteproperty]::new('VerticalAlignment', ($Props.VerticalAlignment ?? 'Stretch')))     # Top, Middle, Bottom, Stretch

    $panel | Add-Member -MemberType ScriptMethod -Name CalculateLayout -Value {
        Invoke-WithErrorHandling -Component "$($this.Name).CalculateLayout" -ScriptBlock {
            $bounds = $this.GetContentBounds()
            $layout = @{ Children = [System.Collections.ArrayList]@() }
            $visibleChildren = $this.Children | Where-Object { $_.Visible }
            if ($visibleChildren.Count -eq 0) {
                $this._isDirty = $false
                return $layout
            }

            $currentX = $bounds.X
            $currentY = $bounds.Y
            $totalChildWidth = 0
            $totalChildHeight = 0

            # Calculate total size needed
            foreach ($child in $visibleChildren) {
                if ($this.Orientation -eq 'Vertical') {
                    $totalChildHeight += $child.Height
                    $totalChildWidth = [Math]::Max($totalChildWidth, $child.Width)
                }
                else {
                    $totalChildWidth += $child.Width
                    $totalChildHeight = [Math]::Max($totalChildHeight, $child.Height)
                }
            }

            # Add spacing
            $totalSpacing = ($visibleChildren.Count - 1) * $this.Spacing
            if ($this.Orientation -eq 'Vertical') { $totalChildHeight += $totalSpacing } else { $totalChildWidth += $totalSpacing }

            # Calculate starting position based on alignment
            if ($this.Orientation -eq 'Vertical') {
                switch ($this.VerticalAlignment) {
                    'Top'    { $currentY = $bounds.Y }
                    'Middle' { $currentY = $bounds.Y + [Math]::Floor(($bounds.Height - $totalChildHeight) / 2) }
                    'Bottom' { $currentY = $bounds.Y + $bounds.Height - $totalChildHeight }
                }
            }
            else {
                switch ($this.HorizontalAlignment) {
                    'Left'   { $currentX = $bounds.X }
                    'Center' { $currentX = $bounds.X + [Math]::Floor(($bounds.Width - $totalChildWidth) / 2) }
                    'Right'  { $currentX = $bounds.X + $bounds.Width - $totalChildWidth }
                }
            }

            # Layout children
            foreach ($child in $visibleChildren) {
                $childX = $currentX
                $childY = $currentY
                $childWidth = $child.Width
                $childHeight = $child.Height

                # Apply stretch and alignment
                if ($this.Orientation -eq 'Vertical') {
                    switch ($this.HorizontalAlignment) {
                        'Stretch' { $childWidth = $bounds.Width; $childX = $bounds.X }
                        'Center'  { $childX = $bounds.X + [Math]::Floor(($bounds.Width - $childWidth) / 2) }
                        'Right'   { $childX = $bounds.X + $bounds.Width - $childWidth }
                    }
                }
                else { # Horizontal
                    switch ($this.VerticalAlignment) {
                        'Stretch' { $childHeight = $bounds.Height; $childY = $bounds.Y }
                        'Middle'  { $childY = $bounds.Y + [Math]::Floor(($bounds.Height - $childHeight) / 2) }
                        'Bottom'  { $childY = $bounds.Y + $bounds.Height - $childHeight }
                    }
                }

                # CRITICAL: Apply calculated positions and sizes back to the child component
                $child.X = $childX
                $child.Y = $childY
                if ($child.PSObject.Properties['Width'] -and $child.Width -ne $childWidth) { $child.Width = $childWidth }
                if ($child.PSObject.Properties['Height'] -and $child.Height -ne $childHeight) { $child.Height = $childHeight }

                [void]$layout.Children.Add(@{ Component = $child; X = $childX; Y = $childY; Width = $childWidth; Height = $childHeight })

                # Move to next position
                if ($this.Orientation -eq 'Vertical') { $currentY += $childHeight + $this.Spacing } else { $currentX += $childWidth + $this.Spacing }
            }

            $this._cachedLayout = $layout
            $this._isDirty = $false
            return $layout
        } -Context @{ Panel = $this.Name; Orientation = $this.Orientation } -ErrorHandler {
            param($Exception)
            Write-Log -Level Error -Message "StackPanel CalculateLayout error: $($Exception.Message)" -Data $Exception.Context
            return @{ Children = [System.Collections.ArrayList]@() } # Return empty layout on error
        }
    }

    $panel | Add-Member -MemberType ScriptMethod -Name Render -Value {
        Invoke-WithErrorHandling -Component "$($this.Name).Render" -ScriptBlock {
            if (-not $this.Visible) { return }

            $bgColor = if ($this.BackgroundColor) { $this.BackgroundColor } else { Get-ThemeColor "Background" }
            for ($y = $this.Y; $y -lt ($this.Y + $this.Height); $y++) {
                Write-BufferString -X $this.X -Y $y -Text (' ' * $this.Width) -BackgroundColor $bgColor
            }

            if ($this.ShowBorder) {
                $borderColor = if ($this.BorderColor) { Get-ThemeColor $this.BorderColor } else { Get-ThemeColor "Border" }
                Write-BufferBox -X $this.X -Y $this.Y -Width $this.Width -Height $this.Height -BorderColor $borderColor -BackgroundColor $bgColor -BorderStyle $this.BorderStyle -Title $this.Title
            }

            # Ensure layout is calculated before the TUI Engine renders the children.
            if ($this._isDirty) {
                [void]$this.CalculateLayout()
            }
        } -Context @{ Panel = $this.Name } -ErrorHandler {
            param($Exception)
            Write-Log -Level Error -Message "StackPanel Render error: $($Exception.Message)" -Data $Exception.Context
        }
    }

    return $panel
}

function New-HeliosGridPanel {
    [CmdletBinding()]
    param(
        [hashtable]$Props = @{}
    )

    $panel = New-HeliosBasePanel -Props $Props
    $panel.Type = "GridPanel"
    $panel.PSObject.Properties.Add([psnoteproperty]::new('RowDefinitions', ($Props.RowDefinitions ?? @("1*"))))
    $panel.PSObject.Properties.Add([psnoteproperty]::new('ColumnDefinitions', ($Props.ColumnDefinitions ?? @("1*"))))
    $panel.PSObject.Properties.Add([psnoteproperty]::new('ShowGridLines', ($Props.ShowGridLines ?? $false)))
    $panel.PSObject.Properties.Add([psnoteproperty]::new('GridLineColor', ($Props.GridLineColor ?? (Get-ThemeColor "BorderDim"))))

    # Private helper method to parse row/column definitions
    $panel | Add-Member -MemberType ScriptMethod -Name _CalculateGridSizes -Value {
        param($definitions, $totalSize)
        Invoke-WithErrorHandling -Component "$($this.Name)._CalculateGridSizes" -ScriptBlock {
            $parsedDefs = [System.Collections.ArrayList]@()
            $totalFixed = 0
            $totalStars = 0.0

            foreach ($def in $definitions) {
                if ($def -match '^(\d+)$') {
                    [void]$parsedDefs.Add(@{ Type = 'Fixed'; Value = [int]$Matches[1] })
                    $totalFixed += [int]$Matches[1]
                }
                elseif ($def -match '^(\d*\.?\d*)\*$') {
                    $stars = if ($Matches[1]) { [double]$Matches[1] } else { 1.0 }
                    [void]$parsedDefs.Add(@{ Type = 'Star'; Value = $stars })
                    $totalStars += $stars
                }
                else { throw "Invalid grid definition: $def" }
            }

            $remainingSize = [Math]::Max(0, $totalSize - $totalFixed)
            $sizes = [System.Collections.ArrayList]@()
            foreach ($def in $parsedDefs) {
                if ($def.Type -eq 'Fixed') {
                    [void]$sizes.Add($def.Value)
                }
                else {
                    $size = if ($totalStars -gt 0) { [Math]::Floor($remainingSize * ($def.Value / $totalStars)) } else { 0 }
                    [void]$sizes.Add($size)
                }
            }

            # Distribute rounding errors to the last star-sized cell
            $totalAllocated = ($sizes | Measure-Object -Sum).Sum
            if ($totalAllocated -ne $totalSize -and $totalStars -gt 0) {
                $lastStarIndex = $parsedDefs.FindLastIndex({ param($d) $d.Type -eq 'Star' })
                if ($lastStarIndex -ne -1) {
                    $sizes[$lastStarIndex] += ($totalSize - $totalAllocated)
                }
            }
            return $sizes
        } -Context @{ Panel = $this.Name; Definitions = $definitions; TotalSize = $totalSize } -ErrorHandler {
            param($Exception)
            Write-Log -Level Error -Message "GridPanel _CalculateGridSizes error: $($Exception.Message)" -Data $Exception.Context
            return @()
        }
    }

    $panel | Add-Member -MemberType ScriptMethod -Name CalculateLayout -Value {
        Invoke-WithErrorHandling -Component "$($this.Name).CalculateLayout" -ScriptBlock {
            $bounds = $this.GetContentBounds()
            $rowHeights = $this._CalculateGridSizes($this.RowDefinitions, $bounds.Height)
            $colWidths = $this._CalculateGridSizes($this.ColumnDefinitions, $bounds.Width)

            $rowOffsets = @(0); for ($i = 0; $i -lt $rowHeights.Count - 1; $i++) { $rowOffsets += ($rowOffsets[-1] + $rowHeights[$i]) }
            $colOffsets = @(0); for ($i = 0; $i -lt $colWidths.Count - 1; $i++) { $colOffsets += ($colOffsets[-1] + $colWidths[$i]) }

            $layout = @{ Children = [System.Collections.ArrayList]@(); Rows = $rowHeights; Columns = $colWidths; RowOffsets = $rowOffsets; ColumnOffsets = $colOffsets }

            foreach ($child in $this.Children | Where-Object { $_.Visible }) {
                $gridRow = [int]($child.LayoutProps.'Grid.Row' ?? 0)
                $gridCol = [int]($child.LayoutProps.'Grid.Column' ?? 0)
                $gridRowSpan = [int]($child.LayoutProps.'Grid.RowSpan' ?? 1)
                $gridColSpan = [int]($child.LayoutProps.'Grid.ColumnSpan' ?? 1)

                $row = [Math]::Max(0, [Math]::Min($rowHeights.Count - 1, $gridRow))
                $col = [Math]::Max(0, [Math]::Min($colWidths.Count - 1, $gridCol))
                $rowSpan = [Math]::Max(1, [Math]::Min($rowHeights.Count - $row, $gridRowSpan))
                $colSpan = [Math]::Max(1, [Math]::Min($colWidths.Count - $col, $gridColSpan))

                $cellX = $bounds.X + $colOffsets[$col]; $cellY = $bounds.Y + $rowOffsets[$row]
                $cellWidth = ($colWidths[$col..($col + $colSpan - 1)] | Measure-Object -Sum).Sum
                $cellHeight = ($rowHeights[$row..($row + $rowSpan - 1)] | Measure-Object -Sum).Sum

                $childX = $cellX; $childY = $cellY
                $childWidth = $child.Width; $childHeight = $child.Height

                switch ($child.LayoutProps.'Grid.HorizontalAlignment' ?? 'Stretch') {
                    "Center"  { $childX = $cellX + [Math]::Floor(($cellWidth - $childWidth) / 2) }
                    "Right"   { $childX = $cellX + $cellWidth - $childWidth }
                    "Stretch" { $childWidth = $cellWidth }
                }
                switch ($child.LayoutProps.'Grid.VerticalAlignment' ?? 'Stretch') {
                    "Middle"  { $childY = $cellY + [Math]::Floor(($cellHeight - $childHeight) / 2) }
                    "Bottom"  { $childY = $cellY + $cellHeight - $childHeight }
                    "Stretch" { $childHeight = $cellHeight }
                }

                # CRITICAL: Apply calculated positions and sizes back to the child component
                $child.X = $childX
                $child.Y = $childY
                if ($child.PSObject.Properties['Width'] -and $child.Width -ne $childWidth) { $child.Width = $childWidth }
                if ($child.PSObject.Properties['Height'] -and $child.Height -ne $childHeight) { $child.Height = $childHeight }

                [void]$layout.Children.Add(@{ Component = $child; X = $childX; Y = $childY; Width = $childWidth; Height = $childHeight })
            }

            $this._cachedLayout = $layout
            $this._isDirty = $false
            return $layout
        } -Context @{ Panel = $this.Name; RowDefs = $this.RowDefinitions; ColDefs = $this.ColumnDefinitions } -ErrorHandler {
            param($Exception)
            Write-Log -Level Error -Message "GridPanel CalculateLayout error: $($Exception.Message)" -Data $Exception.Context
            return @{ Children = [System.Collections.ArrayList]@() }
        }
    }

    $panel | Add-Member -MemberType ScriptMethod -Name Render -Value {
        Invoke-WithErrorHandling -Component "$($this.Name).Render" -ScriptBlock {
            if (-not $this.Visible) { return }

            $bgColor = if ($this.BackgroundColor) { $this.BackgroundColor } else { Get-ThemeColor "Background" }
            for ($y = $this.Y; $y -lt ($this.Y + $this.Height); $y++) {
                Write-BufferString -X $this.X -Y $y -Text (' ' * $this.Width) -BackgroundColor $bgColor
            }

            if ($this.ShowBorder) {
                $borderColor = if ($this.BorderColor) { Get-ThemeColor $this.BorderColor } else { Get-ThemeColor "Border" }
                Write-BufferBox -X $this.X -Y $this.Y -Width $this.Width -Height $this.Height -BorderColor $borderColor -BackgroundColor $bgColor -BorderStyle $this.BorderStyle -Title $this.Title
            }

            if ($this._isDirty) {
                [void]$this.CalculateLayout()
            }
            $layout = $this._cachedLayout

            if ($this.ShowGridLines -and $layout) {
                $bounds = $this.GetContentBounds()
                foreach ($offset in $layout.ColumnOffsets[1..($layout.ColumnOffsets.Count - 1)]) {
                    $x = $bounds.X + $offset; for ($y = $bounds.Y; $y -lt ($bounds.Y + $bounds.Height); $y++) { Write-BufferChar -X $x -Y $y -Char "│" -ForegroundColor $this.GridLineColor }
                }
                foreach ($offset in $layout.RowOffsets[1..($layout.RowOffsets.Count - 1)]) {
                    $y = $bounds.Y + $offset; Write-BufferString -X $bounds.X -Y $y -Text ("─" * $bounds.Width) -ForegroundColor $this.GridLineColor
                }
            }
        } -Context @{ Panel = $this.Name } -ErrorHandler {
            param($Exception)
            Write-Log -Level Error -Message "GridPanel Render error: $($Exception.Message)" -Data $Exception.Context
        }
    }

    return $panel
}

function New-HeliosDockPanel {
    [CmdletBinding()]
    param(
        [hashtable]$Props = @{}
    )
    # A DockPanel is a StackPanel with a fixed vertical orientation.
    # Clone the props to avoid side-effects on the caller's hashtable.
    $dockProps = $Props.Clone()
    $dockProps.Orientation = 'Vertical'
    return New-HeliosStackPanel -Props $dockProps
}

function New-HeliosWrapPanel {
    [CmdletBinding()]
    param(
        [hashtable]$Props = @{}
    )
    # The legacy implementation was an alias for StackPanel. A true WrapPanel
    # would require different layout logic. Replicating legacy behavior for now.
    return New-HeliosStackPanel -Props $Props
}

#endregion

Export-ModuleMember -Function "New-HeliosStackPanel", "New-HeliosGridPanel", "New-HeliosDockPanel", "New-HeliosWrapPanel"