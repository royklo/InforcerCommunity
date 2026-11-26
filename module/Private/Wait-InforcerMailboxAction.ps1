function Wait-InforcerMailboxAction {
    # Polls a queued mailbox action until Exchange Online reports succeeded or failed.
    # A failed action is an error, and so is one still running at the deadline: a later step (a licence
    # removal) must not run before Exchange has confirmed this one.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$UserEndpoint,
        [Parameter(Mandatory)][string]$ActionId,
        [Parameter(Mandatory)][string]$Step,
        [Parameter(Mandatory)][string]$UserId,
        [int]$TimeoutSeconds = 300
    )
    $endpoint = "$UserEndpoint/mailbox/actions/$([System.Uri]::EscapeDataString($ActionId))"
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $interval = 2
    $status = 'queued'
    try {
        while ($status -notin 'succeeded', 'failed') {
            if ((Get-Date) -ge $deadline) {
                Write-Error -Message "The request to $Step for user $UserId is still $status after $TimeoutSeconds seconds, so the steps after it were not run. Exchange Online carries on in the background (action id $ActionId); check it with Get-InforcerUser -IncludeMailbox before running the rest again." -ErrorId 'MailboxActionTimedOut' -Category OperationTimeout
                return
            }
            Write-Progress -Activity "Mailbox of user $UserId" -Status "${Step}: $status"
            Start-Sleep -Seconds $interval
            $interval = [Math]::Min($interval * 2, 15)
            $actionErr = $null
            $action = Invoke-InforcerApiRequest -Endpoint $endpoint -Method GET -ErrorVariable actionErr -ErrorAction SilentlyContinue
            if ($actionErr) {
                Write-Error -Message "The request to $Step was queued (action id $ActionId), but its progress could not be read. $($actionErr[-1].Exception.Message)" -ErrorId 'MailboxActionUnknown' -Category $actionErr[-1].CategoryInfo.Category
                return
            }
            $status = $action.status
        }
    } finally {
        Write-Progress -Activity "Mailbox of user $UserId" -Completed
    }
    if ($status -eq 'failed') {
        Write-Error -Message "Exchange Online could not apply it: $($action.error.message) ($($action.error.code))." -ErrorId 'MailboxActionFailed' -Category InvalidResult
    }
}
