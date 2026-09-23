 $ErrorActionPreference = "Continue"

 $AbiMap = @{
    "arm64-v8a"   = "aarch64-linux-android"
    "armeabi-v7a" = "armv7-linux-androideabi"
}

 $ProjectRoot  = Get-Location
 $CrateDir     = Join-Path $ProjectRoot "spotify_bridge\librespot-ffi"
 $OutputDir    = Join-Path $ProjectRoot "android\app\src\main\jniLibs"
 $PlatformVersion = 21

if (-not $env:ANDROID_SDK_ROOT) {
    Write-Host "ANDROID_SDK_ROOT is not set"
    exit 1
}

 $NdkBase = Join-Path $env:ANDROID_SDK_ROOT "ndk"
 $NdkPath = Get-ChildItem $NdkBase -Directory |
    Where-Object { $_.Name -match '^\d+\.' } |
    Sort-Object Name |
    Select-Object -Last 1

if (-not $NdkPath) {
    Write-Host "No Android NDK 29.x found"
    exit 1
}

 $env:ANDROID_NDK_HOME = $NdkPath.FullName
Write-Host "Using ANDROID_NDK=$($env:ANDROID_NDK_HOME)"

foreach ($abi in $AbiMap.Keys) {
    $triple = $AbiMap[$abi]

    Write-Host "Building librespot-ffi for $abi ($triple)..."
    Set-Location $CrateDir

    cargo ndk -t $abi --platform $PlatformVersion build --release

    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to build for $abi"
        exit 1
    }

    $SoFile = Join-Path $CrateDir "target\$triple\release\liblibrespot_ffi.so"
    $OutAbiDir = Join-Path $OutputDir $abi
    New-Item -ItemType Directory -Force -Path $OutAbiDir | Out-Null
    Copy-Item $SoFile $OutAbiDir -Force
    Write-Host "✅ placed $abi\liblibrespot_ffi.so"
}

Set-Location $ProjectRoot
Write-Host "Build completed successfully!"