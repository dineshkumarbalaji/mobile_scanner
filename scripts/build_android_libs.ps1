# PowerShell script to build libllama.so for Android ABIs and copy into jniLibs.
# Usage: run from workspace root in PowerShell (Windows). Requires CMake and NDK installed.

param(
    [string]$NdKPath = $env:ANDROID_NDK_HOME,
    [string[]]$Abis = @('arm64-v8a', 'x86_64', 'armeabi-v7a')
)

if (-not $NdKPath) {
    Write-Error "ANDROID_NDK_HOME is not set. Please supply via environment variable or -NdKPath argument."
    exit 1
}

$abis = $Abis
Write-Host "Requested ABIs: $($abis -join ', ')"
$ProjectRoot = (Resolve-Path "$PSScriptRoot\..").Path
$llamaSrc = Join-Path $ProjectRoot 'packages/llama_cpp_dart/src/llama.cpp'
$jniRoot = Join-Path $ProjectRoot 'android/app/src/main/jniLibs'

Write-Host "Using NDK at $NdKPath"
Write-Host "LLAMA source: $llamaSrc"
Write-Host "Building for ABIs: $($abis -join ', ')"

foreach ($abi in $abis) {
    Write-Host "`n=== Building $abi ==="
    $buildDir = Join-Path $ProjectRoot "packages/llama_cpp_dart/build-android/$abi"    # start fresh to avoid cached CMake variables from previous attempts
    if (Test-Path $buildDir) {
        Remove-Item -Recurse -Force $buildDir
    }    New-Item -ItemType Directory -Force -Path $buildDir | Out-Null
    Push-Location $buildDir
    # configure with PowerShell argument array to avoid newline/quoting mishaps
    $cmakeArgs = @(
        "-G", "Ninja",
        "-DCMAKE_BUILD_TYPE=Release",
        "-DLLAMA_BUILD_TESTS=OFF",             # don't compile unit tests on Android
        "-DLLAMA_BUILD_TOOLS=OFF",             # skip building CLI/server tools which pull in host-only code
        "-DLLAMA_OPENSSL=OFF",                # disable OpenSSL to avoid extra dependencies
        "-DGGML_VULKAN=OFF",                  # disable Vulkan to avoid GPU device validation errors on emulator
        "-DGGML_CUDA=OFF",                    # disable CUDA (not available on Android anyway)
        "-DGGML_METAL=OFF",                   # disable Metal (iOS only)
        "-DGGML_OPENBLAS=OFF",                # disable OpenBLAS
        "-DCMAKE_TOOLCHAIN_FILE=$NdKPath/build/cmake/android.toolchain.cmake",
        "-DANDROID_ABI=$abi",
        "-DANDROID_PLATFORM=android-21",
        "-DBUILD_SHARED_LIBS=ON",
        "$llamaSrc"
    )
    & cmake @cmakeArgs
    & cmake --build . --config Release
    Pop-Location

    $targetDir = Join-Path $jniRoot $abi
    # clean any previous libs to avoid stale mismatched binaries
    if (Test-Path $targetDir) {
        Remove-Item -Recurse -Force $targetDir
    }
    New-Item -ItemType Directory -Force -Path $targetDir | Out-Null

    # copy the main shared libraries built by CMake (usually placed under buildDir/bin)
    # use a recursive search to catch them regardless of exact location
    Get-ChildItem -Path $buildDir -Filter "*.so" -Recurse | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination $targetDir -ErrorAction SilentlyContinue
    }
    # also pull the matching libomp from the NDK (necessary for OpenMP support)
    $clangLibDirOld = Join-Path $NdKPath "toolchains/llvm/prebuilt/windows-x86_64/lib64/clang"
    $clangLibDirNew = Join-Path $NdKPath "toolchains/llvm/prebuilt/windows-x86_64/lib/clang"
    $clangLibDir = if (Test-Path $clangLibDirNew) { $clangLibDirNew } else { $clangLibDirOld }
    
    # find latest clang version directory, if it exists
    $clangVersion = $null
    if (Test-Path $clangLibDir) {
        $clangVersion = Get-ChildItem -Directory $clangLibDir | Sort-Object Name -Descending | Select-Object -First 1
    }
    if ($clangVersion) {
        switch ($abi) {
            'arm64-v8a' { $ompAbi = 'aarch64' }
            'armeabi-v7a' { $ompAbi = 'arm' }
            'x86_64' { $ompAbi = 'x86_64' }
            default { $ompAbi = $null }
        }
        if ($ompAbi) {
            # build full path to libomp.so inside clang version directory
            $ompPath = Join-Path $clangLibDir $clangVersion.Name
            $ompPath = Join-Path $ompPath "lib/linux/$ompAbi/libomp.so"
            if ($ompPath -and (Test-Path $ompPath)) {
                Copy-Item -Path $ompPath -Destination $targetDir -ErrorAction SilentlyContinue
                Write-Host "Copied libomp.so for $abi from NDK"
            }
            else {
                Write-Warning "libomp.so not found for $abi at $ompPath"
            }
        }
    }
    else {
        Write-Warning "clang directory not found at $clangLibDir, skipping libomp copy"
    }

    Write-Host "Copied libraries to $targetDir"
}

Write-Host "Build complete. Run 'flutter clean' and rebuild to include new libraries."