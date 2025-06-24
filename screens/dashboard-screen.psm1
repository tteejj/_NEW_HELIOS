# Ultra-simple Dashboard - Direct buffer writing test

function New-UltraSimpleDashboard {
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Services
    )
    
    Write-Log "Creating Ultra Simple Dashboard" -Level Info
    
    $dashboard = [PSCustomObject]@{
        Name = "UltraSimpleDashboard"
        Services = $Services
        RootPanel = $null
    }
    
    # Add BuildUI method
    $dashboard | Add-Member -MemberType ScriptMethod -Name BuildUI -Value {
        Write-Log "Building Ultra Simple UI" -Level Info
        
        # Create root panel with a Render method that directly writes to buffer
        $this.RootPanel = [PSCustomObject]@{
            Name = "SimpleRoot"
            Type = "Panel"
            X = 0
            Y = 0
            Visible = $true
            Children = @()
        }
        
        # Add render method to root that directly draws
        $this.RootPanel | Add-Member -MemberType ScriptMethod -Name Render -Value {
            Write-Log "Root panel rendering - writing directly to buffer" -Level Info
            
            # Direct buffer writes - bypass component system
            Write-BufferString -X 10 -Y 5 -Text "*** PMC TERMINAL V5 ***" -ForegroundColor ([ConsoleColor]::Cyan)
            Write-BufferString -X 10 -Y 7 -Text "If you see this, rendering works!" -ForegroundColor ([ConsoleColor]::Green)
            Write-BufferBox -X 5 -Y 10 -Width 50 -Height 10 -BorderStyle "Double" -BorderColor ([ConsoleColor]::Yellow)
            Write-BufferString -X 10 -Y 12 -Text "Menu Options:" -ForegroundColor ([ConsoleColor]::White)
            Write-BufferString -X 10 -Y 14 -Text "1. Tasks" -ForegroundColor ([ConsoleColor]::White)
            Write-BufferString -X 10 -Y 15 -Text "2. Exit" -ForegroundColor ([ConsoleColor]::White)
            Write-BufferString -X 10 -Y 22 -Text "Press ESC to exit" -ForegroundColor ([ConsoleColor]::DarkGray)
            
            # Force dirty flag
            $global:TuiState.IsDirty = $true
        }
        
        Write-Log "Ultra Simple UI built" -Level Info
    }
    
    # Add simple input handler
    $dashboard | Add-Member -MemberType ScriptMethod -Name HandleInput -Value {
        param($KeyInfo)
        
        if ($KeyInfo.Key -eq [ConsoleKey]::Escape) {
            Write-Log "Escape pressed - exiting" -Level Info
            $global:TuiState.Running = $false
            return "Quit"
        }
        
        return $false
    }
    
    # Build the UI
    $dashboard.BuildUI()
    
    # Debug: Check if render method exists
    Write-Log "RootPanel has Render method: $($dashboard.RootPanel.PSObject.Methods.Name -contains 'Render')" -Level Info
    Write-Log "RootPanel ScriptMethods: $($dashboard.RootPanel.PSObject.ScriptMethods.Name -join ', ')" -Level Info
    
    return $dashboard
}

# Factory function
function Get-HeliosDashboardScreen {
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Services
    )
    
    return New-UltraSimpleDashboard -Services $Services
}

Export-ModuleMember -Function New-UltraSimpleDashboard, Get-HeliosDashboardScreen
