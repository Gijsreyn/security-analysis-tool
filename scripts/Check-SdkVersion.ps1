#Requires -Version 7.0
<#
.SYNOPSIS
    Verifies that the SAT SDK version is consistent everywhere it is declared.

.DESCRIPTION
    The SDK version lives in three places that must agree, or every notebook
    fails at install time with "no such file dbl_sat_sdk-<version>...whl":

      1. src/securityanalysistoolproject/setup.py      -> __version__ = "x.y.z"
      2. notebooks/Includes/install_sat_sdk.py         -> SDK_VERSION='x.y.z'
      3. lib/dbl_sat_sdk-x.y.z-py3-none-any.whl        -> exactly one wheel,
         whose embedded METADATA also reports Version: x.y.z

    Exits 0 when all agree, 1 otherwise. Run it before tagging a release and
    in CI on every push.

.EXAMPLE
    pwsh ./scripts/Check-SdkVersion.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$setupPy = Join-Path $repoRoot 'src/securityanalysistoolproject/setup.py'
$installNb = Join-Path $repoRoot 'notebooks/Includes/install_sat_sdk.py'
$libDir = Join-Path $repoRoot 'lib'

$errors = [System.Collections.Generic.List[string]]::new()

function Get-SingleMatch {
    param(
        [string]$Path,
        [string]$Pattern,
        [string]$Label
    )
    if (-not (Test-Path $Path)) {
        $script:errors.Add("$Label not found: $Path")
        return $null
    }
    $matches = Select-String -Path $Path -Pattern $Pattern -AllMatches
    $values = @($matches | ForEach-Object { $_.Matches } | ForEach-Object { $_.Groups[1].Value })
    if ($values.Count -eq 0) {
        $script:errors.Add("$Label has no version declaration matching '$Pattern'")
        return $null
    }
    if ($values.Count -gt 1) {
        $script:errors.Add("$Label declares the version more than once: $($values -join ', ')")
        return $null
    }
    return $values[0]
}

# 1. setup.py
$setupVersion = Get-SingleMatch -Path $setupPy `
    -Pattern '^\s*__version__\s*=\s*["'']([^"'']+)["'']' `
    -Label 'setup.py'

# 2. install_sat_sdk.py
$notebookVersion = Get-SingleMatch -Path $installNb `
    -Pattern '^\s*SDK_VERSION\s*=\s*["'']([^"'']+)["'']' `
    -Label 'install_sat_sdk.py'

# 3. lib/ wheel(s)
$wheelVersion = $null
if (-not (Test-Path $libDir)) {
    $errors.Add("lib directory not found: $libDir")
}
else {
    $wheels = @(Get-ChildItem -Path $libDir -Filter 'dbl_sat_sdk-*.whl' -File)
    if ($wheels.Count -eq 0) {
        $errors.Add("lib/ contains no dbl_sat_sdk-*.whl")
    }
    elseif ($wheels.Count -gt 1) {
        $errors.Add("lib/ must contain exactly one SDK wheel, found $($wheels.Count): $($wheels.Name -join ', '). Delete the stale one(s).")
    }
    else {
        $wheel = $wheels[0]
        if ($wheel.Name -match '^dbl_sat_sdk-(\d+\.\d+\.\d+)-py3-none-any\.whl$') {
            $wheelVersion = $Matches[1]
        }
        else {
            $errors.Add("Wheel filename does not follow dbl_sat_sdk-x.y.z-py3-none-any.whl: $($wheel.Name)")
        }

        # Cross-check the version baked into the wheel, in case the file was renamed by hand.
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead($wheel.FullName)
        try {
            $metadata = $zip.Entries | Where-Object { $_.FullName -like '*.dist-info/METADATA' } | Select-Object -First 1
            if ($null -eq $metadata) {
                $errors.Add("Wheel $($wheel.Name) has no dist-info/METADATA entry")
            }
            else {
                $reader = [System.IO.StreamReader]::new($metadata.Open())
                try { $content = $reader.ReadToEnd() } finally { $reader.Dispose() }
                $m = [regex]::Match($content, '(?m)^Version:\s*(\S+)')
                if (-not $m.Success) {
                    $errors.Add("Wheel $($wheel.Name) METADATA has no Version line")
                }
                elseif ($wheelVersion -and $m.Groups[1].Value -ne $wheelVersion) {
                    $errors.Add("Wheel filename says $wheelVersion but its METADATA says $($m.Groups[1].Value). Rebuild the wheel instead of renaming it.")
                }
            }
        }
        finally {
            $zip.Dispose()
        }
    }
}

Write-Host ''
Write-Host 'SAT SDK version declarations'
Write-Host ('  setup.py            : {0}' -f ($setupVersion ?? '<missing>'))
Write-Host ('  install_sat_sdk.py  : {0}' -f ($notebookVersion ?? '<missing>'))
Write-Host ('  lib/ wheel          : {0}' -f ($wheelVersion ?? '<missing>'))
Write-Host ''

$found = @($setupVersion, $notebookVersion, $wheelVersion) | Where-Object { $_ }
$distinct = @($found | Sort-Object -Unique)
if ($found.Count -eq 3 -and $distinct.Count -gt 1) {
    $errors.Add("Versions disagree: $($distinct -join ' vs '). All three must match.")
}

if ($errors.Count -gt 0) {
    Write-Host 'FAIL: SDK version is out of sync' -ForegroundColor Red
    $errors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    Write-Host ''
    Write-Host 'To bump the SDK version:'
    Write-Host '  1. Set __version__ in src/securityanalysistoolproject/setup.py'
    Write-Host '  2. cd src/securityanalysistoolproject; python setup.py sdist bdist_wheel'
    Write-Host '  3. Remove lib/dbl_sat_sdk-*.whl and copy dist/dbl_sat_sdk-<version>-py3-none-any.whl into lib/'
    Write-Host '  4. Set SDK_VERSION in notebooks/Includes/install_sat_sdk.py to the same value'
    exit 1
}

Write-Host "OK: SDK version $($distinct[0]) is consistent across setup.py, install_sat_sdk.py and lib/" -ForegroundColor Green
exit 0
