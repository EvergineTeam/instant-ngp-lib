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

function Build-Shared {
	param (
		[Parameter(mandatory = $true)][string]$viewer_path,
		[Parameter(mandatory = $true)][int]$arch
	)

	$arch_name = ""
	if ($arch -eq 75) { $arch_name = "rtx2" }
	elseif ($arch -eq 86) { $arch_name = "rtx3" }
	elseif ($arch -eq 89) { $arch_name = "rtx4" }
	else { echo "Architecture $arch not supported"; exit(1) }

	Start-Process -FilePath cmake -ArgumentList (". -DTCNN_CUDA_ARCHITECTURES=$arch -B build") -Wait -NoNewWindow
	if (-not $?) {
		exit $LASTEXITCODE
	}
	cmake --build build --config RelWithDebInfo -j
	if (-not $?) {
		exit $LASTEXITCODE
	}

	Copy-Item ./build/ngp_shared.dll $viewer_path/Evergine.InstantNGP/runtimes/win-x64/$arch_name/native/
	Copy-Item ./build/ngp_shared.pdb $viewer_path/Evergine.InstantNGP/runtimes/win-x64/$arch_name/native/
	Copy-Item ./build/nvngx_dlss.dll $viewer_path/Evergine.InstantNGP/runtimes/win-x64/$arch_name/native/

	$arch_name_upper = $arch_name.ToUpper()
	Write-Output "$arch_name_upper Libraries copied to main Evergine.NGPViewer project."
}

# Build-Shared -viewer_path $viewer_path -arch 75
Build-Shared -viewer_path $viewer_path -arch 86
Build-Shared -viewer_path $viewer_path -arch 89

Pop-Location
