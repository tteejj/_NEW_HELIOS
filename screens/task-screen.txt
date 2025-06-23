#
# MODULE: screens/task-screen.psm1
#
# PURPOSE:
#   Provides the user interface for managing tasks. This screen allows users to
#   view a list of all tasks, create new tasks, and edit existing tasks. It follows
#   a two-panel design, switching between a task list view and a task entry form.
#   It interacts directly with the TaskService to manage state and subscribes to
#   service events to automatically refresh its display.
#

using module "$PSScriptRoot/../modules/logger.psm1"
using module "$PSScriptRoot/../modules/exceptions.psm1"
using module "$PSScriptRoot/../ui/helios-components.psm1"
using module "$PSScriptRoot/../ui/helios-panels.psm1"
# NOTE: The 'New-HeliosDataTable' component is assumed to exist in the component library
# with the following API:
# - Props: Columns (array), Data (array), OnAction (scriptblock)
# - Properties: SelectedItem
# - Methods: UpdateData([array]$newData)

#region Factory Function

function Get-HeliosTaskScreen {
    <#
    .SYNOPSIS
        Creates a new Task Management screen object.
    .DESCRIPTION
        This factory function builds and returns a PSCustomObject representing the task screen,
        complete with its UI layout, methods, and internal state, ready to be pushed
        onto the TUI engine's screen stack.
    .OUTPUTS
        [PSCustomObject] The initialized screen object.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    Write-Log -Level Trace -Message "Creating Helios Task Screen object."

    $screen = [PSCustomObject]@{
        Name                  = "HeliosTaskScreen"
        _services             = $null
        _eventSubscriptions   = [System.Collections.ArrayList]@()
        _rootPanel            = $null
        _listPanel            = $null
        _formPanel            = $null
        _dataTable            = $null
        _formFields           = @{}
        _editingTask          = $null # Stores the task being edited, or $null for a new task
    }

    #================================================================================
    # Private Methods
    #================================================================================

    $buildUiScript = {
        Write-Log -Level Debug -Message "Building UI for Task Screen."

        # --- List Panel (Visible by default) ---
        $this._dataTable = New-HeliosDataTable -Props @{
            Name    = "TaskDataTable"
            Columns = @(
                @{ Name = "Title";       Expression = { $_.title };       Width = 40 },
                @{ Name = "Status";      Expression = { if ($_.completed) { "Done" } else { "Pending" } }; Width = 10 },
                @{ Name = "Priority";    Expression = { $_.priority };    Width = 10 },
                @{ Name = "Due Date";    Expression = { if ($_.due_date) { Get-Date($_.due_date) -format 'yyyy-MM-dd' } else { 'N/A' } }; Width = 12 }
            )
            # The 'OnAction' handler is triggered by keys like Enter, 'e', 'd' within the component
            OnAction = {
                param($action, $item)
                switch ($action) {
                    'select' { $this._EditTask($item) }
                    'delete' { $this._DeleteTask($item) }
                }
            }
        }

        $listFooter = New-HeliosLabel -Props @{
            Name = "TaskListFooter"
            Text = "N: New | E: Edit | Del: Delete | Esc: Back"
        }

        $this._listPanel = New-HeliosStackPanel -Props @{
            Name        = "TaskListPanel"
            Orientation = 'Vertical'
            Spacing     = 1
        }
        $this._listPanel.AddChild($this._dataTable, @{ 'Grid.Row' = 0 })
        $this._listPanel.AddChild($listFooter, @{ 'Grid.Row' = 1 })


        # --- Form Panel (Hidden by default) ---
        $formTitleLabel = New-HeliosLabel -Props @{ Text = "Title:" }
        $formTitleBox = New-HeliosTextBox -Props @{ Name = "TaskFormTitle"; Width = 50 }
        $this._formFields.Title = $formTitleBox

        $formDescLabel = New-HeliosLabel -Props @{ Text = "Description:" }
        $formDescBox = New-HeliosTextArea -Props @{ Name = "TaskFormDescription"; Width = 50; Height = 5 }
        $this._formFields.Description = $formDescBox

        $saveButton = New-HeliosButton -Props @{
            Name    = "TaskFormSaveButton"
            Text    = "Save"
            Width   = 8
            OnClick = { $this._SaveTask() }
        }
        $cancelButton = New-HeliosButton -Props @{
            Name    = "TaskFormCancelButton"
            Text    = "Cancel"
            Width   = 10
            OnClick = { $this._ShowListPanel() }
        }
        $buttonPanel = New-HeliosStackPanel -Props @{
            Orientation         = 'Horizontal'
            Spacing             = 2
            HorizontalAlignment = 'Left'
        }
        $buttonPanel.AddChild($saveButton)
        $buttonPanel.AddChild($cancelButton)

        $this._formPanel = New-HeliosStackPanel -Props @{
            Name       = "TaskFormPanel"
            Spacing    = 1
            Visible    = $false
            ShowBorder = $true
            Title      = " Edit Task "
            Padding    = 1
        }
        $this._formPanel.AddChild($formTitleLabel)
        $this._formPanel.AddChild($formTitleBox)
        $this._formPanel.AddChild($formDescLabel)
        $this._formPanel.AddChild($formDescBox)
        $this._formPanel.AddChild($buttonPanel)


        # --- Root Panel ---
        $this._rootPanel = New-HeliosGridPanel -Props @{
            Name              = "TaskScreenRoot"
            Width             = $global:TuiState.BufferWidth
            Height            = $global:TuiState.BufferHeight
            RowDefinitions    = @("1*", "Auto") # DataTable gets remaining space, footer is auto-sized
            ColumnDefinitions = @("1*")
            Padding           = 1
        }
        # Add both panels to the root. Their visibility will determine which is shown.
        $this._rootPanel.AddChild($this._listPanel)
        $this._rootPanel.AddChild($this._formPanel)
    }
    $screen | Add-Member -MemberType ScriptMethod -Name _BuildUI -Value $buildUiScript

    $refreshTaskListScript = {
        Invoke-WithErrorHandling -Component "$($this.Name)._RefreshTaskList" -Context @{} -ScriptBlock {
            Write-Log -Level Debug -Message "Refreshing task list data on screen."
            $tasks = $this._services.Task.GetTasks()
            $this._dataTable.UpdateData($tasks)
            Request-TuiRefresh
        }
    }
    $screen | Add-Member -MemberType ScriptMethod -Name _RefreshTaskList -Value $refreshTaskListScript

    $showListPanelScript = {
        Invoke-WithErrorHandling -Component "$($this.Name)._ShowListPanel" -Context @{} -ScriptBlock {
            Write-Log -Level Debug -Message "Switching to Task List Panel."
            $this._formPanel.Hide()
            $this._listPanel.Show()
            Request-Focus -Component $this._dataTable
            Request-TuiRefresh
        }
    }
    $screen | Add-Member -MemberType ScriptMethod -Name _ShowListPanel -Value $showListPanelScript

    $showFormPanelScript = {
        Invoke-WithErrorHandling -Component "$($this.Name)._ShowFormPanel" -Context @{} -ScriptBlock {
            Write-Log -Level Debug -Message "Switching to Task Form Panel."
            $this._listPanel.Hide()
            $this._formPanel.Show()

            # Populate form based on whether we are editing or creating a new task
            if ($this._editingTask) {
                $this._formPanel.Title = " Edit Task "
                $this._formFields.Title.Text = $this._editingTask.title
                $this._formFields.Description.Text = $this._editingTask.description
            }
            else {
                $this._formPanel.Title = " New Task "
                $this._formFields.Title.Text = ""
                $this._formFields.Description.Text = ""
            }
            # The description is a multi-line text area, we need to update its internal lines as well.
            $this._formFields.Description.Lines = $this._formFields.Description.Text -split "`n"

            Request-Focus -Component $this._formFields.Title
            Request-TuiRefresh
        }
    }
    $screen | Add-Member -MemberType ScriptMethod -Name _ShowFormPanel -Value $showFormPanelScript

    $newTaskScript = {
        Invoke-WithErrorHandling -Component "$($this.Name)._NewTask" -Context @{} -ScriptBlock {
            Write-Log -Level Info -Message "User initiated new task entry."
            $this._editingTask = $null
            $this._ShowFormPanel()
        }
    }
    $screen | Add-Member -MemberType ScriptMethod -Name _NewTask -Value $newTaskScript

    $editTaskScript = {
        param([hashtable]$Task)
        Invoke-WithErrorHandling -Component "$($this.Name)._EditTask" -Context @{ TaskId = $Task.id } -ScriptBlock {
            $taskToEdit = $Task
            if (-not $taskToEdit) {
                $taskToEdit = $this._dataTable.SelectedItem
            }
            if (-not $taskToEdit) {
                Write-Log -Level Warn -Message "Edit action triggered, but no task is selected."
                # Optionally show an alert dialog here
                return
            }
            Write-Log -Level Info -Message "User initiated edit for task: $($taskToEdit.id)"
            $this._editingTask = $taskToEdit
            $this._ShowFormPanel()
        }
    }
    $screen | Add-Member -MemberType ScriptMethod -Name _EditTask -Value $editTaskScript

    $deleteTaskScript = {
        param([hashtable]$Task)
        Invoke-WithErrorHandling -Component "$($this.Name)._DeleteTask" -Context @{ TaskId = $Task.id } -ScriptBlock {
            $taskToDelete = $Task
            if (-not $taskToDelete) {
                $taskToDelete = $this._dataTable.SelectedItem
            }
            if (-not $taskToDelete) {
                Write-Log -Level Warn -Message "Delete action triggered, but no task is selected."
                return
            }

            Show-ConfirmDialog -Title "Delete Task" `
                -Message "Are you sure you want to delete task '$($taskToDelete.title)'?" `
                -OnConfirm {
                    Write-Log -Level Info -Message "User confirmed deletion of task: $($taskToDelete.id)"
                    $this._services.Task.DeleteTask($taskToDelete.id)
                    # The UI will refresh automatically via the Tasks.Changed event
                }
        }
    }
    $screen | Add-Member -MemberType ScriptMethod -Name _DeleteTask -Value $deleteTaskScript

    $saveTaskScript = {
        Invoke-WithErrorHandling -Component "$($this.Name)._SaveTask" -Context @{ IsEditing = ($null -ne $this._editingTask) } -ScriptBlock {
            $updates = @{
                Title       = $this._formFields.Title.Text
                Description = $this._formFields.Description.Text
            }

            if ($this._editingTask) {
                # Update existing task
                Write-Log -Level Info -Message "Saving updates for task: $($this._editingTask.id)"
                $this._services.Task.UpdateTask($this._editingTask.id, $updates)
            }
            else {
                # Add new task
                Write-Log -Level Info -Message "Saving new task with title: $($updates.Title)"
                $this._services.Task.AddTask($updates)
            }
            # The UI will refresh automatically via the Tasks.Changed event.
            # We just need to switch back to the list view.
            $this._ShowListPanel()
        }
    }
    $screen | Add-Member -MemberType ScriptMethod -Name _SaveTask -Value $saveTaskScript

    #================================================================================
    # Public Methods (Screen Lifecycle)
    #================================================================================

    $initScript = {
        param(
            [Parameter(Mandatory = $true)]
            [hashtable]$services
        )
        Invoke-WithErrorHandling -Component "$($this.Name).Init" -Context @{} -ScriptBlock {
            Write-Log -Level Info -Message "Initializing Task Screen."
            # Defensive programming: ensure required services are provided
            if (-not $services) { throw "Services hashtable cannot be null." }
            if (-not $services.Task) { throw "TaskService is missing from services." }
            if (-not $services.Keybinding) { throw "KeybindingService is missing from services." }

            $this._services = $services

            # Build the entire UI component tree for the screen
            $this._BuildUI()

            # Subscribe to TaskService events to keep the UI in sync with the state
            $eventHandler = {
                # This scriptblock runs when the 'Tasks.Changed' event is fired
                Write-Log -Level Trace -Message "TaskScreen received 'Tasks.Changed' event."
                $this._RefreshTaskList()
            }
            $subscription = Register-EngineEvent -SourceIdentifier 'TaskService' -EventIdentifier 'Tasks.Changed' -Action $eventHandler
            [void]$this._eventSubscriptions.Add($subscription)
            Write-Log -Level Debug -Message "TaskScreen subscribed to 'TaskService.Tasks.Changed' event."

            # Perform initial data load
            $this._RefreshTaskList()
        }
    }
    $screen | Add-Member -MemberType ScriptMethod -Name Init -Value $initScript

    $onExitScript = {
        Invoke-WithErrorHandling -Component "$($this.Name).OnExit" -Context @{} -ScriptBlock {
            Write-Log -Level Info -Message "Exiting Task Screen, unregistering event subscriptions."
            # CRITICAL: Clean up event subscriptions to prevent memory leaks
            foreach ($sub in $this._eventSubscriptions) {
                try {
                    Unregister-Event -SubscriptionId $sub.Id
                }
                catch {
                    Write-Log -Level Warn -Message "Failed to unregister event subscription $($sub.Id): $_"
                }
            }
            $this._eventSubscriptions.Clear()
        }
    }
    $screen | Add-Member -MemberType ScriptMethod -Name OnExit -Value $onExitScript

    $handleInputScript = {
        param(
            [Parameter(Mandatory = $true)]
            [System.Management.Automation.Host.KeyInfo]$Key
        )

        # Input is only handled at the screen level if the list panel is visible.
        # When the form panel is visible, its components (TextBox, Button) handle input.
        if (-not $this._listPanel.Visible) {
            return $false
        }

        Invoke-WithErrorHandling -Component "$($this.Name).HandleInput" -Context @{ Key = $Key.Key } -ScriptBlock {
            $keybindingSvc = $this._services.Keybinding
            if ($keybindingSvc.IsAction('list.new', $Key))    { $this._NewTask(); return $true }
            if ($keybindingSvc.IsAction('list.edit', $Key))   { $this._EditTask($null); return $true }
            if ($keybindingSvc.IsAction('list.delete', $Key)) { $this._DeleteTask($null); return $true }
            if ($keybindingSvc.IsAction('app.back', $Key))    { $this._services.Navigation.Back(); return $true }
        }
        return $false
    }
    $screen | Add-Member -MemberType ScriptMethod -Name HandleInput -Value $handleInputScript

    # The Render method for a screen is simple: it just renders its root panel.
    # The TUI engine will then recursively render the children of the root panel.
    $renderScript = {
        if ($this._rootPanel -and $this._rootPanel.PSObject.Methods['Render']) {
            $this._rootPanel.Render()
        }
    }
    $screen | Add-Member -MemberType ScriptMethod -Name Render -Value $renderScript

    # Expose the root panel for the TUI engine and focus manager
    $screen.PSObject.Properties.Add([psnoteproperty]::new('RootPanel', $screen._rootPanel))

    return $screen
}

Export-ModuleMember -Function Get-HeliosTaskScreen

#endregion