<!-- Copilot instructions for the `mobile_scanner` Flutter app -->
# Copilot instructions — mobile_scanner

Purpose
- Help contributors implement a GLM-backed OCR flow and maintain the Flutter UI.

Big picture
- Flutter app (`lib/main.dart`) with a small screen-based UI under `lib/ui/`: `HomeScreen`, `CameraScreen`, `PreviewScreen`, `ResultScreen`.
- Camera capture -> pass image path to preview -> `OcrService.extractText` returns `OcrResult` -> `ResultScreen` renders Markdown.
- OCR service is currently mocked: `lib/services/ocr_service.dart` contains a simulated response and a TODO to replace with a real GLM-OCR endpoint.

Key files and responsibilities
- `lib/main.dart`: app entry, MaterialApp, sets `HomeScreen` as home.
- `lib/ui/home_screen.dart`: starts camera flow by calling `availableCameras()` and pushing `CameraScreen`.
- `lib/ui/camera_screen.dart`: manages `CameraController`, takes pictures and navigates to `PreviewScreen` with `image.path`.
- `lib/ui/preview_screen.dart`: shows captured image and calls `OcrService.extractText(File(path))` to process.
- `lib/services/ocr_service.dart`: central integration point for OCR — replace mock here with an HTTP Multipart upload to the GLM-OCR API and parse into `OcrResult`.
- `lib/models/ocr_result.dart`: canonical data model for OCR results. Use `OcrResult.fromJson` when parsing API responses.
- `lib/ui/result_screen.dart`: renders `result.text` using `flutter_markdown`.

Patterns & conventions (project-specific)
- Minimal service objects: services are plain classes (no DI framework required). Instances are created where needed (`PreviewScreen` creates `OcrService`).
- Screens pass simple primitives (e.g., `CameraDescription`, `imagePath`) through constructors rather than providers or global state.
- UI uses `Navigator.of(context).push(MaterialPageRoute(...))` for screen transitions — keep that style when adding screens.
- Use `debugPrint` and `ScaffoldMessenger.of(context).showSnackBar(...)` for lightweight debugging and user errors (this project uses those patterns).

Developer workflows & commands
- Install dependencies: `flutter pub get`.
- Run on Android emulator: `flutter run -d <android_device_id>` (use `flutter devices` to list devices).
- Run on Windows (desktop): `flutter run -d windows` (project contains a `windows/` runner).
- Run tests: `flutter test` (only `test/widget_test.dart` exists currently).
- iOS: requires macOS + Xcode; iOS runner exists under `ios/` but CI or contributors on macOS only.

Integration notes (what to change for a real backend)
- Replace the mock in `lib/services/ocr_service.dart`: use `http.MultipartRequest` to upload the image to your GLM-OCR endpoint (there's an `_apiUrl` TODO comment already).
- Parse the JSON response into `OcrResult.fromJson(...)` and return that.
- Keep `confidence` and `text` fields populated; `structuredData` may be JSON/Markdown depending on API.

Testing and debugging tips
- The code uses a mocked OCR, so unit/feature testing of UI flow can be done locally without external services.
- To test real API integration, create a small feature flag or environment var to toggle between mock and real service in `OcrService`.
- Camera behavior: `availableCameras()` is invoked in `HomeScreen` before navigating; ensure emulator/device has camera support or use an image picker in tests.

Where to look for TODOs
- `lib/services/ocr_service.dart`: implement API call (commented `TODO`).
- `lib/ui/result_screen.dart`: clipboard and save-to-file actions are `TODO`.

If you are editing code
- Follow existing file layout: `lib/ui/` for screens, `lib/services/` for backend integrations, `lib/models/` for data models.
- Keep changes minimal and follow the existing navigation style.

Questions for maintainers
- Preferred API auth method for GLM-OCR (API key, bearer token, service account)?
- Expected structured output format (JSON schema or Markdown preference)?

Thanks — please point me to anything missing or any internal API docs to include.
