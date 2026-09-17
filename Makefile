.PHONY: build test app run

build:
	swift build

test:
	swift run chelka-selftest

app:
	./scripts/make-app.sh

run: app
	open build/Chelka.app

install: app
	pkill -x Chelka || true
	rm -rf /Applications/Chelka.app
	cp -R build/Chelka.app /Applications/Chelka.app
	open /Applications/Chelka.app

# Обновить обе машины: локально + push сборки на вторую по ssh.
# Хост пира: make deploy PEER=<host>, либо задать один раз:
#   defaults write dev.mike.Chelka deployPeer <host>
PEER ?= $(shell defaults read dev.mike.Chelka deployPeer 2>/dev/null)

deploy: install
	@test -n "$(PEER)" || { echo "Не задан пир: make deploy PEER=<host> или defaults write dev.mike.Chelka deployPeer <host>"; exit 1; }
	rsync -a --delete -e "ssh -o BatchMode=yes" build/Chelka.app $(PEER):/Applications/
	ssh -o BatchMode=yes $(PEER) 'pkill -x Chelka; sleep 1; open /Applications/Chelka.app'
