function Send-MgTeamsMessage {
    [CmdletBinding()]
    param (
        # Omit UserId or specify "me" to send to your Teams self-chat.
        [Parameter(Position = 0)]
        [Alias('Recipient')]
        [string]$UserId = 'me',

        [Parameter(Mandatory, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [ValidateSet('Text', 'Html')]
        [string]$ContentType = 'Text',

        [string]$AccessToken
    )

    $headers = @{
        'Content-Type' = 'application/json'
    }

    if ($AccessToken) {
        $headers.Authorization = "Bearer $AccessToken"
    }

    $requestParameters = @{
        Headers = $headers
    }

    # Resolve the signed-in user.
    $me = Invoke-MgRequest @requestParameters `
        -Method GET `
        -Uri 'https://graph.microsoft.com/v1.0/me'

    if (-not $me.id) {
        throw 'Could not resolve the current user through /me.'
    }

    $selfIdentifiers = @(
        'me'
        $me.id
        $me.userPrincipalName
        $me.mail
    ) | Where-Object { $_ }

    $isSelfChat = (
        [string]::IsNullOrWhiteSpace($UserId) -or
        $UserId -in $selfIdentifiers
    )

    if ($isSelfChat) {
        # Teams uses this special chat ID for "Chat with yourself."
        # It is not created through POST /chats.
        $target = $me

        $chat = [pscustomobject]@{
            id       = '48:notes'
            chatType = 'oneOnOne'
        }
    }
    else {
        $escapedUserId = [uri]::EscapeDataString($UserId)

        $target = Invoke-MgRequest @requestParameters `
            -Method GET `
            -Uri "https://graph.microsoft.com/v1.0/users/$escapedUserId"

        if (-not $target.id) {
            throw "Could not resolve user '$UserId'."
        }

        # Creating a normal one-on-one chat requires two members.
        # If it already exists, Graph returns the existing chat.
        $createBody = @{
            chatType = 'oneOnOne'
            members  = @(
                @{
                    '@odata.type'     = '#microsoft.graph.aadUserConversationMember'
                    roles             = @('owner')
                    'user@odata.bind' = "https://graph.microsoft.com/v1.0/users/$($me.id)"
                }
                @{
                    '@odata.type'     = '#microsoft.graph.aadUserConversationMember'
                    roles             = @('owner')
                    'user@odata.bind' = "https://graph.microsoft.com/v1.0/users/$($target.id)"
                }
            )
        }

        $chat = Invoke-MgRequest @requestParameters `
            -Method POST `
            -Uri 'https://graph.microsoft.com/v1.0/chats' `
            -Body $createBody

        if (-not $chat.id) {
            throw "Failed to obtain a one-on-one chat with '$UserId'."
        }
    }

    $payload = @{
        body = @{
            contentType = $ContentType.ToLowerInvariant()
            content     = $Message
        }
    }

    try {
        $msg = Invoke-MgRequest @requestParameters `
            -Method POST `
            -Uri "https://graph.microsoft.com/v1.0/chats/$($chat.id)/messages" `
            -Body $payload
    }
    catch {
        if ($isSelfChat) {
            throw @"
Unable to send the message to the Teams self-chat '48:notes'.

Open Microsoft Teams, select 'Chat with yourself', and send one message
manually to initialize the conversation. Then retry the command.

Graph error: $($_.Exception.Message)
"@
        }

        throw
    }

    if (-not $msg.id) {
        throw "The chat '$($chat.id)' was found, but the message was not created."
    }

    [pscustomobject]@{
        RecipientId          = $target.id
        RecipientDisplayName = $target.displayName
        IsSelfChat           = $isSelfChat
        ChatId               = $chat.id
        ChatType             = $chat.chatType
        MessageId            = $msg.id
        CreatedAt            = $msg.createdDateTime
        ContentType          = $ContentType
    }
}