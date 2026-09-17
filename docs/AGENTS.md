---
audience: агенты и разработчики
updated: 2026-09-17
---

# AGENTS.md — точка входа

Проект **Chelka**: полка в чёлке MacBook (drag-and-drop приёмник/источник)
с синхронизацией файлов на второй Mac через Tailscale.
Инструкции пользователя (установка на один Mac и связка двух машин) —
[README.md](../README.md) / [README.ru.md](../README.ru.md),
архитектура — [ADR-0001](architecture/decisions/ADR-0001-notch-shelf-sync.md).

## Сборка / тесты / запуск

```bash
make build    # swift build (отладочная)
make test     # swift run chelka-selftest — тесты чистой логики
make app      # собирает build/Chelka.app (LSUIElement, ad-hoc подпись)
make run      # make app + open build/Chelka.app
make install  # ставит в /Applications и запускает (перезапуск — Spotlight: «Chelka»)
make deploy   # install + push сборки на вторую машину по ssh и перезапуск там
```

`make deploy` берёт хост второй машины из `make deploy PEER=<host>` либо из
`defaults read dev.mike.Chelka deployPeer` (задать один раз:
`defaults write dev.mike.Chelka deployPeer <host>`). Требует настроенного
ssh-доступа по ключу — рецепт связки машин см. в README, раздел
«два Mac через Tailscale».

Автозапуск при входе: правая кнопка по полке → «Запускать при входе»
(SMAppService, работает надёжно из /Applications).

Требования: macOS 13+, Swift 6 (достаточно Command Line Tools, полный Xcode не нужен).

## Структура

- `Sources/ChelkaCore/` — чистая логика без AppKit (тестируется selftest'ом).
- `Sources/Chelka/` — приложение: `AppDelegate` (геометрия чёлки, экраны),
  `ShelfPanel` (NSPanel поверх чёлки), `ShelfView` (drop-target + drag-source + отрисовка),
  `ShelfStore` (папка `~/Shelf` + watcher), `ThumbnailCache` (превью QuickLook),
  `Transport` (rsync/ssh push).
- `Sources/chelka-selftest/` — исполняемые проверки (см. «подводные камни»).
- `scripts/make-icon.swift` — генерация иконки из `Resources/icon-art.jpg`
  (константы кропа подобраны под конкретный арт).

## Использование

- Перетащить файл на чёлку — он падает на полку (`~/Shelf`) и, если задан `peerHost`,
  уезжает на вторую машину в такую же папку.
- Навести курсор на чёлку — полка раскрывается; файлы вытаскиваются drag'ом
  (в Telegram — станет вложением). Картинки/PDF/видео показываются превью.
- Правая кнопка по файлу: убрать с полки (в Корзину), показать в Finder,
  повторить отправку; по пустому месту — автозапуск, выход.
- Точка на иконке: оранжевая — отправляется, зелёная — доставлено, красная — ошибка
  (5 попыток с интервалом 15 с исчерпаны).

## Подводные камни

- **Тестовых фреймворков нет без Xcode**: с одними CLT `swift test`
  падает с «no such module 'XCTest'/'Testing'». Поэтому тесты — обычный
  исполняемый таргет `chelka-selftest` с exit-кодом.
- **`.nonactivatingPanel` обязателен**, иначе окно заберёт фокус и drag из Finder сорвётся.
- **Ложные mouseEnter/Exit при анимации кадра**: AppKit пересоздаёт tracking-зоны
  при resize окна под курсором → без гистерезиса (150 мс + проверка, что курсор
  реально вне окна) полка мигает.
- **SSH-транспорт работает в BatchMode**: ключ пира — только без passphrase и
  лучше выделенный, прописанный через `~/.ssh/config` с `IdentitiesOnly yes`
  (ключи с нестандартными именами файлов ssh сам не предъявляет, а
  `ssh-copy-id` без `-i` копирует первый попавшийся — «пароль проходит, ключ нет»).
- **`authorized_keys`, принадлежащий root**: встречается как артефакт старых
  настроек — в него нельзя дописать, и sshd его отвергает из-за прав. Лечение:
  `sudo rm`, пересоздать от своего пользователя, `chmod 600`.
- **Перенос .app между машинами — только rsync/scp**: AirDrop ставит quarantine,
  Gatekeeper блокирует ad-hoc подпись.
- **Push-only**: удаление файла с полки не синхронизируется на другую машину (намеренно).
- rsync пишет во временный дот-файл и переименовывает атомарно; полка скрытые
  файлы не показывает, поэтому недокачанный файл в UI не попадёт. Для **папок**
  это не так — папка видна на приёмнике до конца докачки содержимого.
- Полка без скролла: показывается столько файлов, сколько влезает по ширине.
