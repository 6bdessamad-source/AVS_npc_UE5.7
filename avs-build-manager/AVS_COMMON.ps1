# Shared Windows PowerShell 5.1 helpers. Secrets remain local and are encrypted
# with DPAPI for this Windows account; never put a live config in GitHub.
function Quote-NativeArgument([string]$value) {
    if ($value -notmatch '[\s"]' -and $value.Length -gt 0) { return $value }
    $escaped = [regex]::Replace($value, '(\\*)"', '$1$1\"')
    $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')
    return '"' + $escaped + '"'
}
function Join-NativeArguments([string[]]$values) {
    return (($values | ForEach-Object { Quote-NativeArgument $_ }) -join ' ')
}
function Write-JsonUtf8([string]$path, $value) {
    $json = $value | ConvertTo-Json -Depth 12
    [IO.File]::WriteAllText($path, $json, (New-Object Text.UTF8Encoding($false)))
}
function Protect-LocalSecret([string]$value) {
    if (-not $value) { return '' }
    if ($value.StartsWith('dpapi:')) { return $value }
    return 'dpapi:' + (ConvertTo-SecureString $value -AsPlainText -Force | ConvertFrom-SecureString)
}
function Unprotect-LocalSecret([string]$value) {
    if (-not $value.StartsWith('dpapi:')) { return $value }
    $secure = ConvertTo-SecureString $value.Substring(6)
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
}
function Assert-StreamConfig($config) {
    foreach ($key in @('PlayerPort','StreamerPort')) {
        $number = 0
        if (-not [int]::TryParse([string]$config.$key, [ref]$number) -or $number -lt 1024 -or $number -gt 65535) { throw "$key must be between 1024 and 65535." }
    }
    if ($config.PlayerPort -eq $config.StreamerPort -or $config.PlayerPort -eq 8889 -or $config.StreamerPort -eq 8889) { throw 'Use distinct ports; 8889 is reserved for SFU.' }
    foreach ($key in @('ResX','ResY','FPS')) {
        $number = 0
        $maximum = if ($key -eq 'FPS') { 120 } else { 7680 }
        $minimum = if ($key -eq 'FPS') { 15 } else { 240 }
        if (-not [int]::TryParse([string]$config.$key, [ref]$number) -or $number -lt $minimum -or $number -gt $maximum) { throw "$key must be between $minimum and $maximum." }
    }
    if ($config.PublicPlayerUrl) {
        $uri = $null
        if (-not [Uri]::TryCreate([string]$config.PublicPlayerUrl, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -ne 'https' -or $uri.UserInfo) { throw 'Public player URL must be an https:// address without embedded credentials.' }
    }
    foreach ($pair in @(@('StunUrl','^stuns?:\S+$'), @('TurnUrl','^turns?:\S+$'))) {
        if ($config.($pair[0]) -and [string]$config.($pair[0]) -notmatch $pair[1]) { throw "Invalid $($pair[0]) URL." }
    }
    if ([string]$config.WebsiteUrl -notmatch '^https://') { throw 'WebsiteUrl must use HTTPS.' }
}
