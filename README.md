# PDF Genesis (Flutter app)

Mobile client for **PDF Genesis - Ask Anything From PDF**. Flutter, Riverpod, go_router, Dio.

## Run

```bash
flutter pub get
flutter run \
  --dart-define=API_BASE_URL=http://10.0.2.2:8190 \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=<web-oauth-client-id>.apps.googleusercontent.com
```

`10.0.2.2` is the host machine from the Android emulator. On a real phone use your computer's LAN IP, and set the backend's `S3_ENDPOINT` to the same IP so the phone can reach the presigned upload URL.

| Define | Purpose | Default |
| --- | --- | --- |
| `API_BASE_URL` | Backend origin (without `/api/v1`) | `http://10.0.2.2:8190` |
| `GOOGLE_SERVER_CLIENT_ID` | OAuth **Web** client ID; must also be in the backend's `GOOGLE_CLIENT_IDS` | empty |
| `PRIVACY_POLICY_URL`, `TERMS_URL` | Legal links | placeholders |

Google Sign-In on Android also needs an **Android** OAuth client in the same Google Cloud project, with package `technology.sct.pdf_genesis` and the signing certificate's SHA-1.

## Checks

```bash
flutter analyze
flutter test
```

## Structure

```
lib/
  main.dart
  core/
    config/      build-time configuration
    layout/      breakpoints, width-capped content, adaptive grid
    network/     ApiClient (auth header, token refresh, envelope), ApiException
    router/      go_router routes and auth redirect
    services/    analytics and ads seams (no-op implementations)
    storage/     secure token storage, preferences
    theme/       colours and ThemeData from the Stitch design system
    widgets/     shared widgets
  features/
    auth/        splash, onboarding, login; AuthController
    home/        bottom navigation shell, Home
    documents/   list, upload, processing, detail, summary
    chat/        chat with a document
    profile/     profile, settings, Pro plan
    viewer/      PDF viewer, editor (pen, highlight, text, signature), page organiser
```

## PDF viewer and editor

Built on [pdfrx](https://pub.dev/packages/pdfrx) (MIT, PDFium).

- The PDF is downloaded once into the app cache (`PdfFileStore`) and re-downloaded only when its `version` changes.
- Edits are kept as normalised marks (`EditSession`) until Save. `PdfMarkWriter` then writes them into the file as real page content through PDFium, so they show in any PDF reader. Saved edits cannot be removed afterwards.
- Typed notes in Latin-1 text are written as real, searchable text in the standard Helvetica font. Notes in any other script (Devanagari, Gujarati, Arabic, CJK, emoji) are drawn by Flutter, which shapes them correctly, and placed as an image; they look right in every reader but are not searchable and are not read by the assistant.
- Page changes are saved by copying the pages into a new document (`assemblePages`): pdfrx 2.6 skips a pure reorder done in place.
- If PDFium refuses any mark, the save fails as a whole (`PdfWriteException`) and the marks stay in the editor.
- A save uploads the new file with `/documents/:id/revision`. Typed notes and page changes reprocess the document for the assistant; drawings alone do not.

Each feature has `data/` (models and repository), `presentation/` (screens) and, where there is logic to share or test, `application/` (controllers and services). Screen locations live in `core/router/routes.dart`. Screens read data through Riverpod providers; repositories are the only code that talks to the API.

## Screen sizes

The app adapts to phones, landscape and tablets (`core/layout/responsive.dart`):

- Below 600 dp wide: bottom navigation bar, single column.
- From 600 dp: side navigation rail; document lists become a grid.
- Wide windows: Home shows upload and recent documents side by side; forms and reading screens are centred at a comfortable width instead of stretching.

`test/widget/responsive_test.dart` lays every screen out on seven surfaces (small phone, large text, landscape, tablets) and fails on any overflow. Tests load the real fonts (`test/flutter_test_config.dart`), so the widths match a device.

Fonts (Inter, Plus Jakarta Sans) are bundled under `assets/fonts` with their OFL licences.
