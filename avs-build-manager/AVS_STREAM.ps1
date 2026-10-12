param(
    [ValidateSet('Setup','StartGame','StartStream','Internet','Stop','OpenPlayer','Status')]
    [string]$Action = 'Status',
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'AVS_BuildManager.config.json'),
    [switch]$NoPause
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'AVS_COMMON.ps1')
$runtime = Join-Path $PSScriptRoot '.runtime'
$logs = Join-Path $PSScriptRoot 'StreamingLogs'
New-Item -ItemType Directory -Force -Path $runtime,$logs | Out-Null
$statePath = Join-Path $runtime 'session.json'
$state = @{ }
if (Test-Path $statePath) {
    $saved = Get-Content $statePath -Raw | ConvertFrom-Json
    foreach ($p in $saved.PSObject.Properties) { $state[$p.Name] = $p.Value }
}
function Save-State { Write-JsonUtf8 $statePath $state }
function Owned-Process($record) {
    if ($null -eq $record) { return $null }
    $process = Get-Process -Id $record.Id -ErrorAction SilentlyContinue
    if ($null -eq $process) { return $null }
    try {
        if ($process.StartTime.ToUniversalTime().ToString('o') -ne $record.StartTime -or
            $process.Path -ne $record.Path) { return $null }
        return $process
    } catch { return $null }
}
function Record-Process($process) {
    $process.Refresh()
    return @{ Id = $process.Id; StartTime = $process.StartTime.ToUniversalTime().ToString('o'); Path = $process.Path }
}
function Stop-Owned($key) {
    $process = Owned-Process $state[$key]
    if ($null -ne $process) {
        # Only stop the recorded process and its descendants, never all node/game processes.
        & taskkill.exe /PID $process.Id /T /F | Out-Host
        if ($LASTEXITCODE -ne 0 -and (Owned-Process $state[$key])) { throw "Could not stop $key. Close it manually and retry." }
    }
    $state.Remove($key)
    Save-State
}
function Start-Logged($exe, $arguments, $directory, $name) {
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
    $stdout = Join-Path $logs "$name-$stamp.stdout.log"
    $stderr = Join-Path $logs "$name-$stamp.stderr.log"
    $process = Start-Process -FilePath $exe -ArgumentList (Join-NativeArguments $arguments) -WorkingDirectory $directory -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $state[$name] = Record-Process $process
    $state["${name}Log"] = $stderr
    Save-State
    return $process
}
function Find-Tool($name) {
    $local = Join-Path $PSScriptRoot "tools\$name"
    if (Test-Path $local -PathType Leaf) { return $local }
    $command = Get-Command $name -ErrorAction SilentlyContinue
    if (-not $command) { throw "$name is missing. Run INSTALL_PREREQUISITES.bat, reopen the manager, and retry." }
    return $command.Source
}
function Wait-Port($port, $process) {
    $deadline = (Get-Date).AddSeconds(30)
    do {
        $process.Refresh()
        if ($process.HasExited) { throw "Signalling server exited. See $logs." }
        $client = New-Object System.Net.Sockets.TcpClient
        try {
            $pending = $client.BeginConnect('127.0.0.1', $port, $null, $null)
            if ($pending.AsyncWaitHandle.WaitOne(300)) { $client.EndConnect($pending); return }
        } catch { } finally { $client.Dispose() }
        Start-Sleep -Milliseconds 200
    } while ((Get-Date) -lt $deadline)
    throw "Signalling server did not open port $port within 30 seconds. See $logs."
}
function Resolve-Game {
    $path = [string]$config.GameExe
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or [IO.Path]::GetExtension($path) -ne '.exe') {
        throw 'Select the packaged game EXE in the Streaming tab. A patch ZIP by itself is not a playable game.'
    }
    $path = (Resolve-Path -LiteralPath $path).Path
    # Unreal bootstrap EXEs can exit after starting their child. Launch the actual
    # Shipping EXE directly so its lifetime can be tracked reliably.
    if ($path -notmatch '\\Binaries\\Win64\\') {
        $folder = Split-Path $path -Parent
        $projectName = [IO.Path]::GetFileNameWithoutExtension($path)
        $binaryDir = Join-Path $folder "$projectName\Binaries\Win64"
        if (Test-Path $binaryDir) {
            $candidates = @(Get-ChildItem -LiteralPath $binaryDir -Filter '*-Win64-Shipping.exe' -File)
            if ($candidates.Count -eq 1) { return $candidates[0].FullName }
        }
        throw 'Select the actual game EXE inside <packaged project>\Binaries\Win64 (usually *-Win64-Shipping.exe), rather than the top-level launcher.'
    }
    return $path
}
function Start-Game([bool]$streaming) {
    $existing = Owned-Process $state.Game
    if ($existing) {
        if ([bool]$state.Streaming -eq $streaming) { Write-Host 'The managed game is already running.'; return }
        throw 'Stop the managed session before switching between local play and streaming.'
    }
    $exe = Resolve-Game
    $argsList = @('-AudioMixer', '-ForceRes', "-ResX=$($config.ResX)", "-ResY=$($config.ResY)", "-ExecCmds=t.MaxFPS $($config.FPS)")
    if ($streaming) {
        $argsList += @('-RenderOffscreen', '-Unattended', "-PixelStreamingURL=ws://127.0.0.1:$($config.StreamerPort)", '-PixelStreamingID=AVS', "-PixelStreamingWebRTCMaxFps=$($config.FPS)")
    } else { $argsList += '-Windowed' }
    $game = Start-Logged $exe $argsList (Split-Path $exe -Parent) 'Game'
    $state.Streaming = $streaming
    Save-State
    Start-Sleep -Seconds 2
    $game.Refresh()
    if ($game.HasExited) { throw "The game exited during startup. See $logs and the game's Saved\Logs folder." }
    Write-Host "Game launched (PID $($game.Id))." -ForegroundColor Green
}
function Get-LanHost {
    if ($config.LanHost) {
        if ([string]$config.LanHost -notmatch '^[a-zA-Z0-9.-]+$') { throw 'LAN host must be an IPv4 address or hostname, without http:// or a port.' }
        return [string]$config.LanHost
    }
    $addresses = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object {
        $_.IPAddress -notmatch '^(127\.|169\.254\.)' -and $_.AddressState -eq 'Preferred'
    } | Sort-Object InterfaceMetric)
    if ($addresses.Count -gt 0) { return $addresses[0].IPAddress }
    return '127.0.0.1'
}
function Player-Page($address) {
    return $config.WebsiteUrl.TrimEnd('/') + '/?server=' + [Uri]::EscapeDataString($address)
}
function Active-PublicUrl {
    if ($config.PublicPlayerUrl) { return [string]$config.PublicPlayerUrl }
    if ((Owned-Process $state.Tunnel) -and $state.PublicUrl) { return [string]$state.PublicUrl }
    return ''
}
function Show-Links {
    $local = "http://$(Get-LanHost):$($config.PlayerPort)"
    $public = Active-PublicUrl
    Write-Host "LAN player: $local/player.html" -ForegroundColor Cyan
    Write-Host "GitHub page: $($config.WebsiteUrl)" -ForegroundColor Cyan
    $lines = @("LAN player: $local/player.html", "GitHub page: $($config.WebsiteUrl)")
    if ($public) {
        $share = Player-Page $public
        Write-Host "Laptop link: $share" -ForegroundColor Green
        $lines += "Laptop link: $share"
    }
    $lines | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'AVS_PLAYER_LINKS.txt') -Encoding UTF8
}
function Start-Server {
    if (Owned-Process $state.Server) { Write-Host 'Managed signalling server is already running.'; return }
    foreach ($port in @($config.PlayerPort, $config.StreamerPort)) {
        if (Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue) {
            throw "Port $port is already in use. Stop the old signalling server or change the port."
        }
    }
    $serverDir = Join-Path $config.InfrastructureRoot 'SignallingWebServer'
    $entry = Join-Path $serverDir 'dist\index.js'
    $www = Join-Path $serverDir 'www'
    if (-not (Test-Path $entry) -or -not (Test-Path (Join-Path $www 'player.html'))) { throw 'Run SETUP STREAMING first. The compiled server or player.html is missing.' }
    $ice = @()
    if ($config.StunUrl) { $ice += @{urls = @([string]$config.StunUrl)} }
    if ($config.TurnUrl) {
        if (-not $config.TurnUsername -or -not $config.TurnPassword) { throw 'TURN requires both username and password.' }
        $ice += @{urls = @([string]$config.TurnUrl); username = [string]$config.TurnUsername; credential = Unprotect-LocalSecret ([string]$config.TurnPassword)}
    }
    $peerFile = Join-Path $runtime 'peer-options.json'
    Write-JsonUtf8 $peerFile @{iceServers = $ice}
    # A fresh config avoids the uploaded config's hardcoded D: path and legacy redirects.
    $serverConfig = Join-Path $runtime 'signalling.json'
    Write-JsonUtf8 $serverConfig @{
        serve = $true; http_root = $www; homepage = 'player.html';
        player_port = $config.PlayerPort; streamer_port = $config.StreamerPort; sfu_port = 8889;
        https = $false; https_redirect = $false; rest_api = $false; stdin = $false;
        log_config = $false; console_messages = 'basic'; log_folder = $logs;
        peer_options_file = $peerFile; max_players = 1
    }
    $server = Start-Logged (Find-Tool 'node.exe') @($entry, '--config_file', $serverConfig) $serverDir 'Server'
    Wait-Port $config.PlayerPort $server
    Wait-Port $config.StreamerPort $server
    Write-Host 'Signalling server is listening. Waiting for the game to register is a separate step.' -ForegroundColor Green
}
function Check-Streamer {
    $ws = New-Object System.Net.WebSockets.ClientWebSocket
    $cancel = New-Object System.Threading.CancellationTokenSource
    $cancel.CancelAfter(12000)
    try {
        $ws.ConnectAsync([Uri]"ws://127.0.0.1:$($config.PlayerPort)", $cancel.Token).GetAwaiter().GetResult() | Out-Null
        $bytes = [Text.Encoding]::UTF8.GetBytes('{"type":"listStreamers"}')
        $send = New-Object 'System.ArraySegment[byte]' -ArgumentList @(,$bytes)
        $ws.SendAsync($send, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cancel.Token).GetAwaiter().GetResult() | Out-Null
        $buffer = New-Object byte[] 65536
        $segment = New-Object 'System.ArraySegment[byte]' -ArgumentList @(,$buffer)
        while (-not $cancel.IsCancellationRequested) {
            $message = ''
            do {
                $result = $ws.ReceiveAsync($segment, $cancel.Token).GetAwaiter().GetResult()
                if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) { return $false }
                $message += [Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count)
            } while (-not $result.EndOfMessage)
            $data = $message | ConvertFrom-Json
            if ($data.type -eq 'streamerList') { return (@($data.ids).Count -gt 0) }
        }
    } catch { return $false } finally { $ws.Dispose(); $cancel.Dispose() }
    return $false
}
function Setup-Streaming {
    if (Owned-Process $state.Server) { throw 'Stop streaming before rebuilding server files.' }
    $node = Find-Tool 'node.exe'
    $npm = Find-Tool 'npm.cmd'
    $nodeVersion = & $node --version
    if ([int]($nodeVersion.TrimStart('v').Split('.')[0]) -lt 22) { throw 'Install Node.js 22 or newer, reopen this manager, and retry.' }
    $root = [string]$config.InfrastructureRoot
    if (-not (Test-Path (Join-Path $root 'package.json'))) { throw 'Select the extracted PixelStreamingInfrastructure-UE5.7 folder.' }
    Push-Location $root
    $oldWebpack = $env:WEBPACK_OUTPUT_PATH
    try {
        $workspaces = @('Common','Signalling','SignallingWebServer','Frontend/library','Frontend/ui-library','Frontend/implementations/typescript')
        $install = @('install','--ignore-scripts','--no-audit','--no-fund','--include-workspace-root')
        foreach ($workspace in $workspaces) { $install += "--workspace=$workspace" }
        & $npm @install
        if ($LASTEXITCODE -ne 0) { throw 'npm install failed. Check this console and internet access.' }
        $env:WEBPACK_OUTPUT_PATH = Join-Path $root 'SignallingWebServer\www'
        $steps = @(
            @('Common','build:cjs'), @('Signalling','build:cjs'), @('SignallingWebServer','build'),
            @('Common','build:esm'), @('Frontend/library','build:esm'),
            @('Frontend/ui-library','build:esm'), @('Frontend/implementations/typescript','build:prod')
        )
        foreach ($step in $steps) {
            Write-Host "Building $($step[0])..." -ForegroundColor Cyan
            & $npm run $step[1] "--workspace=$($step[0])"
            if ($LASTEXITCODE -ne 0) { throw "Build failed: $($step[0])." }
        }
        if (-not (Test-Path (Join-Path $env:WEBPACK_OUTPUT_PATH 'player.html'))) { throw 'Frontend build did not create player.html.' }
        Write-Host 'Streaming setup completed. Enable Pixel Streaming 2 in Unreal before packaging the game.' -ForegroundColor Green
    } finally { $env:WEBPACK_OUTPUT_PATH = $oldWebpack; Pop-Location }
}
$mutex = New-Object Threading.Mutex($false, 'Local\AVSStreamingManagerV2')
$locked = $false
try {
    $locked = $mutex.WaitOne(0)
    if (-not $locked) { throw 'Another AVS streaming command is running. Wait for that command to finish.' }
    $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    if ($Action -ne 'Stop') { Assert-StreamConfig $config }
    switch ($Action) {
        'Setup' { Setup-Streaming }
        'StartGame' { Start-Game $false }
        'StartStream' {
            $null = Resolve-Game
            Start-Server
            Start-Game $true
            Show-Links
            if (Check-Streamer) { Write-Host 'Game registered as a streamer. Ready for a player.' -ForegroundColor Green }
            else { Write-Warning 'Server started, but no streamer is registered yet. Wait for game loading, then click CHECK STATUS. If the list remains empty, enable Pixel Streaming 2 and repackage your project.' }
        }
        'Internet' {
            if (-not (Owned-Process $state.Server) -or -not (Owned-Process $state.Game) -or -not $state.Streaming) { throw 'Click START STREAM first, then CREATE INTERNET LINK.' }
            $public = Active-PublicUrl
            if (-not $public) {
                $tunnel = Start-Logged (Find-Tool 'cloudflared.exe') @('tunnel','--url',"http://127.0.0.1:$($config.PlayerPort)") $PSScriptRoot 'Tunnel'
                $deadline = (Get-Date).AddSeconds(35)
                do {
                    $tunnel.Refresh()
                    if ($tunnel.HasExited) { throw 'HTTPS tunnel exited. See StreamingLogs.' }
                    $logText = Get-Content -LiteralPath $state.TunnelLog -Raw -ErrorAction SilentlyContinue
                    if ($logText -match 'https://[a-z0-9-]+\.trycloudflare\.com') { $public = $Matches[0]; break }
                    Start-Sleep -Milliseconds 500
                } while ((Get-Date) -lt $deadline)
                if (-not $public) { Stop-Owned 'Tunnel'; throw 'No HTTPS URL appeared within 35 seconds. Check tunnel logs, network access, and any existing cloudflared config.' }
                $state.PublicUrl = $public
                Save-State
            }
            if (-not $config.TurnUrl) { Write-Warning 'HTTPS carries signalling only. Internet video can fail behind NAT without a TURN relay. Configure TURN or use a VPN between laptop and rig.' }
            Write-Host 'The temporary URL gives access to your running game to anyone who has it. STOP SESSION closes the tunnel.' -ForegroundColor Yellow
            Show-Links
            Start-Process (Player-Page $public)
        }
        'Stop' {
            Stop-Owned 'Tunnel'; Stop-Owned 'Game'; Stop-Owned 'Server'
            $state.Remove('PublicUrl'); $state.Remove('Streaming'); Save-State
            Remove-Item -LiteralPath (Join-Path $runtime 'peer-options.json') -Force -ErrorAction SilentlyContinue
            Write-Host 'Managed session stopped.' -ForegroundColor Green
        }
        'OpenPlayer' {
            $public = Active-PublicUrl
            if ($public) { Start-Process (Player-Page $public) }
            else { Start-Process "http://127.0.0.1:$($config.PlayerPort)/player.html" }
        }
        'Status' {
            foreach ($key in @('Server','Game','Tunnel')) {
                $process = Owned-Process $state[$key]
                Write-Host "${key}: $(if ($process) { 'Running (PID ' + $process.Id + ')' } else { 'Stopped' })"
            }
            if (Owned-Process $state.Server) {
                if (Check-Streamer) { Write-Host 'Streamer registered: YES' -ForegroundColor Green }
                else { Write-Warning 'Streamer registered: NO. The game may still be loading, or the packaged game lacks the Pixel Streaming plugin.' }
            }
            Show-Links
        }
    }
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    $failed = $true
} finally {
    if ($locked) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
if (-not $NoPause) { Read-Host 'Press ENTER to close this console' | Out-Null }
if ($failed) { exit 1 }
