# Test-ComponentStructure.ps1
# Diagnostic script to test component creation and focus management

param(
    [switch]$Detailed
)

# Set up logging to see what's happening
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$basePath = Split-Path -Parent $MyInvocation.MyCommand.Path

# Load core modules first
Write-Host "Loading core modules..." -ForegroundColor Cyan
Import-Module "$basePath\modules\exceptions.psm1" -Force -Global
Import-Module "$basePath\modules\logger.psm1" -Force -Global
Initialize-Logger

# Load theme and UI modules
Import-Module "$basePath\modules\theme-support.psm1" -Force -Global
Import-Module "$basePath\ui\helios-panels.psm1" -Force -Global
Import-Module "$basePath\ui\helios-components.psm1" -Force -Global

Write-Host "Testing component creation..." -ForegroundColor Yellow

# Test 1: Create a simple button
Write-Host "`n=== Test 1: Basic Button Creation ===" -ForegroundColor Green
$testButton = New-HeliosButton -Props @{
    Name = "TestButton"
    Text = "Test Button"
    Width = 20
    Height = 3
    IsFocusable = $true
    Visible = $true
}

Write-Host "Button created successfully!"
Write-Host "  Name: $($testButton.Name)"
Write-Host "  Type: $($testButton.Type)"
Write-Host "  IsFocusable: $($testButton.IsFocusable)"
Write-Host "  Visible: $($testButton.Visible)"
Write-Host "  Has Render method: $(($testButton.PSObject.ScriptMethods.Name -contains 'Render'))"
Write-Host "  Has HandleInput method: $(($testButton.PSObject.ScriptMethods.Name -contains 'HandleInput'))"

# Test 2: Create a panel and add children
Write-Host "`n=== Test 2: Panel with Children ===" -ForegroundColor Green
$testPanel = New-HeliosStackPanel -Props @{
    Name = "TestPanel"
    Width = 50
    Height = 20
    Visible = $true
    Orientation = "Vertical"
    Spacing = 1
}

Write-Host "Panel created successfully!"
Write-Host "  Name: $($testPanel.Name)"
Write-Host "  Type: $($testPanel.Type)"
Write-Host "  Children count (initial): $($testPanel.Children.Count)"

# Add the button to the panel
$testPanel.AddChild($testButton)
Write-Host "  Children count (after adding button): $($testPanel.Children.Count)"

if ($testPanel.Children.Count -gt 0) {
    $child = $testPanel.Children[0]
    Write-Host "  First child: $($child.Name), Type: $($child.Type)"
    Write-Host "  First child IsFocusable: $($child.IsFocusable)"
    Write-Host "  First child Visible: $($child.Visible)"
} else {
    Write-Host "  ERROR: No children found!" -ForegroundColor Red
}

# Test 3: Mock the focus manager component discovery
Write-Host "`n=== Test 3: Focus Manager Component Discovery ===" -ForegroundColor Green

function Test-FindFocusableComponents {
    param($RootComponent)
    
    Write-Host "Starting component discovery from: $($RootComponent.Name)"
    $focusable = @()
    $queue = @($RootComponent)
    $processed = 0

    while ($queue.Count -gt 0) {
        $current = $queue[0]
        $queue = $queue[1..($queue.Count-1)]
        $processed++

        if (-not $current) { continue }

        Write-Host "  Processing: $($current.Name), Type: $($current.Type)"
        Write-Host "    Visible: $($current.Visible), IsFocusable: $($current.IsFocusable)"

        if (($current.PSObject.Properties.Name -contains 'IsFocusable') -and $current.IsFocusable -and 
            ($current.PSObject.Properties.Name -contains 'Visible') -and $current.Visible) {
            $focusable += $current
            Write-Host "    >>> FOCUSABLE COMPONENT FOUND! <<<" -ForegroundColor Green
        }

        if (($current.PSObject.Properties.Name -contains 'Children') -and $current.Children) {
            Write-Host "    Has $($current.Children.Count) children"
            foreach ($child in $current.Children) {
                if ($child) {
                    $queue += $child
                }
            }
        }
    }

    Write-Host "Processed $processed components, found $($focusable.Count) focusable"
    return $focusable
}

$focusableComponents = Test-FindFocusableComponents -RootComponent $testPanel
Write-Host "Total focusable components found: $($focusableComponents.Count)"

foreach ($comp in $focusableComponents) {
    Write-Host "  - $($comp.Name) ($($comp.Type))"
}

# Test 4: Create multiple buttons like the dashboard does
Write-Host "`n=== Test 4: Multiple Buttons (Dashboard Style) ===" -ForegroundColor Green

$menuItems = @(
    @{ Text = "1. Test Item 1"; Enabled = $true }
    @{ Text = "2. Test Item 2"; Enabled = $true }
    @{ Text = "3. Test Item 3"; Enabled = $false }
)

$multiPanel = New-HeliosStackPanel -Props @{
    Name = "MultiButtonPanel"
    Width = 60
    Height = 30
    Visible = $true
    Orientation = "Vertical"
    Spacing = 1
}

$buttons = @()
foreach ($item in $menuItems) {
    $button = New-HeliosButton -Props @{
        Name = "Button_$($item.Text.Replace(' ','_').Replace('.',''))"
        Text = $item.Text
        Width = 50
        Height = 3
        IsFocusable = $item.Enabled
        Visible = $true
    }
    
    $multiPanel.AddChild($button)
    $buttons += $button
    
    Write-Host "Created button: $($button.Name), IsFocusable: $($button.IsFocusable)"
}

Write-Host "Panel now has $($multiPanel.Children.Count) children"

# Test the focus discovery on this panel
$multiFocusable = Test-FindFocusableComponents -RootComponent $multiPanel
Write-Host "Found $($multiFocusable.Count) focusable components in multi-button panel"

if ($Detailed) {
    Write-Host "`n=== Detailed Object Inspection ===" -ForegroundColor Yellow
    
    Write-Host "`nButton object structure:"
    $testButton.PSObject.Properties | ForEach-Object {
        Write-Host "  Property: $($_.Name) = $($_.Value)"
    }
    
    Write-Host "`nButton methods:"
    $testButton.PSObject.Methods | ForEach-Object {
        Write-Host "  Method: $($_.Name)"
    }
    
    Write-Host "`nPanel object structure:"
    $testPanel.PSObject.Properties | ForEach-Object {
        Write-Host "  Property: $($_.Name) = $($_.Value)"
    }
}

Write-Host "`n=== Test Complete ===" -ForegroundColor Cyan
Write-Host "If you see focusable components found above, the issue is likely in the focus manager timing or event handling."
Write-Host "If no focusable components are found, there's an issue with component creation or the discovery algorithm."