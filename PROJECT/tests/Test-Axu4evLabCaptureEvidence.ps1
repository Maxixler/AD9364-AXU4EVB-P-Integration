param(
    [string]$Python = 'python',
    [string]$Manifest,
    [string]$Evidence,
    [string]$Npz,
    [string]$Csv
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$arguments = @(
    '-B',
    '-m',
    'PROJECT.lab_console.evidence'
)

foreach ($binding in @(
    @{ Name = '--manifest'; Value = $Manifest },
    @{ Name = '--evidence'; Value = $Evidence },
    @{ Name = '--npz'; Value = $Npz },
    @{ Name = '--csv'; Value = $Csv }
)) {
    if (-not [string]::IsNullOrWhiteSpace($binding.Value)) {
        $arguments += $binding.Name
        $arguments += $binding.Value
    }
}

Push-Location $root
try {
    & $Python @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Controlled-CW evidence validation failed with exit code $LASTEXITCODE."
    }
} finally {
    Pop-Location
}
