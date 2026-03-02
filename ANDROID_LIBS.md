# Android native libraries for llama_cpp_dart

This project uses `llama_cpp_dart`, which depends on a native shared library
`libllama.so` built from the `llama.cpp` repo.  The Flutter package doesn't ship
prebuilt binaries, so you must compile and bundle them yourself.

## ABI compatibility

Android apps include native libraries in `android/app/src/main/jniLibs/<ABI>/`.
The emulator/device loads the library that matches its CPU architecture.  For
example, the default Android 64-bit emulator (`sdk gphone64 x86 64`) requires
an `x86_64` version of `libllama.so`; the arm64 emulator or a real arm device
requires `arm64-v8a`.

If you only place a single ABI (e.g. `arm64-v8a/libllama.so`) and run on an
incompatible emulator, the app will fail with:

```
LlamaException: Failed to initialize Llama (Invalid argument(s): Failed to load dynamic library 'libllama.so': dlopen failed: library "libllama.so" not found)
```

That's because the runtime can't find the library for the current architecture.

### Steps to include libraries for all ABIs you intend to support:

1. Build `libllama.so` for each ABI (arm64-v8a, x86_64, armeabi-v7a, etc.)
   using the Android NDK.  Example commands:

   ```bash
   # set NDK path appropriately:
   export ANDROID_NDK_HOME="C:/Android/android-ndk-r25"   # Windows
   
   for ABI in arm64-v8a x86_64 armeabi-v7a; do
     mkdir -p build-android/$ABI && cd build-android/$ABI
     cmake -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake" \
           -DANDROID_ABI=$ABI \
           -DANDROID_PLATFORM=android-21 \
           -DBUILD_SHARED_LIBS=ON \
           ../../packages/llama_cpp_dart/src/llama.cpp
     cmake --build . --config Release -j
     cd -
   done
   ```

2. Copy the resulting `libllama.so` (and any companion libraries like
   `libggml.so`) into the corresponding `jniLibs/<ABI>/` folders under the
   Flutter project:

   ```
   cp build-android/arm64-v8a/libllama.so android/app/src/main/jniLibs/arm64-v8a/
   cp build-android/x86_64/libllama.so   android/app/src/main/jniLibs/x86_64/
   # repeat for other ABIs as needed
   ```

3. Clean and rebuild the app:

   ```bash
   flutter clean
   flutter run -d <device-or-emulator>
   ```

   Make sure the selected device matches one of the included ABIs.  For the
   default emulator (`sdk gphone64 x86 64`), you'll need the `x86_64` library.

---

### Automated build script

Helper scripts are included under `scripts/` which build the required shared
libraries for a set of ABIs and copy them into the appropriate `jniLibs/` folders.

* **Unix-style shell** (`build_android_libs.sh`):

```bash
# run from workspace root (Git Bash, WSL, etc.)
export ANDROID_NDK_HOME="C:/Path/To/android-ndk"  # e.g. E:\DevTools\Android\Sdk\ndk\29.0.14206865
bash scripts/build_android_libs.sh
```

* **Windows PowerShell** (`build_android_libs.ps1`):

```powershell
# run from workspace root in PowerShell
$env:ANDROID_NDK_HOME = 'E:\DevTools\Android\Sdk\ndk\29.0.14206865'
# or specify path explicitly:
# .\scripts\build_android_libs.ps1 -NdKPath 'E:\DevTools\Android\Sdk\ndk\29.0.14206865'
.
```

You can edit the `ABIS` array inside the script if you only need specific
architectures.

After running the script, perform a clean rebuild of your Flutter app as shown
above.

4. Optional: if you don't plan to target the emulator, simply run on a real
   arm/arm64 device; then only the corresponding ARM libraries must be present.

## Verifying the APK

After building, inspect the APK to confirm that the native libs were packaged:

```bash
unzip -l build/app/outputs/flutter-apk/app-debug.apk | grep libllama.so
```

You'll see entries under `lib/arm64-v8a/`, `lib/x86_64/`, etc.

--

Keeping the `jniLibs` directories up to date and matching the emulator/device
architecture is the key to avoiding the "not found" error.
