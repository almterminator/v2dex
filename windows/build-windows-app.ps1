param(
    [string]$Configuration = "Release",
    [string]$Runtime = "win-x64"
)

$ErrorActionPreference = "Stop"

$ProjectPath = Join-Path $PSScriptRoot "V2Dex.WindowsApp\V2Dex.WindowsApp.csproj"
$PublishDir = Join-Path $PSScriptRoot "artifacts\V2Dex.WindowsApp-$Runtime"

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw "dotnet SDK 8.0 or newer is required."
}

dotnet publish $ProjectPath `
    -c $Configuration `
    -r $Runtime `
    --self-contained true `
    -p:PublishSingleFile=true `
    -p:IncludeNativeLibrariesForSelfExtract=true `
    -p:EnableCompressionInSingleFile=true `
    -o $PublishDir

$SingBoxCandidates = @(
    (Join-Path $PSScriptRoot "..\.local\bin\sing-box.exe"),
    (Join-Path $PSScriptRoot "sing-box.exe")
)

$SingBox = $SingBoxCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($SingBox) {
    Copy-Item $SingBox (Join-Path $PublishDir "sing-box.exe") -Force
} else {
    Write-Warning "sing-box.exe was not found. Put it next to V2Dex.exe or set V2DEX_SING_BOX_PATH on Windows."
}

Write-Host "V2Dex Windows app published to: $PublishDir"
