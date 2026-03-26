.PHONY: install uninstall test

BIN ?= ezsops
PREFIX ?= /usr/local

install:
	cp ezsops.sh $(PREFIX)/bin/$(BIN)

uninstall:
	rm -f $(PREFIX)/bin/$(BIN)

test:
	bats test/ezsops.bats
