$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ps_support.ps1"

# Set working directory
$currentDir = (Get-Location).Path
Push-Location $currentDir
Set-Location $PSScriptRoot/..

git submodule update --init --recursive

conda create -n instantngp python=3.9 -y

conda activate instantngp

pip install -r requirements.txt

conda deactivate

Pop-Location
