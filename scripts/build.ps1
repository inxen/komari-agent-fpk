# build.ps1 - 本地打包 Komari Agent .fpk（Windows）
# 用法: powershell -ExecutionPolicy Bypass -File scripts\build.ps1 [-Version <tag|latest>] [-Arch amd64|arm64]
# 产物: D:\workbuddy\fnos-fpk\komari-agent.fpk（默认 x86_64；-Arch arm64 时同时改写 manifest platform=arm）
param(
    [string]$Version = "latest",
    [string]$Arch = "amd64"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Pack = Join-Path $Root "komari-agent"
$Tools = Join-Path $Root "tools"
$Fnpack = Join-Path $Tools "fnpack.exe"
$AgentOut = Join-Path $Pack "app\komari-agent"
$Manifest = Join-Path $Pack "manifest"

New-Item -ItemType Directory -Force -Path $Tools | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $Pack "app") | Out-Null

# ---- 1. 下载 komari-agent 二进制 ----
if ($Arch -eq "arm64") {
    $Asset = "komari-agent-linux-arm64"
    $Platform = "arm"
} else {
    $Asset = "komari-agent-linux-amd64"
    $Platform = "x86"
}

if ($Version -eq "latest") {
    $Url = "https://github.com/komari-monitor/komari-agent/releases/latest/download/$Asset"
} else {
    $Url = "https://github.com/komari-monitor/komari-agent/releases/download/$Version/$Asset"
}
Write-Host "Downloading $Url ..."
Invoke-WebRequest -Uri $Url -OutFile $AgentOut
Write-Host "Agent binary size: $((Get-Item $AgentOut).Length) bytes"

# ---- 2. 下载 fnpack（首次） ----
if (-not (Test-Path $Fnpack)) {
    Write-Host "Downloading fnpack ..."
    Invoke-WebRequest -Uri "https://static2.fnnas.com/fnpack/fnpack-1.2.3-windows-amd64" -OutFile $Fnpack
}

# ---- 3. 解析版本号并改写 manifest：platform / version ----
if ($Version -eq "latest") {
    Write-Host "Resolving latest komari-agent tag ..."
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/komari-monitor/komari-agent/releases/latest" -Headers @{ "User-Agent" = "fnos-build" }
    $tag = $release.tag_name
} else {
    $tag = $Version
}
$ver = $tag.TrimStart("v")

$manifestContent = Get-Content $Manifest -Raw -Encoding UTF8
$manifestContent = $manifestContent -replace "(?m)^platform=.*$", "platform=$Platform"
$manifestContent = $manifestContent -replace "(?m)^version=.*$", "version=$ver"
Set-Content -Path $Manifest -Value $manifestContent -Encoding UTF8 -NoNewline
Write-Host "manifest: platform=$Platform version=$ver (tag=$tag)"

# ---- 4. fnpack build（产物输出到调用时的 cwd） ----
Push-Location $Root
try {
    Write-Host "Running fnpack build ..."
    & $Fnpack build --directory $Pack
    if ($LASTEXITCODE -ne 0) { throw "fnpack build failed with exit code $LASTEXITCODE" }
}
finally {
    Pop-Location
}

$fpk = Join-Path $Root "komari-agent.fpk"
if (Test-Path $fpk) {
    Write-Host ""
    Write-Host "SUCCESS: $fpk ($((Get-Item $fpk).Length) bytes)"
} else {
    Write-Host "ERROR: output .fpk not found" -ForegroundColor Red
    exit 1
}
