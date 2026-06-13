$ErrorActionPreference = "Stop"

param(
    [string]$Configuration = "Release",
    [string]$OutputDir = "$env:USERPROFILE\Desktop\v2dex desktop",
    [string]$SingBoxPath = $env:V2DEX_SING_BOX_PATH
)

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$ProjectPath = Join-Path $PSScriptRoot "V2DexWindowsBridge.csproj"
$PublishDir = Join-Path $RepoRoot ".build-artifacts\windows\publish"
$PackageDir = Join-Path $RepoRoot ".build-artifacts\windows\package"

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw "dotnet SDK is required to build the Windows package."
}

if ([string]::IsNullOrWhiteSpace($SingBoxPath)) {
    $Candidates = @(
        (Join-Path $RepoRoot ".local\bin\sing-box.exe"),
        "C:\Program Files\sing-box\sing-box.exe",
        "C:\sing-box\sing-box.exe"
    )
    $SingBoxPath = $Candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}

if ([string]::IsNullOrWhiteSpace($SingBoxPath) -or -not (Test-Path $SingBoxPath)) {
    throw "sing-box.exe was not found. Pass -SingBoxPath or set V2DEX_SING_BOX_PATH."
}

Remove-Item $PublishDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $PackageDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $PublishDir, $PackageDir, $OutputDir | Out-Null

dotnet publish $ProjectPath `
    -c $Configuration `
    -r win-x64 `
    --self-contained true `
    -p:PublishSingleFile=false `
    -o $PublishDir

Copy-Item (Join-Path $PublishDir "*") $PackageDir -Recurse -Force
Copy-Item $SingBoxPath (Join-Path $PackageDir "sing-box.exe") -Force

$ReadmePath = Join-Path $PackageDir "README.txt"
@"
V2Dex Windows package

This package contains the updated Windows native backend and sing-box.exe.

Run requirements:
- The React Native Windows host app must load V2DexWindowsBridge.
- sing-box.exe must stay beside the application binaries.
- Full VPN/Wintun packaging is not included in this backend-only package.

Updated behavior:
- VLESS import parses real config values.
- Multi-encoded names decode correctly.
- WebSocket ed=2560 paths are converted for sing-box.
- Connect starts sing-box and enables Windows system proxy on 127.0.0.1:2080.
- Stop kills sing-box and clears Windows system proxy.
- Ping/Ping All use temporary sing-box probe processes.
"@ | Set-Content -Path $ReadmePath -Encoding UTF8

$ZipPath = Join-Path $OutputDir "V2Dex-Windows-backend-package.zip"
Remove-Item $ZipPath -Force -ErrorAction SilentlyContinue
Compress-Archive -Path (Join-Path $PackageDir "*") -DestinationPath $ZipPath -Force

Write-Host "Windows backend package written to: $ZipPath"
Write-Host "Note: MSIX requires a generated React Native Windows host app and signing certificate."
