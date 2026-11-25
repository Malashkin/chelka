.PHONY: build test app run

build:
	swift build

test:
	swift run lintel-selftest

app:
	./scripts/make-app.sh

run: app
	open build/Lintel.app

install: app
	pkill -x Lintel || true
	@# старое имя продукта: убрать прежнюю сборку, чтобы не висели две полки
	pkill -x Chelka || true
	rm -rf /Applications/Chelka.app
	rm -rf /Applications/Lintel.app
	cp -R build/Lintel.app /Applications/Lintel.app
	open /Applications/Lintel.app

# Обновить обе машины: локально + push сборки на вторую по ssh.
# Хост пира: make deploy PEER=<host>, либо задать один раз:
#   defaults write dev.mike.Lintel deployPeer <host>
# (до переименования ключ жил в dev.mike.Chelka — читаем и его)
PEER ?= $(shell defaults read dev.mike.Lintel deployPeer 2>/dev/null || defaults read dev.mike.Chelka deployPeer 2>/dev/null)

deploy: install
	@test -n "$(PEER)" || { echo "Не задан пир: make deploy PEER=<host> или defaults write dev.mike.Lintel deployPeer <host>"; exit 1; }
	rsync -a --delete -e "ssh -o BatchMode=yes" build/Lintel.app $(PEER):/Applications/
	ssh -o BatchMode=yes $(PEER) 'pkill -x Lintel; pkill -x Chelka; rm -rf /Applications/Chelka.app; sleep 1; open /Applications/Lintel.app'
