BIN ?= ezsops
PREFIX ?= /usr/local

install:
	cp ezsops.sh $(PREFIX)/bin/$(BIN)

uninstall:
	rm -f $(PREFIX)/bin/$(BIN)