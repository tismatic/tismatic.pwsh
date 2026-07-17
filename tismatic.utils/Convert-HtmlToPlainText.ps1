function Convert-HtmlToPlainText {
    [CmdletBinding()]
    param (
        [Parameter(
            Mandatory,
            ValueFromPipeline
        )]
        [AllowEmptyString()]
        [string]$Html,

        [switch]$Pretty,

        # Removes this marker and everything after it.
        [string]$RemoveAfter
    )

    process {
        if ([string]::IsNullOrWhiteSpace($Html)) {
            return ''
        }

        $PlainText = $Html -replace "`r`n?", "`n"

        # Remove comments and non-visible content.
        $PlainText = $PlainText -replace '(?is)<!--.*?-->', ''
        $PlainText = $PlainText -replace '(?is)<(script|style|head|noscript|svg)\b[^>]*>.*?</\1\s*>', ''

        if ($Pretty) {
            # Line breaks
            $PlainText = $PlainText -replace '(?is)<br\s*/?>', "`n"

            # Tables
            $PlainText = $PlainText -replace '(?is)<tr\b[^>]*>', ''
            $PlainText = $PlainText -replace '(?is)</tr\s*>', "`n"
            $PlainText = $PlainText -replace '(?is)</t[dh]\s*>\s*<t[dh]\b[^>]*>', ': '
            $PlainText = $PlainText -replace '(?is)</?t[dh]\b[^>]*>', ''

            # Lists
            $PlainText = $PlainText -replace '(?is)<li\b[^>]*>', '* '
            $PlainText = $PlainText -replace '(?is)</li\s*>', "`n"

            # Block-level elements
            $PlainText = $PlainText -replace '(?is)</?(p|div|section|article|header|footer|blockquote|h[1-6]|ul|ol)\b[^>]*>', "`n"
        }
        else {
            $PlainText = $PlainText -replace '(?is)<br\s*/?>', ' '
            $PlainText = $PlainText -replace '(?is)</?(p|div|section|article|tr|li|h[1-6])\b[^>]*>', ' '
            $PlainText = $PlainText -replace '(?is)</t[dh]\s*>\s*<t[dh]\b[^>]*>', ': '
        }

        # Remove remaining tags.
        $PlainText = $PlainText -replace '(?is)<[^>]+>', ''

        # Decode named and numeric HTML entities.
        $PlainText = [System.Net.WebUtility]::HtmlDecode($PlainText)

        # Convert decoded non-breaking spaces into normal spaces.
        $PlainText = $PlainText -replace [char]0x00A0, ' '

        if ($RemoveAfter) {
            $EscapedMarker = [regex]::Escape($RemoveAfter)
            $PlainText = $PlainText -replace "(?is)$EscapedMarker.*$", ''
        }

        if ($Pretty) {
            $PlainText = $PlainText -replace '[ \t]+\n', "`n"
            $PlainText = $PlainText -replace '\n[ \t]+', "`n"
            $PlainText = $PlainText -replace '[ \t]{2,}', ' '
            $PlainText = $PlainText -replace '(?:\n\s*){3,}', "`n`n"
        }
        else {
            $PlainText = $PlainText -replace '\s+', ' '
            $PlainText = $PlainText -replace '\s+([,.;:!?])', '$1'
        }

        $PlainText.Trim()
    }
}