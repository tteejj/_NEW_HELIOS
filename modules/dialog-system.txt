#
# MODULE: modules/dialog-system.psm1
#
# PURPOSE:
#   Manages the creation, display, and interaction of modal dialogs. This system
#   constructs dialogs using Helios components and intercepts all user input
#   while a dialog is active, ensuring a modal experience.
#
# ARCHITECTURE:
#   - This module maintains a private state object, $DialogSystem, which holds a
#     stack of active dialogs.
#   - Public functions like `Show-ConfirmDialog` and `Show-AlertDialog` act as
#     factories, composing Helios panels and components to build the dialog UI.
#   - When a dialog is shown, this system takes control of focus, managing a
#     temporary tab order for the dialog's components. It restores the previous
#     focus state when the dialog is closed.
#   - The TUI Engine interacts with this module via two hooks:
#     - `Get-ActiveDialog()`: To get the dialog's root panel for rendering.
#     - `Handle-DialogInput()`: To pass keyboard input for processing.
#

using module "$PSScriptRoot/logger.psm1"
using module "$PSScriptRoot/exceptions.psm1"
using module "$PSScriptRoot/../ui/helios-components.psm1"
using module "$PSScriptRoot/../ui/helios-panels.psm1"
using module "$PSScriptRoot/focus-manager.psm1" # For Get-FocusedComponent, Request-Focus

#region Private State
# ------------------------------------------------------------------------------
# Private state for the Dialog System.
# ------------------------------------------------------------------------------

$DialogSystem = [PSCustomObject]@{
    # A stack to manage nested dialogs.
    DialogStack = [System.Collections.Stack]::new()

    # The root panel of the currently visible dialog.
    CurrentDialog = $null

    # The component that was focused on the main screen before the dialog appeared.
    PreviousFocusedComponent = $null

    # A temporary, ordered list of focusable components within the active dialog.
    DialogTabOrder = [System.Collections.Generic.List[object]]::new()
}
#endregion

#region Private Functions
# ------------------------------------------------------------------------------
# Internal helper functions for managing dialog state and focus.
# ------------------------------------------------------------------------------

function Find-DialogFocusableComponents {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$RootComponent
    )
    # This is a local reimplementation of the same logic in focus-manager.psm1,
    # specifically for traversing a dialog's component tree.
    $focusable = [System.Collections.Generic.List[object]]::new()
    $queue = [System.Collections.Generic.Queue[object]]::new()
    $queue.Enqueue($RootComponent)

    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        if (-not $current) { continue }

        if ($current.PSObject.Properties['IsFocusable'] -and $current.IsFocusable -and $current.PSObject.Properties['Visible'] -and $current.Visible) {
            $focusable.Add($current)
        }

        if ($current.PSObject.Properties['Children']) {
            foreach ($child in $current.Children) {
                $queue.Enqueue($child)
            }
        }
    }
    return $focusable
}

function Show-ActiveDialog {
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$DialogPanel
    )

    Invoke-WithErrorHandling -Component 'DialogSystem.ShowActiveDialog' -Context @{ DialogType = $DialogPanel.Name } -ScriptBlock {
        Write-Log -Level Debug -Message "Showing dialog '$($DialogPanel.Name)'"

        # If another dialog is already active, push it onto the stack.
        if ($DialogSystem.CurrentDialog) {
            $DialogSystem.DialogStack.Push($DialogSystem.CurrentDialog)
        }
        else {
            # This is the first dialog being shown, save the screen's focus state.
            $DialogSystem.PreviousFocusedComponent = Get-FocusedComponent
        }

        # Take over focus from the main screen.
        Request-Focus -Component $null -Reason 'DialogShown'

        $DialogSystem.CurrentDialog = $DialogPanel

        # Build the tab order for the new dialog.
        $DialogSystem.DialogTabOrder.Clear()
        $focusableComponents = Find-DialogFocusableComponents -RootComponent $DialogPanel
        $DialogSystem.DialogTabOrder.AddRange($focusableComponents)
        Write-Log -Level Trace -Message "Dialog has $($DialogSystem.DialogTabOrder.Count) focusable components."

        # Focus the first component in the dialog.
        if ($DialogSystem.DialogTabOrder.Count -gt 0) {
            Request-Focus -Component $DialogSystem.DialogTabOrder[0] -Reason 'DialogInitialFocus'
        }

        # The TUI Engine needs to be told to redraw.
        Request-TuiRefresh
    }
}

