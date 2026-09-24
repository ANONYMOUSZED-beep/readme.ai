# ReadMe.ai — Mobile (Flutter client)

The Flutter reading client for ReadMe.ai: a personal library (PDF, EPUB,
Markdown, and text uploads) with EPUB cover art and a *Continue reading*
shelf; a distraction-free reflowable reader with serif/sans typography,
Light/Sepia/Dark pages, a chapter contents sheet, automatic resume, and
bookmarks; and contextual AI explanations of any selected word, sentence, or
passage. Theme and reading preferences persist across launches
(`shared_preferences`, behind `core/storage/PreferencesStore`).

## Running locally without Firebase

With the API started with `DEV_AUTH=true` (see the root README), the client can
skip Firebase entirely and sign in as a mock user:

```bash
flutter run -d chrome --web-port 8080 \
  --dart-define=DEV_AUTH=true \
  --dart-define=API_BASE_URL=http://localhost:8000
```

On an Android emulator use `API_BASE_URL=http://10.0.2.2:8000`; debug builds
allow plain HTTP to a local API, release builds require HTTPS. A "Dev Mode"
ribbon marks development-auth builds; never ship one.

## Firebase setup (required to actually sign in)

Configuration is supplied at build time via `--dart-define` (no
`firebase_options.dart` is committed, so no credentials live in the repo).
Obtain these values from your Firebase project and Google OAuth setup:

```bash
flutter run \
  --dart-define=API_BASE_URL=http://localhost:8000 \
  --dart-define=FIREBASE_API_KEY=... \
  --dart-define=FIREBASE_APP_ID=... \
  --dart-define=FIREBASE_MESSAGING_SENDER_ID=... \
  --dart-define=FIREBASE_PROJECT_ID=... \
  --dart-define=FIREBASE_AUTH_DOMAIN=... \
  --dart-define=FIREBASE_STORAGE_BUCKET=... \
  --dart-define=GOOGLE_SERVER_CLIENT_ID=...   # for Google Sign-In token exchange
```

Platform OAuth setup (Android SHA keys, iOS URL schemes, web client id) is also
required per the Firebase/Google Sign-In docs. Without configuration the app
still launches to the login screen; sign-in then reports missing configuration.

A `--dart-define-from-file=env.json` is recommended for day-to-day development.

## Auth feature structure (feature-first)

```
lib/features/auth/
├── domain/        # AuthUser, AuthRepository (interface), AuthException
├── data/          # FirebaseAuthRepository (Firebase + Google Sign-In)
├── application/   # auth_providers (DI + state stream), auth_controller
└── presentation/  # splash_page, login_page
```

The `AuthRepository` interface hides Firebase from the application/presentation
layers; the router (`core/router`) enforces protected navigation by listening to
the auth state stream.

## Library feature structure

```
lib/features/library/
├── domain/        # Book, BookStatus, LibraryRepository (interface)
├── data/          # BookDto (JSON) + LibraryRepositoryImpl (Dio)
├── application/   # library_providers, library_controller (list/upload/delete)
└── presentation/  # library_screen, book_detail_screen, widgets/book_card
```

The authenticated landing route (`/home`) is the library; book detail is a
nested route (`/home/books/:bookId`). File selection is abstracted behind
`core/files/FilePickerService` so the upload flow is testable without the native
picker.

## Reader feature structure

```
lib/features/reader/
├── domain/        # BookContent, ContentFormat, ReadingProgress, Bookmark, repo
├── data/          # DTOs (JSON) + ReaderRepositoryImpl (Dio)
├── application/   # reader_providers (family futures), ReaderController,
│                  # ReaderSettings(+controller)
└── presentation/  # reader_screen + widgets (settings sheet, bookmarks sheet)
```

The reader (`/home/books/:bookId/read`) renders reflowable text with adjustable
font size / line spacing and light/dark mode. The server converts PDF, EPUB, and
text uploads into the same readable text, so the reader has a single rendering
path. Reading position and bookmarks use **stable character-offset anchors**
(not page numbers); the position is saved shortly after scrolling stops and
when the reader closes. Books the server could not prepare (e.g. scanned or
password-protected files) show a "not ready" message, and their detail screen
explains why and offers to try again.

## Commands

```bash
flutter pub get
flutter gen-l10n
dart run build_runner build              # Freezed / json_serializable codegen
flutter run --dart-define=...            # see Firebase setup above

# quality gates
dart format --set-exit-if-changed . && flutter analyze && flutter test
```

> Generated files (`*.g.dart`, `*.freezed.dart`, `lib/l10n/generated/`) are not
> committed; run `build_runner` and `flutter gen-l10n` after checkout.
