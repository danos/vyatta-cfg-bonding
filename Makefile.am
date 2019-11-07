SUBDIRS = . tests

opdir = $(datadir)/vyatta-op/templates
share_perl5dir = $(datarootdir)/perl5/Vyatta
tmplscriptdir = $(datadir)/tmplscripts
yangdir = /usr/share/configd/yang

bin_SCRIPTS = scripts/vyatta-show-bonding
sbin_SCRIPTS = scripts/vyatta-bonding
sysconf_DATA =
share_perl5_DATA = lib/Vyatta/Bonding.pm

AM_CFLAGS = -I /usr/include/vyatta-cfg

cpiop = find  . ! -regex '\(.*~\|.*\.bak\|.*\.swp\|.*\#.*\#\)' -print0 | \
  cpio -0pd

install-exec-hook:
	mkdir -p $(DESTDIR)$(opdir)
	cd templates && $(cpiop) $(DESTDIR)$(opdir) || true
	mkdir -p $(DESTDIR)$(tmplscritdir)
	cd tmplscripts && $(cpiop) $(DESTDIR)$(tmplscriptdir) || true
	mkdir -p $(DESTDIR)$(yangdir)
	cd yang && $(cpiop) $(DESTDIR)$(yangdir) || true
