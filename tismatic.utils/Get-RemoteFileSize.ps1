function Get-RemoteFileSize {
    param(
        $URL
    )
    $url = $URL
    $response = Invoke-WebRequest -Uri $url -Method Head
    $sizeInBytes = $response.Headers['Content-Length']

    $SizeInBytes | Format-Size

}