function Close-ActiveDialog {
    Invoke-WithErrorHandling -Component 'DialogSystem.CloseActiveDialog' -Context @{} -ScriptBlock {
        Write-Log -Level Debug -Message "Closing active dialog."
        $closedDialog = $DialogSystem.CurrentDialog

        # Blur whatever was focused in the dialog.
        Request-Focus -Component $null -Reason 'DialogClosed'
        $DialogSystem.DialogTabOrder.Clear()

        if ($DialogSystem.DialogStack.Count -gt 0) {
            # There's another dialog on the stack, so show it instead.
            $nextDialog = $DialogSystem.DialogStack.Pop()
            Show-ActiveDialog -DialogPanel $nextDialog
        }
        else {
            # No more dialogs, return control to the main screen.
            $DialogSystem.CurrentDialog = $null
            Write-Log -Level Debug -Message "Dialog stack is empty. Restoring screen focus."

            # Restore focus to the component that was active before the first dialog appeared.
            if ($DialogSystem.PreviousFocusedComponent) {
                Request-Focus -Component $DialogSystem.PreviousFocusedComponent -Reason 'RestoreScreenFocus'
                $DialogSystem.PreviousFocusedComponent = $null
            }
            Request-TuiRefresh
        }
    }
}

#endregion

#region Public API - Dialog Factories
# ------------------------------------------------------------------------------
# Exported functions to create and show standard dialog types.
# ------------------------------------------------------------------------------

function Show-ConfirmDialog {
    <#
    .SYNOPSIS
        Displays a modal confirmation dialog with 'Yes' and 'No' buttons.
    .PARAMETER Title
        The title to display in the dialog's border.
    .PARAMETER Message
        The confirmation message to display to the user.
    .PARAMETER OnConfirm
        A scriptblock to execute when the 'Yes' button is clicked.
    .PARAMETER OnCancel
        A scriptblock to execute when the 'No' button is clicked or Esc is pressed.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $true)]
        [scriptblock]$OnConfirm,

        [scriptblock]$OnCancel = { }
    )

    Invoke-WithErrorHandling -Component 'DialogSystem.ShowConfirmDialog' -Context @{ Title = $Title; Message = $Message } -ScriptBlock {
        # Define actions for the buttons. They must close the dialog first.
        $onYesClick = {
            Close-ActiveDialog
            & $OnConfirm
        }
        $onNoClick = {
            Close-ActiveDialog
            & $OnCancel
        }

        # Create UI components
        $messageLabel = New-HeliosLabel -Props @{
            Text   = $Message
            Width  = 50 # Let the panel manage this
            Height = 1
        }

        $yesButton = New-HeliosButton -Props @{
            Name    = 'ConfirmDialogYesButton'
            Text    = 'Yes'
            Width   = 7
            OnClick = $onYesClick
        }

        $noButton = New-HeliosButton -Props @{
            Name    = 'ConfirmDialogNoButton'
            Text    = 'No'
            Width   = 6
            OnClick = $onNoClick
        }

        $buttonPanel = New-HeliosStackPanel -Props @{
            Name                = 'ConfirmDialogButtonPanel'
            Orientation         = 'Horizontal'
            Spacing             = 2
            HorizontalAlignment = 'Center'
            Height              = 3
        }
        $buttonPanel.AddChild($yesButton)
        $buttonPanel.AddChild($noButton)

        $dialogPanel = New-HeliosStackPanel -Props @{
            Name       = 'ConfirmDialogPanel'
            Width      = 60
            Height     = 10
            ShowBorder = $true
            Title      = " $Title "
            Padding    = 1
            Spacing    = 2
        }
        $dialogPanel.AddChild($messageLabel)
        $dialogPanel.AddChild($buttonPanel)

        # Show the composed dialog
        Show-ActiveDialog -DialogPanel $dialogPanel
    }
}

