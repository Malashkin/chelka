#!/bin/sh
# Chelka: forced command для транспортного ssh-ключа.
# Ставится на ПРИНИМАЮЩЕЙ машине как ~/.chelka-receive, а в authorized_keys
# строка ключа получает префикс:
#   restrict,command="/Users/<user>/.chelka-receive" ssh-ed25519 AAAA... chelka-transport
# После этого ключ может ТОЛЬКО принимать файлы rsync'ом в ~/Shelf:
# shell, любые команды и чтение файлов (--sender) отклоняются.
set -u
cmd="${SSH_ORIGINAL_COMMAND:-}"

reject() { logger -t chelka-receive "reject: $cmd" 2>/dev/null || true; exit 1; }

# shell-метасимволов нет ни в одной законной команде транспорта
case "$cmd" in
  *[\;\&\|\`\$\(\)\<\>\"\']*) reject ;;
  *"
"*) reject ;;
esac

case "$cmd" in
  "mkdir -p Shelf")
    mkdir -p "$HOME/Shelf"
    exit 0 ;;
  "chelka-clear")
    # очистка полки по явной команде с пира: только в Корзину (восстановимо)
    if [ "${CHELKA_RECEIVE_TEST:-}" = "1" ]; then
        echo "WOULD-CLEAR"
        exit 0
    fi
    mkdir -p "$HOME/.Trash"
    for f in "$HOME/Shelf"/*; do
        [ -e "$f" ] || continue
        base=$(basename "$f")
        dest="$HOME/.Trash/$base"
        [ -e "$dest" ] && dest="$HOME/.Trash/$base-$(date +%s)-$$"
        mv "$f" "$dest"
    done
    exit 0 ;;
  "rsync --server "*" . Shelf/" | "/usr/bin/rsync --server "*" . Shelf/")
    case "$cmd" in *--sender*) reject ;; esac    # чтение с этой машины запрещено
    mkdir -p "$HOME/Shelf"
    if [ "${CHELKA_RECEIVE_TEST:-}" = "1" ]; then
        echo "WOULD-RUN: $cmd"
        exit 0
    fi
    set -f
    # shellcheck disable=SC2086
    set -- $cmd
    shift                                        # слово rsync / /usr/bin/rsync
    exec /usr/bin/rsync "$@" ;;
  *) reject ;;
esac
