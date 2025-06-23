#
# MODULE: theme-support.psm1
# PURPOSE: Provides minimal theme support for the PMC Terminal application
# This is a simplified version that follows PowerShell-First principles
#

# Module-scoped theme configuration
$script:CurrentTheme = @{
    Name = "Default"
    Colors = @{
        # Core colors
        Background = [ConsoleColor]::Black
        Primary = [ConsoleColor]::White
        Secondary = [ConsoleColor]::Gray
        Accent = [ConsoleColor]::Cyan
        
        # Semantic colors
        Success = [ConsoleColor]::Green
        Warning = [ConsoleColor]::Yellow
        Error = [ConsoleColor]::Red
        Info = [ConsoleColor]::Blue
        
        # UI element colors
        Border = [ConsoleColor]::DarkGray
        Header = [ConsoleColor]::Cyan
        Footer = [ConsoleColor]::DarkGray
        Subtle = [ConsoleColor]::DarkGray
        
        # Component-specific colors
        ButtonFocused = [ConsoleColor]::Cyan
        ButtonUnfocused = [ConsoleColor]::Gray
        InputFocused = [ConsoleColor]::White
        InputUnfocused = [ConsoleColor]::Gray
        TableHeader = [ConsoleColor]::Cyan
        TableRowSelected = [ConsoleColor]::Cyan
    }
}

function Get-ThemeColor {
    <#
    .SYNOPSIS
        Gets a color value from the current theme
    .PARAMETER ColorName
        The name of the color to retrieve
    .PARAMETER Default
        Default color to return if the requested color is not found
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ColorName,
        
        [ConsoleColor]$Default = [ConsoleColor]::White
    )
    
    if ($script:CurrentTheme.Colors.ContainsKey($ColorName)) {
        return $script:CurrentTheme.Colors[$ColorName]
    }
    
    # Log warning for missing color (but don't fail)
    if (Get-Command -Name "Write-Log" -ErrorAction SilentlyContinue) {
        Write-Log -Level Debug -Message "Theme color '$ColorName' not found, using default: $Default"
    }
    
    return $Default
}

function Set-Theme {
    <#
    .SYNOPSIS
        Sets the current theme
    .PARAMETER ThemeName
        The name of the theme to set
    .PARAMETER Colors
        Hashtable of color overrides
    #>
    [CmdletBinding()]
    param(
        [string]$ThemeName = "Default",
        [hashtable]$Colors = @{}
    )
    
    $script:CurrentTheme.Name = $ThemeName
    
    # Apply color overrides
    foreach ($key in $Colors.Keys) {
        $script:CurrentTheme.Colors[$key] = $Colors[$key]
    }
    
    # Request TUI refresh if available
    if (Get-Command -Name "Request-TuiRefresh" -ErrorAction SilentlyContinue) {
        Request-TuiRefresh
    }
}

function Get-CurrentTheme {
    <#
    .SYNOPSIS
        Gets the current theme configuration
    #>
    [CmdletBinding()]
    param()
    
    # Return a copy to prevent direct modification
    return @{
        Name = $script:CurrentTheme.Name
        Colors = $script:CurrentTheme.Colors.Clone()
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Get-ThemeColor',
    'Set-Theme',
    'Get-CurrentTheme'
)