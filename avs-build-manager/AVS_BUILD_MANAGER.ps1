Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot "AVS_COMMON.ps1")

[System.Windows.Forms.Application]::EnableVisualStyles()

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $scriptDir "AVS_BuildManager.config.json"
$runnerPath = Join-Path $scriptDir "AVS_RUN_BUILD.ps1"

function Add-Label {
    param([string]$Text, [int]$X, [int]$Y, [int]$Width = 170)
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.Location = New-Object System.Drawing.Point($X, $Y)
    $label.Size = New-Object System.Drawing.Size($Width, 23)
    $label.ForeColor = [System.Drawing.Color]::FromArgb(225, 225, 225)
    $label.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $buildTab.Controls.Add($label)
    return $label
}

function Add-TextBox {
    param([int]$X, [int]$Y, [int]$Width, [string]$Value = "")
    $box = New-Object System.Windows.Forms.TextBox
    $box.Location = New-Object System.Drawing.Point($X, $Y)
    $box.Size = New-Object System.Drawing.Size($Width, 27)
    $box.Text = $Value
    $box.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $box.BackColor = [System.Drawing.Color]::FromArgb(45, 45, 48)
    $box.ForeColor = [System.Drawing.Color]::White
    $box.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $buildTab.Controls.Add($box)
    return $box
}

function Add-BrowseButton {
    param([int]$X, [int]$Y, [scriptblock]$OnClick)
    $button = New-Object System.Windows.Forms.Button
    $button.Text = "Browse"
    $button.Location = New-Object System.Drawing.Point($X, $Y)
    $button.Size = New-Object System.Drawing.Size(82, 28)
    $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $button.BackColor = [System.Drawing.Color]::FromArgb(63, 63, 70)
    $button.ForeColor = [System.Drawing.Color]::White
    $button.Add_Click($OnClick)
    $buildTab.Controls.Add($button)
    return $button
}

function Quote-Argument {
    param([string]$Value)
    return Quote-NativeArgument $Value
}

$defaults = [ordered]@{
    ProjectPath = Join-Path $scriptDir "AMV_VILLA_UE.uproject"
    UERoot = "C:\Program Files\Epic Games\UE_5.7"
    OutputRoot = Join-Path $scriptDir "AVS_Builds"
    BaseVersion = "4.71"
    NewVersion = "4.72"
    UpdateName = ""
    BuildMode = "Patch"
    CreateZip = $true
    GameExe = ""
    InfrastructureRoot = Join-Path $scriptDir "PixelStreamingInfrastructure-UE5.7"
    PlayerPort = 8080
    StreamerPort = 8888
    ResX = 1920
    ResY = 1080
    FPS = 60
    LanHost = ""
    PublicPlayerUrl = ""
    StunUrl = "stun:stun.l.google.com:19302"
    TurnUrl = ""
    TurnUsername = ""
    TurnPassword = ""
    WebsiteUrl = "https://6bdessamad-source.github.io/AVS_npc_UE5.7/avs-player/"
}

if (Test-Path $configPath) {
    try {
        $saved = Get-Content $configPath -Raw | ConvertFrom-Json
        foreach ($key in @($defaults.Keys)) {
            if ($null -ne $saved.$key -and [string]$saved.$key -ne "") {
                $defaults[$key] = $saved.$key
            }
        }
    }
    catch {
        # Invalid config is ignored; the UI will use safe defaults.
    }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "AVS Build & Stream Manager v2 - UE 5.7"
$form.Size = New-Object System.Drawing.Size(840, 665)
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$form.ForeColor = [System.Drawing.Color]::White
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9)

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock = [System.Windows.Forms.DockStyle]::Fill
$buildTab = New-Object System.Windows.Forms.TabPage
$buildTab.Text = "BUILD / PATCH"
$buildTab.BackColor = $form.BackColor
$streamTab = New-Object System.Windows.Forms.TabPage
$streamTab.Text = "START / STREAM"
$streamTab.BackColor = $form.BackColor
$streamTab.AutoScroll = $true
$tabs.TabPages.Add($buildTab)
$tabs.TabPages.Add($streamTab)
$form.Controls.Add($tabs)

