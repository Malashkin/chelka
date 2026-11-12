---
audience: люди
updated: 2026-11-12
---

# Документация проекта

Для пользователей — [README.md](../README.md) (EN) / [README.ru.md](../README.ru.md) (RU):
что это, установка на один Mac и связка двух через Tailscale, использование,
траблшутинг.

Для ИИ-агентов (Claude Code, Codex и т.п.) — [AGENTS.md](../AGENTS.md) в корне:
команды, карта кода, инварианты безопасности, правила работы. `CLAUDE.md`
указывает туда же.

Внутренние документы:

- [CHANGELOG.md](CHANGELOG.md) — история изменений (Keep a Changelog).
- [architecture/decisions/](architecture/decisions/ADR-0001-notch-shelf-sync.md) —
  ADR: почему полка — это синхронизация папки, а не «drag сквозь Screen Sharing»;
  [ADR-0002](architecture/decisions/ADR-0002-rename-to-lintel.md) — переименование
  Chelka → Lintel и миграция существующих установок.
- [testing/](testing/index.md) — стратегия тестов и ручной чек-лист.
- [security/](security/index.md) — аудит: модель угроз, находки (все устранены), проверки.
