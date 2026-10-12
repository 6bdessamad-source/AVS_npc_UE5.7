param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Base", "Patch")]
    [string]$Mode,

    [Parameter(Mandatory = $true)]
    [string]$ProjectPath,

    [Parameter(Mandatory = $true)]
    [string]$UERoot,

    [Parameter(Mandatory = $true)]
    [string]$OutputRoot,

    [string]$BaseVersion = "4.71",

    [Parameter(Mandatory = $true)]
    [string]$NewVersion,

    [string]$UpdateName = "",

    [ValidateSet("0", "1")]
    [string]$CreateZip = "1"
)

$ErrorActionPreference = "Stop"
$host.UI.RawUI.WindowTitle = "AVS Unreal Build - $Mode $NewVersion"

function Write-Stage {
    param([string]$Message, [ConsoleColor]$Color = [ConsoleColor]::Cyan)
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor DarkGray
    Write-Host $Message -ForegroundColor $Color
    Write-Host "============================================================" -ForegroundColor DarkGray
}

function Convert-ToSafeName {
    param([string]$Value)
    $safe = ($Value.Trim() -replace '[^A-Za-z0-9._-]+', '_').Trim('_')
    if ([string]::IsNullOrWhiteSpace($safe)) { return "Update" }
    return $safe
}

function Wait-BeforeClose {
    Write-Host ""
    Read-Host "Press ENTER to close this window"
}