$title = New-Object System.Windows.Forms.Label
$title.Text = "AVS UNREAL BUILD MANAGER"
$title.Location = New-Object System.Drawing.Point(28, 20)
$title.Size = New-Object System.Drawing.Size(500, 35)
$title.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 17)
$title.ForeColor = [System.Drawing.Color]::FromArgb(235, 235, 235)
$buildTab.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = "Create the base release or a cumulative update package"
$subtitle.Location = New-Object System.Drawing.Point(31, 57)
$subtitle.Size = New-Object System.Drawing.Size(600, 22)
$subtitle.ForeColor = [System.Drawing.Color]::FromArgb(170, 170, 170)
$buildTab.Controls.Add($subtitle)

Add-Label "Build type" 30 100 | Out-Null
$modeCombo = New-Object System.Windows.Forms.ComboBox
$modeCombo.Location = New-Object System.Drawing.Point(205, 96)
$modeCombo.Size = New-Object System.Drawing.Size(220, 28)
$modeCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$modeCombo.Items.AddRange(@("Patch", "Base"))
$modeCombo.SelectedItem = [string]$defaults.BuildMode
if ($modeCombo.SelectedIndex -lt 0) { $modeCombo.SelectedItem = "Patch" }
$buildTab.Controls.Add($modeCombo)

Add-Label "Project (.uproject)" 30 145 | Out-Null
$projectBox = Add-TextBox 205 141 480 ([string]$defaults.ProjectPath)
Add-BrowseButton 695 140 {
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Filter = "Unreal Project (*.uproject)|*.uproject"
    if (Test-Path $projectBox.Text) { $dialog.InitialDirectory = Split-Path $projectBox.Text -Parent }
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $projectBox.Text = $dialog.FileName
    }
} | Out-Null

Add-Label "Unreal Engine folder" 30 190 | Out-Null
$ueBox = Add-TextBox 205 186 480 ([string]$defaults.UERoot)
Add-BrowseButton 695 185 {
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Select the UE_5.7 installation folder"
    if (Test-Path $ueBox.Text) { $dialog.SelectedPath = $ueBox.Text }
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $ueBox.Text = $dialog.SelectedPath
    }
} | Out-Null

Add-Label "Output folder" 30 235 | Out-Null
$outputBox = Add-TextBox 205 231 480 ([string]$defaults.OutputRoot)
Add-BrowseButton 695 230 {
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Select the AVS builds output folder"
    if (Test-Path $outputBox.Text) { $dialog.SelectedPath = $outputBox.Text }
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $outputBox.Text = $dialog.SelectedPath
    }
} | Out-Null

Add-Label "Base release version" 30 290 | Out-Null
$baseBox = Add-TextBox 205 286 220 ([string]$defaults.BaseVersion)

Add-Label "New build version" 30 335 | Out-Null
$newBox = Add-TextBox 205 331 220 ([string]$defaults.NewVersion)

Add-Label "Update name" 30 380 | Out-Null
$nameBox = Add-TextBox 205 376 480 ([string]$defaults.UpdateName)

$zipCheck = New-Object System.Windows.Forms.CheckBox
$zipCheck.Text = "Create a ZIP ready to upload after a successful build"
$zipCheck.Location = New-Object System.Drawing.Point(205, 420)
$zipCheck.Size = New-Object System.Drawing.Size(470, 26)
$zipCheck.Checked = [bool]$defaults.CreateZip
$zipCheck.ForeColor = [System.Drawing.Color]::FromArgb(225, 225, 225)
$buildTab.Controls.Add($zipCheck)

$infoPanel = New-Object System.Windows.Forms.Panel
$infoPanel.Location = New-Object System.Drawing.Point(30, 461)
$infoPanel.Size = New-Object System.Drawing.Size(745, 47)
$infoPanel.BackColor = [System.Drawing.Color]::FromArgb(38, 45, 52)
$buildTab.Controls.Add($infoPanel)

$infoLabel = New-Object System.Windows.Forms.Label
$infoLabel.Text = "A live console will open for the build log. Outputs are timestamped and never overwrite older builds."
$infoLabel.Location = New-Object System.Drawing.Point(13, 13)
$infoLabel.Size = New-Object System.Drawing.Size(715, 24)
$infoLabel.ForeColor = [System.Drawing.Color]::FromArgb(188, 214, 231)
$infoPanel.Controls.Add($infoLabel)

