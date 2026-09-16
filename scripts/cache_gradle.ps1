$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$archive = Join-Path $projectRoot '.tools\gradle-9.3.1-bin.zip'
$expected = 'b266d5ff6b90eada6dc3b20cb090e3731302e553a27c5d3e4df1f0d76beaff06'
if (-not (Test-Path -LiteralPath $archive) -or (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) {
    & curl.exe --fail --location --retry 5 --retry-all-errors --connect-timeout 30 --max-time 600 --output $archive 'https://mirrors.huaweicloud.com/gradle/gradle-9.3.1-bin.zip'
    if ($LASTEXITCODE -ne 0) { throw 'Gradle download failed.' }
}
if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) { throw 'Official Gradle SHA-256 verification failed.' }
$cacheDirectory = Join-Path $env:USERPROFILE '.gradle\wrapper\dists\gradle-9.3.1-bin\30eg2jcb8eqk5ro0gq9h8x6ef'
New-Item -ItemType Directory -Force -Path $cacheDirectory | Out-Null
Copy-Item -LiteralPath $archive -Destination (Join-Path $cacheDirectory 'gradle-9.3.1-bin.zip')
Write-Output 'Official Gradle checksum verified. Wrapper cache prepared.'
