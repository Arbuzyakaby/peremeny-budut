# Тесты

Своя лёгкая система без аддонов: [`tests/run_tests.gd`](../tests/run_tests.gd) (точка входа),
[`tests/test_runner.gd`](../tests/test_runner.gd) (раннер), [`tests/test_case.gd`](../tests/test_case.gd)
(базовый класс и проверки).

## Запуск

```bash
godot --headless --path . -s res://tests/run_tests.gd
```

| Аргумент (после `--`) | Что делает |
|---|---|
| `--only=текст` | только наборы и тесты, в имени которых есть эта подстрока |
| `--unit` | только юнит-тесты |

На GitHub тесты идут при каждом пуше в `main` и на каждый PR (`.github/workflows/tests.yml`, Godot 4.7.2 под Linux).

## Как написать тест

```gdscript
extends "res://tests/test_case.gd"

func test_что_проверяем() -> void:
	var n: Node = add(Something.new())  # узел удалится после теста
	await frames(2)                     # тесты могут ждать кадры и таймеры
	assert_near(n.value, 1.0, 0.01, "подпись, которая объяснит провал")
```

- Файл — в `tests/unit/` (без игры) или `tests/integration/` (с игрой); имя набора — `test_*.gd`.
- Проверки: `assert_true/false`, `assert_eq/ne`, `assert_near`, `assert_between`, `assert_gt`, `assert_has`, `assert_len`.
- `before_each()` / `after_each()` — вокруг каждого теста; `use_temp_storage()` перенаправляет
  сохранения и настройки во временную папку `user://test/` — настоящие не трогаются.
- Интеграционные наборы наследуют [`tests/integration/game_case.gd`](../tests/integration/game_case.gd):
  `boot()` поднимает игру в меню, `boot_stage(n, diff)` — сразу на этапе.

## Что покрыто

- **Юнит:** баланс, навыки, бой, настройки и миграция формата, сохранения, синтез звуков, шина звука
  (лимит голосов, разброс, ducking, тишина), змея, враги и приёмы вилок, раскладка клавиш, симуляция
  пожара, приборные контролы, дизайн-язык (включая видимый отказ и скорость отклика), советы, картотека,
  испытание дня, повтор, текстуры, иконки.
- **Интеграция:** весь забег, финал и пожар, экраны (включая «настройки помещаются без прокрутки»),
  тач-управление, кооперативный ИИ, панель разработчика с настоящими нажатиями F1, ё и Ctrl+Shift+D,
  тень акцента при открытом желтке.

## Визуальная проверка

Тесты не видят картинку, поэтому после изменений интерфейса снимай кадры:

```bash
godot --path . -- --open=settings --shots=90
```

Снимки — в `user://shots` (на Windows `%APPDATA%/Godot/app_userdata/Snake Game/shots`).
`--open=` принимает `pause`, `end`, `win`, `perks`, `skills`, `settings`, `bestiary`; `--settings-tab=N` открывает
настройки на вкладке N.