$buildButton = New-Object System.Windows.Forms.Button
$buildButton.Text = "BUILD PATCH"
$buildButton.Location = New-Object System.Drawing.Point(565, 520)
$buildButton.Size = New-Object System.Drawing.Size(210, 40)
$buildButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$buildButton.BackColor = [System.Drawing.Color]::FromArgb(20, 110, 180)
$buildButton.ForeColor = [System.Drawing.Color]::White
$buildButton.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 10)
$buildTab.Controls.Add($buildButton)

$openOutputButton = New-Object System.Windows.Forms.Button
$openOutputButton.Text = "OPEN OUTPUTS"
$openOutputButton.Location = New-Object System.Drawing.Point(30, 520)
$openOutputButton.Size = New-Object System.Drawing.Size(160, 40)
$openOutputButton.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$openOutputButton.BackColor = [System.Drawing.Color]::FromArgb(63, 63, 70)
$openOutputButton.ForeColor = [System.Drawing.Color]::White
$buildTab.Controls.Add($openOutputButton)

$modeCombo.Add_SelectedIndexChanged({
    if ($modeCombo.SelectedItem -eq "Base") {
        $buildButton.Text = "BUILD BASE RELEASE"
        $baseBox.Enabled = $false
        $nameBox.Enabled = $false
        $infoLabel.Text = "The new build version becomes the permanent release baseline. Keep its Releases folder."
    }
    else {
        $buildButton.Text = "BUILD PATCH"
        $baseBox.Enabled = $true
        $nameBox.Enabled = $true
        $infoLabel.Text = "A live console will open for the build log. Outputs are timestamped and never overwrite older builds."
    }
})

$openOutputButton.Add_Click({
    if (-not (Test-Path $outputBox.Text)) {
        New-Item -ItemType Directory -Path $outputBox.Text -Force | Out-Null
    }
    Start-Process explorer.exe -ArgumentList (Quote-Argument $outputBox.Text)
})

$buildButton.Add_Click({
    $projectPath = $projectBox.Text.Trim()
    $ueRoot = $ueBox.Text.Trim()
    $outputRoot = $outputBox.Text.Trim()
    $baseVersion = $baseBox.Text.Trim()
    $newVersion = $newBox.Text.Trim()
    $updateName = $nameBox.Text.Trim()
    $mode = [string]$modeCombo.SelectedItem

    $runUat = Join-Path $ueRoot "Engine\Build\BatchFiles\RunUAT.bat"

    if (-not (Test-Path $projectPath -PathType Leaf)) {
        [System.Windows.Forms.MessageBox]::Show("The .uproject file was not found.", "AVS Build Manager", "OK", "Error") | Out-Null
        return
    }
    if (-not (Test-Path $runUat -PathType Leaf)) {
        [System.Windows.Forms.MessageBox]::Show("RunUAT.bat was not found in the selected Unreal Engine folder.", "AVS Build Manager", "OK", "Error") | Out-Null
        return
    }
    if ([string]::IsNullOrWhiteSpace($newVersion) -or $newVersion -notmatch '^[A-Za-z0-9._-]+$') {
        [System.Windows.Forms.MessageBox]::Show("Enter a valid build version, for example 4.72.", "AVS Build Manager", "OK", "Warning") | Out-Null
        return
    }
    if ($mode -eq "Patch" -and ([string]::IsNullOrWhiteSpace($baseVersion) -or $baseVersion -notmatch '^[A-Za-z0-9._-]+$')) {
        [System.Windows.Forms.MessageBox]::Show("Enter a valid base release version, for example 4.71.", "AVS Build Manager", "OK", "Warning") | Out-Null
        return
    }
    if ($mode -eq "Patch" -and [string]::IsNullOrWhiteSpace($updateName)) {
        [System.Windows.Forms.MessageBox]::Show("Enter a short update name, for example Villa_UI.", "AVS Build Manager", "OK", "Warning") | Out-Null
        return
    }
    if (Get-Process UnrealEditor -ErrorAction SilentlyContinue) {
        [System.Windows.Forms.MessageBox]::Show("Unreal Editor is currently running. Save the project and close Unreal before building.", "Unreal must be closed", "OK", "Warning") | Out-Null
        return
    }
    if (-not (Test-Path $runnerPath -PathType Leaf)) {
        [System.Windows.Forms.MessageBox]::Show("AVS_RUN_BUILD.ps1 is missing from the kit folder.", "AVS Build Manager", "OK", "Error") | Out-Null
        return
    }

    Save-AllSettings

    $arguments = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", (Quote-Argument $runnerPath),
        "-Mode", $mode,
        "-ProjectPath", (Quote-Argument $projectPath),
        "-UERoot", (Quote-Argument $ueRoot),
        "-OutputRoot", (Quote-Argument $outputRoot),
        "-BaseVersion", $baseVersion,
        "-NewVersion", $newVersion,
        "-UpdateName", (Quote-Argument $updateName),
        "-CreateZip", $(if ($zipCheck.Checked) { "1" } else { "0" })
    )

    Start-Process -FilePath "powershell.exe" -ArgumentList $arguments -WorkingDirectory $scriptDir

    [System.Windows.Forms.MessageBox]::Show(
        "The build was launched in a separate live log window. You can keep this manager open.",
        "Build launched",
        "OK",
        "Information"
    ) | Out-Null
})

