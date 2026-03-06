# InforcerCommunity PowerShell Script Module (community project)
# Private helpers (not exported)
$privatePath = Join-Path $PSScriptRoot 'Private'
Get-ChildItem -Path $privatePath -Filter '*.ps1' -Recurse | ForEach-Object { . $_.FullName }
# Public cmdlets (exported via manifest)
$publicPath = Join-Path $PSScriptRoot 'Public'
Get-ChildItem -Path $publicPath -Filter '*.ps1' -Recurse | ForEach-Object { . $_.FullName }
