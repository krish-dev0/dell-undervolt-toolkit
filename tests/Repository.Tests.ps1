#requires -Version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path

& (Join-Path (Join-Path $repoRoot 'scripts') 'Test-Toolkit.ps1') -SourceRoot $repoRoot -RequireSourceOnly

$readme = Get-Content -LiteralPath (Join-Path $repoRoot 'README.md') -Raw
if ($readme -notmatch 'VarOffset.*not universal' -and $readme -notmatch 'not universal') {
    throw 'README must state that firmware offsets are not universal.'
}
if ($readme -notmatch 'UEFITool plus IFRExtractor') {
    throw 'README must require UEFITool plus IFRExtractor analysis.'
}
if ($readme -notmatch 'https://www\.youtube\.com/watch\?v=gJBEIfyV7DY') {
    throw 'Tutorial link is missing from README.'
}

$example = Get-Content -LiteralPath (Join-Path (Join-Path $repoRoot 'examples') 'precision-3551-video-example.json') -Raw | ConvertFrom-Json
if (-not [bool]$example.exampleOnly -or [bool]$example.portablePreset) {
    throw 'The Precision 3551 example must remain explicitly non-portable.'
}

$allText = Get-ChildItem -LiteralPath $repoRoot -Include '*.md', '*.ps1', '*.psm1', '*.json', '*.csv' -File -Recurse | ForEach-Object {
    Get-Content -LiteralPath $_.FullName -Raw
}
$joinedText = $allText -join "`n"
if ($joinedText -match '(?i)automatically\s+(write|set).{0,30}(UEFI|NVRAM|firmware).{0,20}(variable|offset)') {
    throw 'Repository text appears to claim automatic firmware-variable writes.'
}

Write-Host 'Repository policy tests passed.' -ForegroundColor Green