function Show-AlertDialog {
    <#
    .SYNOPSIS
        Displays a modal alert dialog with a single 'OK' button.
    .PARAMETER Title
        The title to display in the dialog's border.
    .PARAMETER Message
        The alert message to display to the user.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )
    Invoke-WithErrorHandling -Component 'DialogSystem.ShowAlertDialog' -Context @{ Title = $Title; Message = $Message } -ScriptBlock {
        # The OK button simply closes the dialog.
        $onOkClick = { Close-ActiveDialog }

        # Create UI components
        $messageLabel = New-HeliosLabel -Props @{
            Text = $Message
        }

        $okButton = New-HeliosButton -Props @{
            Name    = 'AlertDialogOkButton'
            Text    = 'OK'
            Width   = 6
            OnClick = $onOkClick
        }

        $buttonPanel = New-HeliosStackPanel -Props @{
            Name                = 'AlertDialogButtonPanel'
            Orientation         = 'Horizontal'
            HorizontalAlignment = 'Center'
            Height              = 3
        }
        $buttonPanel.AddChild($okButton)

        $dialogPanel = New-HeliosStackPanel -Props @{
            Name       = 'AlertDialogPanel'
            Width      = 60
            Height     = 10
            ShowBorder = $true
            Title      = " $Title "
            Padding    = 1
            Spacing    = 2
        }
        $dialogPanel.AddChild($messageLabel)
        $dialogPanel.AddChild($buttonPanel)

        # Show the composed dialog
        Show-ActiveDialog -DialogPanel $dialogPanel
    }
}
#endregion

#region Engine Hooks
# ------------------------------------------------------------------------------
# Functions for the TUI Engine to call during its main loop.
# ------------------------------------------------------------------------------

function Get-ActiveDialog {
    <#
    .SYNOPSIS
        (Engine Hook) Gets the root component of the currently active dialog.
    .DESCRIPTION
        The TUI Engine calls this during each render pass. If a dialog is active,
        the engine will render its component tree on top of the current screen.
    .OUTPUTS
        [PSCustomObject] The root panel of the active dialog, or $null if none.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    return $DialogSystem.CurrentDialog
}

function Handle-DialogInput {
    <#
    .SYNOPSIS
        (Engine Hook) Processes keyboard input if a dialog is active.
    .DESCRIPTION
        The TUI Engine calls this at the beginning of its input handling logic.
        If a dialog is active, this function consumes the input, handles focus
        navigation (Tab/Shift+Tab), and dispatches the key to the focused
        component within the dialog.
    .PARAMETER Key
        The [ConsoleKeyInfo] object representing the key press.
    .OUTPUTS
        [bool] Returns $true if the input was handled (i.e., a dialog was active),
               otherwise $false.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Host.KeyInfo]$Key
    )

    if (-not $DialogSystem.CurrentDialog) {
        return $false
    }

    Invoke-WithErrorHandling -Component 'DialogSystem.HandleDialogInput' -Context @{ Key = $Key.Key } -ScriptBlock {
        # Handle Tab navigation within the dialog
        if ($Key.Key -eq [ConsoleKey]::Tab) {
            $tabOrder = $DialogSystem.DialogTabOrder
            if ($tabOrder.Count -gt 0) {
                $currentFocused = Get-FocusedComponent
                $currentIndex = if ($currentFocused) { $tabOrder.IndexOf($currentFocused) } else { -1 }

                $increment = if ($Key.Modifiers -band [ConsoleModifiers]::Shift) { -1 } else { 1 }
                $nextIndex = ($currentIndex + $increment + $tabOrder.Count) % $tabOrder.Count

                Request-Focus -Component $tabOrder[$nextIndex] -Reason 'DialogTabNavigation'
            }
            return # We handled it, so exit the scriptblock
        }

        # Dispatch input to the currently focused component within the dialog
        $focusedComponent = Get-FocusedComponent
        if ($focusedComponent -and $focusedComponent.PSObject.ScriptMethods['HandleInput']) {
            # If the component's HandleInput returns $true, it handled the key.
            if ($focusedComponent.HandleInput($Key)) {
                return
            }
        }
    }

    # Always return true to signify that the dialog system consumed the input,
    # preventing it from "leaking" to the underlying screen.
    return $true
}

#endregion

Export-ModuleMember -Function Show-ConfirmDialog, Show-AlertDialog, Get-ActiveDialog, Handle-DialogInput