try {
    Write-Stage "AVS BUILD VALIDATION"

    if (Get-Process UnrealEditor -ErrorAction SilentlyContinue) {
        throw "Unreal Editor is still running. Save the project, close Unreal, then retry."
    }

    $runUat = Join-Path $UERoot "Engine\Build\BatchFiles\RunUAT.bat"
    if (-not (Test-Path $runUat -PathType Leaf)) {
        throw "RunUAT.bat was not found: $runUat"
    }
    if (-not (Test-Path $ProjectPath -PathType Leaf)) {
        throw "The project file was not found: $ProjectPath"
    }

    $projectDir = Split-Path $ProjectPath -Parent
    $projectName = [System.IO.Path]::GetFileNameWithoutExtension($ProjectPath)

    if ($Mode -eq "Patch") {
        $releaseFolder = Join-Path $projectDir ("Releases\" + $BaseVersion)
        if (-not (Test-Path $releaseFolder -PathType Container)) {
            throw "Base release data was not found: $releaseFolder`nBuild the base release $BaseVersion first."
        }
    }

    New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
    $logsRoot = Join-Path $OutputRoot "Logs"
    New-Item -ItemType Directory -Path $logsRoot -Force | Out-Null

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $safeName = Convert-ToSafeName $UpdateName

    if ($Mode -eq "Base") {
        $folderName = "Base_${NewVersion}_${timestamp}"
    }
    else {
        $folderName = "Patch_${NewVersion}_${safeName}_${timestamp}"
    }

    $outputDir = Join-Path $OutputRoot $folderName
    $logFile = Join-Path $logsRoot ($folderName + ".log")
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

    Write-Host "Mode          : $Mode"
    Write-Host "Project       : $projectName"
    Write-Host "New version   : $NewVersion"
    if ($Mode -eq "Patch") {
        Write-Host "Base version  : $BaseVersion"
        Write-Host "Update name   : $UpdateName"
    }
    Write-Host "Output        : $outputDir"
    Write-Host "Log           : $logFile"

    $uatArguments = @(
        "BuildCookRun",
        "-project=$ProjectPath",
        "-noP4",
        "-platform=Win64",
        "-clientconfig=Shipping",
        "-build",
        "-cook",
        "-stage",
        "-package",
        "-pak",
        "-archive",
        "-archivedirectory=$outputDir",
        "-compressed",
        "-utf8output"
    )

    if ($Mode -eq "Base") {
        $uatArguments += "-createreleaseversion=$NewVersion"
    }
    else {
        $uatArguments += "-generatepatch"
        $uatArguments += "-basedonreleaseversion=$BaseVersion"
    }

    Write-Stage "RUNNING UNREAL AUTOMATION TOOL"
    Write-Host "The log below is live. This can take a long time on a large project." -ForegroundColor Yellow
    Write-Host ""

    & $runUat @uatArguments 2>&1 | Tee-Object -FilePath $logFile
    $buildExitCode = $LASTEXITCODE

    if ($buildExitCode -ne 0) {
        throw "Unreal Automation Tool failed with exit code $buildExitCode. See: $logFile"
    }

    Write-Stage "BUILD COMPLETED" Green

    if ($CreateZip -eq "1") {
        $tarCommand = Get-Command "tar.exe" -ErrorAction SilentlyContinue
        if ($null -eq $tarCommand) {
            Write-Warning "tar.exe is not available. The build succeeded, but the ZIP was not created."
        }
        elseif ($Mode -eq "Patch") {
            Write-Stage "PREPARING PATCH PAYLOAD"

            $payloadDir = Join-Path $outputDir "PatchPayload"
            New-Item -ItemType Directory -Path $payloadDir -Force | Out-Null

            $searchRoots = @($outputDir)
            $stagedRoot = Join-Path $projectDir "Saved\StagedBuilds\Windows"
            if (Test-Path $stagedRoot) { $searchRoots += $stagedRoot }

            $patchFiles = @()
            foreach ($root in $searchRoots) {
                $found = Get-ChildItem -Path $root -File -Recurse -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -match '(?i)_p\.(pak|utoc|ucas)$' }
                foreach ($file in $found) {
                    if (-not ($patchFiles.FullName -contains $file.FullName)) {
                        $patchFiles += $file
                    }
                }
            }

            if ($patchFiles.Count -eq 0) {
                throw "The build succeeded, but no _P.pak, _P.utoc or _P.ucas patch files were found. Check the log: $logFile"
            }

            foreach ($file in $patchFiles) {
                $sourceRoot = $null
                foreach ($candidate in $searchRoots) {
                    $candidateFull = [System.IO.Path]::GetFullPath($candidate).TrimEnd('\') + '\'
                    if ($file.FullName.StartsWith($candidateFull, [System.StringComparison]::OrdinalIgnoreCase)) {
                        $sourceRoot = $candidateFull
                        break
                    }
                }
                if ($null -eq $sourceRoot) { continue }

                $relativePath = $file.FullName.Substring($sourceRoot.Length)
                $destination = Join-Path $payloadDir $relativePath
                New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
                Copy-Item $file.FullName $destination -Force
                Write-Host "Added: $relativePath"
            }

            $zipName = "AMV_UPDATE_${NewVersion}_${safeName}_${timestamp}.zip"
            $zipPath = Join-Path $OutputRoot $zipName

            Push-Location $payloadDir
            try {
                & $tarCommand.Source -a -c -f $zipPath "."
                if ($LASTEXITCODE -ne 0) { throw "tar.exe failed with exit code $LASTEXITCODE" }
            }
            finally {
                Pop-Location
            }

            Write-Host ""
            Write-Host "Patch ZIP: $zipPath" -ForegroundColor Green
        }
        else {
            Write-Stage "COMPRESSING BASE BUILD"
            $zipName = "AMV_BASE_${NewVersion}_${timestamp}.zip"
            $zipPath = Join-Path $OutputRoot $zipName

            Push-Location $outputDir
            try {
                & $tarCommand.Source -a -c -f $zipPath "."
                if ($LASTEXITCODE -ne 0) { throw "tar.exe failed with exit code $LASTEXITCODE" }
            }
            finally {
                Pop-Location
            }

            Write-Host "Base ZIP: $zipPath" -ForegroundColor Green
        }
    }

    Write-Stage "SUCCESS" Green
    Write-Host "Build folder : $outputDir" -ForegroundColor Green
    Write-Host "Log file     : $logFile" -ForegroundColor Green
    Write-Host ""
    Write-Host "The output folder will now open."
    Start-Process explorer.exe -ArgumentList ('"' + $OutputRoot + '"')
    Wait-BeforeClose
    exit 0
}
catch {
    Write-Stage "BUILD FAILED" Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    if ($logFile) {
        Write-Host ""
        Write-Host "Log file: $logFile" -ForegroundColor Yellow
    }
    Wait-BeforeClose
    exit 1
}
