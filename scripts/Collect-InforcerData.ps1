<#
.SYNOPSIS
    Collects raw API data from all Inforcer data-source cmdlets for documentation development.
.DESCRIPTION
    Runs Get-InforcerTenant, Get-InforcerBaseline, and Get-InforcerTenantPolicies with
    -OutputType JsonObject to capture the full API response. Saves each as a separate
    JSON file in the specified output directory.
.PARAMETER TenantId
    Tenant to collect data for. Accepts numeric ID, GUID, or tenant name.
.PARAMETER OutputDirectory
    Directory to save JSON files. Defaults to ./scripts/sample-data/
.EXAMPLE
    # First connect to Inforcer
    Connect-Inforcer -ApiKey $key -Region eu

    # Then collect data for a specific tenant
    .\scripts\Collect-InforcerData.ps1 -TenantId 482
.EXAMPLE
    # Collect data for a tenant by name
    .\scripts\Collect-InforcerData.ps1 -TenantId "Contoso" -OutputDirectory "C:\temp\inforcer-data"
.NOTES
    Requires an active Inforcer session (Connect-Inforcer).
    Output files:
      - tenants.json        (all tenants)
      - baselines.json      (all baselines)
      - tenant-policies.json (all policies for the specified tenant)
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [object]$TenantId,

    [Parameter(Mandatory = $false)]
    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'sample-data')
)

$ErrorActionPreference = 'Stop'

# Ensure module is loaded
$modulePath = Join-Path $PSScriptRoot '..' 'module' 'InforcerCommunity.psd1'
if (-not (Get-Module InforcerCommunity)) {
    Import-Module $modulePath -Force
}

# Create output directory
if (-not (Test-Path $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}

Write-Host "Collecting Inforcer data for tenant: $TenantId" -ForegroundColor Cyan
Write-Host "Output directory: $OutputDirectory" -ForegroundColor Cyan
Write-Host ""

# 1. Tenants
Write-Host "[1/3] Collecting tenants..." -ForegroundColor Yellow
try {
    $tenantsJson = Get-InforcerTenant -OutputType JsonObject -ErrorAction Stop
    $tenantsPath = Join-Path $OutputDirectory 'tenants.json'
    $tenantsJson | Out-File -FilePath $tenantsPath -Encoding utf8NoBOM
    Write-Host "  Saved: $tenantsPath" -ForegroundColor Green
} catch {
    Write-Error "Failed to collect tenants. Are you connected? Run Connect-Inforcer first. Error: $($_.Exception.Message)"
    return
}

# 2. Baselines
Write-Host "[2/3] Collecting baselines..." -ForegroundColor Yellow
$baselinesJson = Get-InforcerBaseline -OutputType JsonObject
$baselinesPath = Join-Path $OutputDirectory 'baselines.json'
$baselinesJson | Out-File -FilePath $baselinesPath -Encoding utf8NoBOM
Write-Host "  Saved: $baselinesPath" -ForegroundColor Green

# 3. Tenant Policies
Write-Host "[3/3] Collecting policies for tenant $TenantId..." -ForegroundColor Yellow
$policiesJson = Get-InforcerTenantPolicies -TenantId $TenantId -OutputType JsonObject
$policiesPath = Join-Path $OutputDirectory 'tenant-policies.json'
$policiesJson | Out-File -FilePath $policiesPath -Encoding utf8NoBOM
Write-Host "  Saved: $policiesPath" -ForegroundColor Green

Write-Host ""
Write-Host "Data collection complete!" -ForegroundColor Green
Write-Host "Files saved to: $OutputDirectory" -ForegroundColor Cyan
Write-Host ""
Write-Host "Files:" -ForegroundColor Cyan
Get-ChildItem $OutputDirectory -Filter '*.json' | ForEach-Object {
    $size = if ($_.Length -gt 1MB) { "{0:N1} MB" -f ($_.Length / 1MB) }
            elseif ($_.Length -gt 1KB) { "{0:N1} KB" -f ($_.Length / 1KB) }
            else { "$($_.Length) bytes" }
    Write-Host "  $($_.Name) ($size)"
}
