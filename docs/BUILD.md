# Сборка и выпуск версии

## Что нужно

- Godot **4.7.2** и шаблоны экспорта 4.7.2 (Редактор → Управление шаблонами экспорта).
- Для Android: JDK 17, Android SDK, ключ подписи в настройках редактора (Редактор → Настройки → Экспорт → Android).

## Пресеты

[`export_presets.cfg`](../export_presets.cfg):

| Пресет | Файл | Особенности |
|---|---|---|
| `Windows Desktop` | `build/PeremenyBudut.exe` | один файл, pck встроен; `tests/*` исключены |
| `Android` | `build/PeremenyBudut.apk` | Android 7.0+, горизонтальная ориентация, рендерер Compatibility |

Папка `build/` в `.gitignore`: сборки публикуются в GitHub Releases, а не в репозитории.

## Сборка из командной строки

```bash
godot --headless --path . --export-release "Windows Desktop" build/PeremenyBudut.exe
```

```bash
godot --headless --path . --export-release "Android" build/PeremenyBudut.apk
```

## Проверка на Android

- Сборка содержит только `arm64-v8a` и `armeabi-v7a`: на эмуляторе x86_64 (образ `android-34 google_apis x86_64`)
  она не запустится. Нужен телефон по `adb install -r build/PeremenyBudut.apk` или ARM-образ эмулятора.
- Без устройства проверяется то, что можно: `aapt dump badging` (пакет, `versionCode`, `minSdk 24`, право `VIBRATE`,
  нативные библиотеки), `apksigner verify` (подпись v2/v3; нужен `JAVA_HOME`) и автотест `test_phone_defaults_and_screens_fit`
  (телефонные настройки по умолчанию: интерфейс 115%, частицы средние, 60 кадров; все вкладки настроек и длинные итоги
  помещаются на экран).
- Ручной прогон на телефоне: сенсорный стик, спринт и атака одновременно тремя пальцами; свернуть игру пальцем на стике —
  после возвращения змея не едет сама; двойной тап; вкладка «Управление» в настройках показывает кнопки за панелью.

## Выпуск версии

1. Номер версии — в трёх местах:
   - `project.godot` → `config/version` (его показывает экран настроек);
   - `export_presets.cfg` → `application/file_version` и `product_version` (Windows, `X.Y.0.0`);
   - `export_presets.cfg` → `version/name` и `version/code` (Android; `code` — **всегда +1**, иначе телефон
     не поставит обновление поверх).
2. Раздел «Изменения в vX.Y» в `README.md` и запись в [CHANGELOG.md](CHANGELOG.md); в «Что внутри» — актуальный номер.
3. Все тесты зелёные (см. [TESTING.md](TESTING.md)).
4. Собрать оба пресета.
5. Коммит `Змея против Гигантской Яичницы vX.Y` с перечнем изменений, пуш в `main`.
6. Релиз:

```bash
gh release create vX.Y build/PeremenyBudut.exe build/PeremenyBudut.apk --title "Змея против Гигантской Яичницы vX.Y" --notes-file notes.md
```

В заметках к релизу — тот же список изменений, что в README, и строка «Скачать».
