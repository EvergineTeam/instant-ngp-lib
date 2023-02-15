<#
.SYNOPSIS
	This script generates all dlls needed for Evergine.NGPViewer for RTX2 and RTX3-4
.EXAMPLE
	.\scripts\build.ps1 -viewer_path "../Evergine.NGPViewer/Evergine.InstantNGP"
.LINK
	https://evergine.com
#>

param (
	[Parameter(mandatory = $true)][string]$viewer_path
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ps_support.ps1"

# Set working directory
$viewer_path = Resolve-Path($viewer_path)
$currentDir = (Get-Location).Path
Push-Location $currentDir
Set-Location $PSScriptRoot/..

# # cmake . -DTCNN_CUDA_ARCHITECTURES=89 -B build  # comment this line for incremental build (deactivate other arch builds)
if (-not $?) {
	exit $LASTEXITCODE
}
cmake --build build --config RelWithDebInfo -j
if (-not $?) {
	exit $LASTEXITCODE
}

Copy-Item ./build/nvngx_dlss.dll $viewer_path/Evergine.InstantNGP/runtimes/win-x64/rtx4/native/
Copy-Item ./build/ngp_shared.dll $viewer_path/Evergine.InstantNGP/runtimes/win-x64/rtx4/native/
Copy-Item ./build/ngp_shared.pdb $viewer_path/Evergine.InstantNGP/runtimes/win-x64/rtx4/native/

Write-Output "RTX4 Libraries copied to main Evergine.NGPViewer project."

Pop-Location
