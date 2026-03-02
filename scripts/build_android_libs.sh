#!/usr/bin/env bash
# Build libllama.so for multiple Android ABIs and copy into the Flutter app's
# jniLibs directory.  Intended to be run from the workspace root.

set -euo pipefail

if [[ -z "${ANDROID_NDK_HOME:-}" ]]; then
    echo "ERROR: ANDROID_NDK_HOME is not set.  Please point it at your Android NDK."
    exit 1
fi

# ABIs to produce.  The emulator default is x86_64; real devices are arm64-v8a,
# armeabi-v7a, etc.  Edit this list if you only need a subset.
ABIS=(arm64-v8a x86_64 armeabi-v7a)

LLAMA_SRC="$(pwd)/packages/llama_cpp_dart/src/llama.cpp"
JNI_LIBS_ROOT="$(pwd)/android/app/src/main/jniLibs"

echo "Using NDK at $ANDROID_NDK_HOME"
echo "LLAMA source: $LLAMA_SRC"

echo "Building for ABIs: ${ABIS[*]}"

for ABI in "${ABIS[@]}"; do
    echo "\n=== Building $ABI ==="
    BUILD_DIR="$(pwd)/packages/llama_cpp_dart/build-android/$ABI"
    mkdir -p "$BUILD_DIR"
    pushd "$BUILD_DIR" > /dev/null
    cmake -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake" \
          -DANDROID_ABI=$ABI \
          -DANDROID_PLATFORM=android-21 \
          -DBUILD_SHARED_LIBS=ON \
          "$LLAMA_SRC"
    cmake --build . --config Release -j$(nproc || echo 4)
    popd > /dev/null

    # copy libraries into jniLibs
    TARGET_DIR="$JNI_LIBS_ROOT/$ABI"
    mkdir -p "$TARGET_DIR"
    # libllama.so plus any ggml libs
    cp -v "$BUILD_DIR"/libllama.so "$TARGET_DIR/" || true
    cp -v "$BUILD_DIR"/libggml*.so "$TARGET_DIR/" || true
    cp -v "$BUILD_DIR"/libmtmd.so "$TARGET_DIR/" || true
    echo "Copied libraries to $TARGET_DIR"
done

echo "Build complete. Run 'flutter clean' then rebuild to include the new
libraries."
