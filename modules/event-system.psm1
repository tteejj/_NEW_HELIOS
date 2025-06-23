# FILE: modules/event-system.psm1
# PURPOSE: Provides PowerShell native eventing functionality for the PMC Terminal v5 application.
#          Services use this to announce state changes, and UI components subscribe to these events
#          to maintain synchronization. Follows the PowerShell-First architectural principles.

Set-StrictMode -Version Latest

#region Core Event Management Functions

function Initialize-HeliosEventSystem {
    <#
    .SYNOPSIS
        Initializes the Helios event system for the application.
    .DESCRIPTION
        Sets up the core event infrastructure and registers any global event handlers
        needed by the application framework.
    .OUTPUTS
        [PSCustomObject] Event system manager object
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()
    
    Invoke-WithErrorHandling -Component "Initialize-HeliosEventSystem" -Context @{} -ScriptBlock {
        Write-Log -Level Debug -Message "Initializing Helios Event System..."
        
        $eventSystem = [PSCustomObject]@{
            Name = "HeliosEventSystem"
            RegisteredSources = [System.Collections.Generic.HashSet[string]]::new()
            ActiveSubscriptions = [System.Collections.ArrayList]::new()
        }
        
        # Add methods for managing event sources
        $registerSourceScript = {
            param([string]$SourceIdentifier)
            
            if ([string]::IsNullOrWhiteSpace($SourceIdentifier)) {
                throw "SourceIdentifier cannot be null or empty"
            }
            
            if ($this.RegisteredSources.Contains($SourceIdentifier)) {
                Write-Log -Level Debug -Message "Event source '$SourceIdentifier' already registered"
                return
            }
            
            try {
                Register-EngineEvent -SourceIdentifier $SourceIdentifier -Action {}
                [void]$this.RegisteredSources.Add($SourceIdentifier)
                Write-Log -Level Debug -Message "Registered event source: $SourceIdentifier"
            }
            catch {
                Write-Log -Level Error -Message "Failed to register event source '$SourceIdentifier': $($_.Exception.Message)"
                throw
            }
        }
        $eventSystem | Add-Member -MemberType ScriptMethod -Name RegisterSource -Value $registerSourceScript
        
        # Add method for publishing events
        $publishEventScript = {
            param(
                [string]$SourceIdentifier,
                [string]$EventIdentifier,
                [object]$EventData = $null
            )
            
            if ([string]::IsNullOrWhiteSpace($SourceIdentifier)) {
                throw "SourceIdentifier cannot be null or empty"
            }
            if ([string]::IsNullOrWhiteSpace($EventIdentifier)) {
                throw "EventIdentifier cannot be null or empty"
            }
            
            try {
                $eventArgs = @{
                    SourceIdentifier = $SourceIdentifier
                    EventIdentifier = $EventIdentifier
                    Sender = $SourceIdentifier
                    EventArguments = @($EventData)
                }
                
                New-Event @eventArgs
                Write-Log -Level Trace -Message "Published event: $SourceIdentifier.$EventIdentifier"
            }
            catch {
                Write-Log -Level Error -Message "Failed to publish event '$SourceIdentifier.$EventIdentifier': $($_.Exception.Message)"
                throw
            }
        }
        $eventSystem | Add-Member -MemberType ScriptMethod -Name PublishEvent -Value $publishEventScript
        
        # Add method for subscribing to events
        $subscribeToEventScript = {
            param(
                [string]$SourceIdentifier,
                [string]$EventIdentifier,
                [scriptblock]$Action,
                [string]$SubscriptionName = $null
            )
            
            if ([string]::IsNullOrWhiteSpace($SourceIdentifier)) {
                throw "SourceIdentifier cannot be null or empty"
            }
            if ([string]::IsNullOrWhiteSpace($EventIdentifier)) {
                throw "EventIdentifier cannot be null or empty"
            }
            if (-not $Action) {
                throw "Action scriptblock cannot be null"
            }
            
            try {
                $subscription = Register-ObjectEvent -InputObject $SourceIdentifier -EventName $EventIdentifier -Action $Action
                if ($SubscriptionName) {
                    $subscription | Add-Member -MemberType NoteProperty -Name "FriendlyName" -Value $SubscriptionName
                }
                
                [void]$this.ActiveSubscriptions.Add($subscription)
                Write-Log -Level Debug -Message "Created event subscription: $SourceIdentifier.$EventIdentifier"
                return $subscription
            }
            catch {
                Write-Log -Level Error -Message "Failed to subscribe to event '$SourceIdentifier.$EventIdentifier': $($_.Exception.Message)"
                throw
            }
        }
        $eventSystem | Add-Member -MemberType ScriptMethod -Name SubscribeToEvent -Value $subscribeToEventScript
        
        # Add cleanup method
        $cleanupScript = {
            Write-Log -Level Debug -Message "Cleaning up Helios Event System..."
            
            foreach ($subscription in $this.ActiveSubscriptions) {
                try {
                    Unregister-Event -SubscriptionId $subscription.Id -ErrorAction SilentlyContinue
                }
                catch {
                    Write-Log -Level Warn -Message "Failed to unregister subscription $($subscription.Id): $($_.Exception.Message)"
                }
            }
            $this.ActiveSubscriptions.Clear()
            
            foreach ($source in $this.RegisteredSources) {
                try {
                    Get-Event -SourceIdentifier $source -ErrorAction SilentlyContinue | Remove-Event -ErrorAction SilentlyContinue
                }
                catch {
                    Write-Log -Level Warn -Message "Failed to cleanup events for source '$source': $($_.Exception.Message)"
                }
            }
            $this.RegisteredSources.Clear()
            
            Write-Log -Level Debug -Message "Event system cleanup completed"
        }
        $eventSystem | Add-Member -MemberType ScriptMethod -Name Cleanup -Value $cleanupScript
        
        Write-Log -Level Info -Message "Helios Event System initialized successfully"
        return $eventSystem
    }
}