# Apply the selected mode after all controls exist.
if ($modeCombo.SelectedItem -eq "Base") {
    $buildButton.Text = "BUILD BASE RELEASE"
    $baseBox.Enabled = $false
    $nameBox.Enabled = $false
    $infoLabel.Text = "The new build version becomes the permanent release baseline. Keep its Releases folder."
}


function Stream-Label([string]$text, [int]$x, [int]$y, [int]$width = 185) {
    $control = New-Object System.Windows.Forms.Label
    $control.Text = $text
    $control.Location = New-Object Drawing.Point($x,$y)
    $control.Size = New-Object Drawing.Size($width,23)
    $control.ForeColor = [Drawing.Color]::Gainsboro
    $streamTab.Controls.Add($control)
    return $control
}
function Stream-Box([string]$key, [int]$x, [int]$y, [int]$width = 475) {
    $control = New-Object System.Windows.Forms.TextBox
    $control.Text = [string]$defaults[$key]
    $control.Location = New-Object Drawing.Point($x,$y)
    $control.Size = New-Object Drawing.Size($width,25)
    $control.BackColor = [Drawing.Color]::FromArgb(45,45,48)
    $control.ForeColor = [Drawing.Color]::White
    $streamTab.Controls.Add($control)
    $script:streamBoxes[$key] = $control
    return $control
}
function Stream-Button([string]$text, [int]$x, [int]$y, [int]$width, [scriptblock]$handler) {
    $control = New-Object System.Windows.Forms.Button
    $control.Text = $text
    $control.Location = New-Object Drawing.Point($x,$y)
    $control.Size = New-Object Drawing.Size($width,34)
    $control.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $control.BackColor = [Drawing.Color]::FromArgb(25,91,127)
    $control.ForeColor = [Drawing.Color]::White
    $control.Add_Click($handler)
    $streamTab.Controls.Add($control)
    return $control
}
$script:streamBoxes = @{}
Stream-Label "AVS / LIVE FROM YOUR RIG" 28 20 700 | Out-Null
Stream-Label "Choose a packaged EXE. First run SETUP STREAMING, then START STREAM." 28 48 740 | Out-Null
$rows = @(
    @('Game EXE','GameExe'), @('Infrastructure folder','InfrastructureRoot'),
    @('Player HTTP port','PlayerPort'), @('Game signalling port','StreamerPort'),
    @('Width / height / FPS','ResX'), @('Rig LAN IP (blank = auto)','LanHost'),
    @('HTTPS player URL (optional)','PublicPlayerUrl'), @('STUN URL','StunUrl'),
    @('TURN URL (internet relay)','TurnUrl'), @('TURN username','TurnUsername'),
    @('TURN password','TurnPassword')
)
$y = 88
foreach ($row in $rows) {
    Stream-Label $row[0] 28 $y | Out-Null
    $width = if ($row[1] -in @('PlayerPort','StreamerPort','ResX')) { 120 } else { 475 }
    Stream-Box $row[1] 218 ($y-3) $width | Out-Null
    $y += 34
}
Stream-Box 'ResY' 363 221 120 | Out-Null
Stream-Box 'FPS' 508 221 100 | Out-Null
$script:streamBoxes.TurnPassword.UseSystemPasswordChar = $true
if ($defaults.TurnPassword) {
    try { $script:streamBoxes.TurnPassword.Text = Unprotect-LocalSecret ([string]$defaults.TurnPassword) }
    catch { $script:streamBoxes.TurnPassword.Text = ''; [Windows.Forms.MessageBox]::Show('The saved TURN password belongs to another Windows account. Enter it again.') | Out-Null }
}
Stream-Button 'Browse' 705 84 78 {
    $dialog = New-Object Windows.Forms.OpenFileDialog
    $dialog.Filter = 'Packaged game (*.exe)|*.exe'
    $dialog.Title = 'Select the packaged game (Binaries\Win64\*-Shipping.exe)'
    if ($dialog.ShowDialog() -eq 'OK') { $script:streamBoxes.GameExe.Text = $dialog.FileName }
} | Out-Null
Stream-Button 'Browse' 705 118 78 {
    $dialog = New-Object Windows.Forms.FolderBrowserDialog
    if ($dialog.ShowDialog() -eq 'OK') { $script:streamBoxes.InfrastructureRoot.Text = $dialog.SelectedPath }
} | Out-Null
function Save-AllSettings {
    $settings = [ordered]@{
        ProjectPath = $projectBox.Text.Trim(); UERoot = $ueBox.Text.Trim(); OutputRoot = $outputBox.Text.Trim()
        BaseVersion = $baseBox.Text.Trim(); NewVersion = $newBox.Text.Trim(); UpdateName = $nameBox.Text.Trim()
        BuildMode = [string]$modeCombo.SelectedItem; CreateZip = [bool]$zipCheck.Checked
        WebsiteUrl = [string]$defaults.WebsiteUrl
    }
    foreach ($key in $script:streamBoxes.Keys) {
        $value = $script:streamBoxes[$key].Text.Trim()
        if ($key -eq 'TurnPassword') { $value = Protect-LocalSecret $script:streamBoxes[$key].Text }
        $settings[$key] = $value
    }
    Write-JsonUtf8 $configPath $settings
}
function Run-StreamCommand([string]$action) {
    try {
        Save-AllSettings
        $saved = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
        if ($action -ne 'Stop') { Assert-StreamConfig $saved }
        $scriptPath = Join-Path $scriptDir 'AVS_STREAM.ps1'
        $argsList = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$scriptPath,'-Action',$action,'-ConfigPath',$configPath)
        Start-Process powershell.exe -ArgumentList (Join-NativeArguments $argsList) -WorkingDirectory $scriptDir
    } catch { [Windows.Forms.MessageBox]::Show($_.Exception.Message, 'AVS', 'OK', 'Error') | Out-Null }
}
Stream-Button 'SETUP STREAMING' 28 476 170 { Run-StreamCommand 'Setup' } | Out-Null
Stream-Button 'START GAME' 208 476 170 { Run-StreamCommand 'StartGame' } | Out-Null
Stream-Button 'START STREAM' 388 476 170 { Run-StreamCommand 'StartStream' } | Out-Null
Stream-Button 'STOP SESSION' 568 476 215 { Run-StreamCommand 'Stop' } | Out-Null
Stream-Button 'CREATE INTERNET LINK' 28 519 215 { Run-StreamCommand 'Internet' } | Out-Null
Stream-Button 'OPEN PLAYER' 253 519 160 { Run-StreamCommand 'OpenPlayer' } | Out-Null
Stream-Button 'CHECK STATUS' 423 519 160 { Run-StreamCommand 'Status' } | Out-Null
Stream-Button 'LOGS / LINKS' 593 519 190 {
    Start-Process explorer.exe -ArgumentList (Quote-NativeArgument $scriptDir)
} | Out-Null
Stream-Label 'Internet: install cloudflared; configure TURN if video cannot cross your networks.' 28 566 755 | Out-Null
Stream-Label 'Enable Pixel Streaming 2 before packaging. STOP SESSION closes only the managed session.' 28 590 755 | Out-Null
$form.Add_FormClosing({ try { Save-AllSettings } catch { } })
[void]$form.ShowDialog()

