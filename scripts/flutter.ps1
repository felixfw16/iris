param([Parameter(ValueFromRemainingArguments = $true)][string[]]$FlutterArgs)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$flutterBinary = Join-Path $projectRoot '.tools\flutter\bin\flutter.bat'
if (-not (Test-Path -LiteralPath $flutterBinary)) { throw 'Install Flutter 3.47.4 into .tools/flutter first. See README.md.' }
$env:PATH = "$env:LOCALAPPDATA\Android\Sdk\platform-tools;$env:PATH"
& $flutterBinary @FlutterArgs
exit $LASTEXITCODE