function Publish-HeliosEvent {
    <#
    .SYNOPSIS
        Publishes an event through the Helios event system.
    .DESCRIPTION
        Convenience function for publishing events. Services should use this to announce state changes.
    .PARAMETER SourceIdentifier
        The source that is publishing the event (typically the service name)
    .PARAMETER EventIdentifier
        The specific event being published
    .PARAMETER EventData
        Optional data to include with the event
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceIdentifier,
        
        [Parameter(Mandatory = $true)]
        [string]$EventIdentifier,
        
        [Parameter()]
        [object]$EventData = $null
    )
    
    Invoke-WithErrorHandling -Component "Publish-HeliosEvent" -Context @{ Source = $SourceIdentifier; Event = $EventIdentifier } -ScriptBlock {
        $eventArgs = @{
            SourceIdentifier = $SourceIdentifier
            EventIdentifier = $EventIdentifier
            Sender = $SourceIdentifier
            EventArguments = @($EventData)
        }
        
        New-Event @eventArgs
        Write-Log -Level Trace -Message "Event published: $SourceIdentifier.$EventIdentifier"
    }
}

function Subscribe-HeliosEvent {
    <#
    .SYNOPSIS
        Subscribes to an event in the Helios event system.
    .DESCRIPTION
        Convenience function for subscribing to events. UI components should use this to react to service state changes.
    .PARAMETER SourceIdentifier
        The source to subscribe to
    .PARAMETER EventIdentifier
        The specific event to subscribe to
    .PARAMETER Action
        The scriptblock to execute when the event occurs
    .PARAMETER SubscriptionName
        Optional friendly name for the subscription
    .OUTPUTS
        [System.Management.Automation.PSEventJob] The event subscription object
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSEventJob])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceIdentifier,
        
        [Parameter(Mandatory = $true)]
        [string]$EventIdentifier,
        
        [Parameter(Mandatory = $true)]
        [scriptblock]$Action,
        
        [Parameter()]
        [string]$SubscriptionName = $null
    )
    
    Invoke-WithErrorHandling -Component "Subscribe-HeliosEvent" -Context @{ Source = $SourceIdentifier; Event = $EventIdentifier } -ScriptBlock {
        $subscription = Register-ObjectEvent -InputObject $SourceIdentifier -EventName $EventIdentifier -Action $Action
        
        if ($SubscriptionName) {
            $subscription | Add-Member -MemberType NoteProperty -Name "FriendlyName" -Value $SubscriptionName -Force
        }
        
        Write-Log -Level Debug -Message "Event subscription created: $SourceIdentifier.$EventIdentifier"
        return $subscription
    }
}

#endregion

#region Export Module Members

Export-ModuleMember -Function @(
    'Initialize-HeliosEventSystem',
    'Publish-HeliosEvent', 
    'Subscribe-HeliosEvent'
)

#endregion