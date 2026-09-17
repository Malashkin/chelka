---
audience: разработчики проекта
updated: 2026-09-17
---

# ADR-0001: Полка в чёлке с синхронизацией на удалённый Mac mini через Tailscale

Статус: принято · Дата: 2026-09-17

## Контекст

Нужно приложение для macOS: файл перетаскивается в область чёлки MacBook
(«полка»), после чего его можно вытащить drag'ом:

1. локально на MacBook (например, вложением в Telegram);
2. на удалённом Mac mini, к которому пользователь подключён через Tailscale
   (Screen Sharing), — вытащить из полки уже на стороне mini.

Ограничение платформы: drag-and-drop в macOS — механизм одной машины
(pasteboard и drag-сессия живут в локальном WindowServer). Перетащить файл
курсором между машинами или «сквозь» окно Screen Sharing нельзя — Screen
Sharing передаёт файлы только через clipboard, drag файлов внутрь окна не
является файловой передачей.

## Решение

**Синхронизируемая полка.** Одно и то же приложение работает на обеих машинах:

- UI — прозрачная панель над чёлкой (`NSPanel`, `.nonactivatingPanel`,
  `level = .statusBar + 1`); на машинах без чёлки (mini) — fallback-полоска
  по центру верхней кромки экрана (`auxiliaryTopLeftArea == nil`).
- Модель полки — папка `~/Library/Application Support/Shelf/`. Панель
  отображает её содержимое; приём и отдача drag'а — целиком локальные
  (`registerForDraggedTypes([.fileURL])` / `beginDraggingSession`).
- Drop на MacBook: файл копируется в локальную папку полки **и** пушится
  на mini в такую же папку.
- Приложение на mini следит за папкой (`DispatchSource.makeFileSystemObjectSource`)
  и показывает новые файлы в своей полке; оттуда их вытаскивают локальным
  drag'ом внутри сессии Screen Sharing.
- Обратное направление (mini → MacBook) симметрично. Push-only с каждой
  стороны; двусторонний rsync с `--delete` не используем (гонки, риск
  внезапных удалений).

## Транспорт

Абстрагирован протоколом, чтобы менять реализацию без правок UI:

```swift
protocol ShelfTransport {
    func push(_ file: URL, to peer: Peer) async throws
}
```

- **MVP: rsync поверх SSH по Tailscale MagicDNS** (`rsync -a --partial
  file mac-mini.<tailnet>.ts.net:Shelf/`). Ноль серверного кода, докачка,
  шифрование и аутентификация уже даёт Tailscale. Требует Remote Login на
  mini либо Tailscale SSH.
- Рассмотрено: **Taildrop** (`tailscale file cp`) — меньше настройки, но
  приём через `tailscale file get`, доступность которого зависит от варианта
  клиента (App Store CLI урезан). Отклонено для MVP.
- Этап 2: **встроенный сервер** (`Network.framework`, listener только на
  tailscale-интерфейсе 100.x) — мгновенный push, прогресс, ретраи.

## Следствия и известные риски

- Sandbox выключен (запуск rsync/ssh, произвольные пути) → мимо Mac App Store.
  Для личного инструмента приемлемо.
- Спящий mini: push падает — нужна очередь с ретраями (источник истины —
  локальная папка полки).
- Передача во временное имя (`.part`) + атомарный rename, чтобы watcher на
  приёмнике не подхватил недокачанный файл.
- В UI полки нужен статус доставки (отправляется / доставлен / ошибка).
- `LSUIElement = YES`, окно `.canJoinAllSpaces, .fullScreenAuxiliary`;
  hit-зона на 20–40 pt шире чёлки, расширение по `draggingEntered`.

## Альтернативы, отклонённые целиком

- SMB-шара поверх Tailscale: флаки при сне, зависимость от смонтированности.
- Перетаскивание сквозь окно Screen Sharing: платформа не поддерживает.
