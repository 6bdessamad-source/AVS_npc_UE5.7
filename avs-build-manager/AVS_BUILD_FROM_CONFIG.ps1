param([ValidateSet('Base','Patch')][string]$Mode = 'Patch')
$config = Get-Content (Join-Path $PSScriptRoot 'AVS_BuildManager.config.json') -Raw | ConvertFrom-Json
$options = @{
    Mode = $Mode; ProjectPath = $config.ProjectPath; UERoot = $config.UERoot; OutputRoot = $config.OutputRoot
    BaseVersion = $config.BaseVersion; NewVersion = $config.NewVersion; UpdateName = $config.UpdateName
    CreateZip = $(if ($config.CreateZip) { '1' } else { '0' })
}
& (Join-Path $PSScriptRoot 'AVS_RUN_BUILD.ps1') @options
