PREFIX      ?= /usr/local
BINDIR      ?= $(PREFIX)/bin
BASHCOMPDIR ?= /usr/share/bash-completion/completions
ZSHCOMPDIR  ?= $(PREFIX)/share/zsh/site-functions

.PHONY: install uninstall 

install:
	install -Dm755 goken.sh              $(DESTDIR)$(BINDIR)/goken
	install -Dm644 completions/goken.bash $(DESTDIR)$(BASHCOMPDIR)/goken
	install -Dm644 completions/_goken     $(DESTDIR)$(ZSHCOMPDIR)/_goken

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/goken \
	      $(DESTDIR)$(BASHCOMPDIR)/goken \
	      $(DESTDIR)$(ZSHCOMPDIR)/_goken


