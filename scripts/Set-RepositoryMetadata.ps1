#requires -Version 5.1
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9_.-]+/dell-undervolt-toolkit$')]
    [string]$Repository,

    [string]$SourceRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
    $SourceRoot = Split-Path -Parent $PSScriptRoot
}
$root = (Resolve-Path -LiteralPath $SourceRoot -ErrorAction Stop).Path
$placeholder = 'krish-dev0/dell-undervolt-toolkit
'
$extensions = @('.md', '.json', '.yml', '.yaml', '.ps1', '.psm1', '.txt')
$changed = New-Object System.Collections.Generic.List[string]

$files = @(Get-ChildItem -LiteralPath $root -File -Recurse -Force | Where-Object {
    $extensions -contains $_.Extension.ToLowerInvariant()
})

foreach ($file in $files) {
    $content = Get-Content -LiteralPath $file.FullName -Raw
    if ($content -notlike "*$placeholder*") {
        continue
    }

    $updated = $content.Replace($placeholder, $Repository)
    if ($PSCmdlet.ShouldProcess($file.FullName, "Replace '$placeholder' with '$Repository'")) {
        $encoding = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($file.FullName, $updated, $encoding)
        $changed.Add($file.FullName)
    }
}

if ($changed.Count -eq 0) {
    Write-Host "No '$placeholder' placeholders were found under '$root'."
}
else {
    Write-Host "Updated $($changed.Count) file(s) for repository '$Repository'." -ForegroundColor Green
    $changed | ForEach-Object { Write-Host "  $_" }
}

Write-Host 'Review the diff before committing. This script does not create, push, or modify a GitHub repository.'
