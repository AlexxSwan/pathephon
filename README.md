# Патефон / Pathephon — All-format retro-tube audio player for Android x64

> All-formats · x86_64 + arm64-v8a · Material 3 with vintage vacuum-tube UI ·
> 10-band parametric EQ · ReplayGain · audiobook bookmarks · sleep timer ·
> tag editor · Media3 foreground service · RU + EN i18n.

> Project namespace: `com.swanlab.audiox64`
> Sister project: [github.com/AlexxSwan/audio-converter](https://github.com/AlexxSwan/audio-converter) — same keystore, same sunset-gradient icon background.

---

## App icon

- **Foreground**: pathephon / gramophone silhouette (HMV-style horn + turntable + crank) — `android/app/src/main/res/drawable/tube_icon_foreground.xml`
- **Background**: sunset gradient `#FF3B30 → #FF9500 → #FFCC00` (red → orange → yellow) — same as audio-converter for visual continuity across the SwanLab product line. File: `android/app/src/main/res/drawable/tube_icon_background.xml`
- **Adaptive icon**: `mipmap-anydpi-v26/ic_launcher.xml` (and `ic_launcher_round.xml`) wire background + foreground together; monochrome variant uses the same foreground for Android 13+ themed icons.

---

## 1. Что в коробке

| Layer | Stack |
|---|---|
| UI framework | Flutter 3.24+ (Dart 3.4+) |
| Audio engine | **just_audio** (ExoPlayer under the hood on Android) |
| MediaSession bridge | `audio_service` — lockscreen / Bluetooth / Android Auto |
| State | Riverpod 2 (`flutter_riverpod`) |
| Models | Plain Dart immutable classes (no codegen) |
| Persistence | `shared_preferences` JSON — playlists, EQ presets, bookmarks |
| Audio metadata | `on_audio_query` (MediaStore-backed) |
| Background playback | `audio_service` MediaSession foreground service |
| Localization | `flutter_localizations` + `.arb` (RU + EN), Per-app language API (Android 13+) |
| Min SDK | **26 (Android 8.0)** — covers ~95 % of x64 modern devices |
| Target SDK | 34 (Android 14) — required for `foregroundServiceType=mediaPlayback` |
| ABIs | `x86_64` (primary per requirement) + `arm64-v8a` (Play Store parity) |

### Supported formats (MVP)

Native ExoPlayer decoding via just_audio:

| Group | Extensions |
|---|---|
| Base | MP3, FLAC, WAV, OGG/Vorbis, Opus, AAC/M4A, ALAC |

Listed in the format safelist but may require FFmpeg for actual playback (post-MVP):

| Group | Extensions |
|---|---|
| Audiophile | APE, WavPack, TTA, MPC |
| Chip-tune | MOD, S3M, XM, IT |
| Exotic | DSF/DSD/DFF, AMR, 3GP, M4B (with chapters), MKA, OFR, SPX |

For these exotic formats, the UI gracefully reports playback errors — full FFmpeg integration is on the post-MVP TODO list.

---

## 2. Архитектура

```
lib/
├── main.dart                       entry point + ProviderScope
├── app.dart                        MaterialApp, router, locale wiring
├── core/
│   ├── theme/
│   │   ├── tube_colors.dart        палитра (amber/brass/phosphor/OLED-black)
│   │   ├── retro_theme.dart        Material 3 ThemeData
│   │   └── vu_painter.dart         CustomPainter — vintage VU-метр
│   ├── l10n/
│   │   ├── app_ru.arb              русская локализация
│   │   ├── app_en.arb              английская локализация
│   │   └── generated/              AppLocalizations (после `flutter gen-l10n`)
│   └── utils/
│       ├── duration_format.dart    tape-counter форматтеры
│       └── replaygain.dart         dB → volume scale
├── data/
│   ├── sources/
│   │   ├── mediastore_source.dart  on_audio_query wrapper + формат safelist
│   │   └── tag_source.dart         on_audio_query tag reader + RG-парсер
│   └── repositories/
│       ├── library_repository.dart scan + albums + playlists (shared_prefs JSON)
│       └── audiobook_repository.dart discovery + bookmarks (shared_prefs JSON)
├── domain/
│   ├── enums/repeat_mode.dart
│   └── models/                    Plain Dart immutable classes (no Freezed)
│       ├── track.dart             + toJson/fromJson
│       ├── album.dart
│       ├── playlist.dart          + toJson/fromJson
│       ├── audiobook.dart         + Chapter + toJson/fromJson
│       └── bookmark.dart          + toJson/fromJson
├── services/
│       ├── playback_service.dart       just_audio + audio_service (real playback)
│   ├── equalizer_service.dart      just_audio AndroidEqualizer + presets
│   └── audio_book_service.dart     sleep timer + bookmarks + auto-resume
└── presentation/
    ├── providers/providers.dart    Riverpod wiring (single file for MVP)
    ├── screens/
    │   ├── library_screen.dart     All tracks / Albums / Artists / Playlists
    │   ├── now_playing_screen.dart VU-meter + art + seek + controls
    │   ├── equalizer_screen.dart   10 knobs + presets + ReplayGain toggle
    │   ├── tag_editor_screen.dart  ID3/Vorbis/FLAC editor
    │   └── audiobooks_screen.dart  list + sleep timer + bookmarks
    └── widgets/
        ├── vu_meter.dart
        ├── tube_knob.dart          rotary knob for EQ
        ├── retro_button.dart       chassis button with amber glow
        ├── track_list_tile.dart
        └── playback_controls.dart
```

---

## 3. Подготовка к сборке

### 3.1. Установить Flutter

```bash
# Рекомендованный канал stable ≥ 3.22
flutter --version
# Flutter 3.22.x • channel stable
```

### 3.2. Установить NDK

Через Android Studio → SDK Manager → SDK Tools → NDK Side-by-side
(используется `27.0.12077973` — см. `android/app/build.gradle.kts`).

### 3.3. Сгенерировать локализацию

MVP не использует Freezed/Drift/build_runner — только l10n codegen:

```bash
cd audio_player_x64
flutter pub get
flutter gen-l10n
```

После этого в `lib/core/l10n/generated/` появятся `app_localizations.dart` и `_ru`/`_en` реализации. CI делает это автоматически.

---

## 4. Подпись (тот же keystore, что у audio-converter)

Подпись настраивается так же, как в `AlexxSwan/audio-converter`:

- `key.properties` лежит в `android/key.properties` (на уровне rootProject)
- keystore-файл лежит в `android/app/upload-keystore.jks`
- `storeFile=upload-keystore.jks` (имя файла, разрешается относительно `android/app/`)

### 4.1. Локальная сборка

1. Скопируйте ваш существующий keystore в `android/app/upload-keystore.jks`.
2. Скопируйте `android/key.properties.example` → `android/key.properties`
   и заполните реальными значениями:
   ```properties
   storePassword=РЕАЛЬНЫЙ_ПАРОЛЬ_ХРАНИЛИЩА
   keyPassword=РЕАЛЬНЫЙ_ПАРОЛЬ_КЛЮЧА
   keyAlias=upload
   storeFile=upload-keystore.jks
   ```
3. **Никогда не коммитьте `key.properties` и `*.jks`** — они уже в `.gitignore`.

Сборка release-APK с правильной подписью:

```bash
flutter build apk --release --split-per-abi
```

> `build.gradle.kts` уже включает `enableV1..V4Signing = true` —
> APK будет подписан всеми актуальными схемами (JAR, v2, v3, v4).

### 4.2. CI/CD — GitHub Actions (с твоими ключами)

Workflow живёт в `.github/workflows/build-android.yml` и подписывает APK тем же
keystore, что и audio-converter. Один раз настроить секреты в репо:

| Secret | Что положить |
|---|---|
| `KEYSTORE_BASE64` | `base64 -w0 upload-keystore.jks` — base64 твоего `.jks` |
| `KEYSTORE_PASSWORD` | пароль от keystore (`storePassword`) |
| `KEY_ALIAS` | alias ключа внутри keystore (у audio-converter это `upload`) |
| `KEY_PASSWORD` | пароль от самого ключа (`keyPassword`) |

Команда для получения `KEYSTORE_BASE64` на локальной машине:

```bash
base64 -w0 upload-keystore.jks > keystore.b64
# содержимое keystore.b64 вставить в GitHub Secret KEYSTORE_BASE64
```

Триггеры workflow:
- `push` в `main` → сборка + артефакты (30 дней хранения)
- `workflow_dispatch` → ручной запуск
- `push tag v*` → сборка + автоматический GitHub Release с APK приложенным

Артефакты:
- `Pathephon-x86_64` → `app-x86_64-release.apk`
- `Pathephon-arm64-v8a` → `app-arm64-v8a-release.apk`

---

## 5. Сборка под x64

x86_64 уже выбран как primary ABI в `android/app/build.gradle.kts`:

```kotlin
ndk {
    abiFilters += listOf("x86_64", "arm64-v8a")
}
```

Если arm64 не нужен (только внутренняя раздача APK для x64-эмулятора/устройств):

```kotlin
ndk {
    abiFilters += listOf("x86_64")
}
```

Для проверки ABI в собранном APK:

```bash
unzip -p build/app/outputs/flutter-apk/app-release.apk lib/*/libmedia3-decoder.flac.so | file -
# должно вывести: ELF 64-bit LSB shared object, x86-64
```

---

## 6. Запуск на устройстве

```bash
flutter devices            # выбрать x86_64 устройство / эмулятор
flutter run --release      # release-режим даёт реальную картину производительности
```

При первом запуске приложение запросит `READ_MEDIA_AUDIO` (Android 13+) или
`READ_EXTERNAL_STORAGE` (Android ≤ 12). Без разрешения библиотека будет пустой.

---

## 7. Дальнейшие шаги (post-MVP)

Что уже работает в MVP: список треков, play/pause/next/prev, shuffle/repeat,
seek-bar, VU-метр (синтетический), UI эквалайзера + переключение пресетов,
экран аудиокниг с закладками и sleep-timer, просмотр тегов.

Что требует доработки:

| TODO | Файл | Что добавить |
|---|---|---|
| Реальный VU-метр | `playback_service.dart` | Заменить pseudo-random на `Visualizer` AudioEffect по audioSessionId |
| Tag write-back | `tag_source.dart` | Нативный MethodChannel bridge для записи ID3/Vorbis/MP4 в файл |
| FFmpeg fallback | `pubspec.yaml` + `playback_service.dart` | Подключить `media_kit` для DSF/AMR/M4B/tracker-форматов |
| LRC-тексты | `now_playing_screen.dart` | LRC-парсер + автопоиск через LRCLIB API |
| CUE sheets | `library_repository.dart` | Парсинг `.cue` и виртуальное разбиение FLAC/WAV на треки |
| Настройки | `app.dart` | Экран настроек: тема, язык, интервал авто-сканирования |
| Альбомный детальный вид | `library_screen.dart` | Drill-down в альбом со списком треков |
| Поиск | `library_screen.dart` | Фильтр по title/artist/album |
| Очереди | `now_playing_screen.dart` | Перетаскивание треков в очереди, undo |

---

## 8. Лицензия

MIT — делайте что хотите. Атрибуция приветствуется.

## 9. Контакты

- Repo: github.com/AlexxSwan/pathephon (предполагается)
- Sister project: github.com/AlexxSwan/audio-converter
- Author: SwanLab
