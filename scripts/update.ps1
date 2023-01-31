param (
	[System.IO.FileInfo]$localFeedPath,
	[string]$versionSuffix = "local"
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ps_support.ps1"

# Set working directory
$currentDir = (Get-Location).Path
Push-Location $currentDir
Set-Location $PSScriptRoot/..

git submodule update --init --recursive
git pull

conda env remove -n instantngp

& ".\setup.ps1"
& ".\build.ps1"

Pop-Location
