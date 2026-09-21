include config.mk

all:
	@echo Nothing to build: use make install, make uninstall, make check, or make dist.

check:
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck -s sh bm test/run.sh test/fakemenu test/fakefzf; \
	else \
		echo shellcheck not found: skipping lint; \
	fi
	@sh test/run.sh

dist:
	@echo creating dist tarball
	@mkdir -p sbm-${VERSION}-temp
	@cp -R Makefile config.mk README TODO bm usertags test sbm-${VERSION}-temp
	@mv sbm-${VERSION}-temp sbm-${VERSION}
	@tar -cf sbm-${VERSION}.tar sbm-${VERSION}
	@gzip sbm-${VERSION}.tar
	@rm -rf sbm-${VERSION}

install:
	@echo installing scripts to ${DESTDIR}${PREFIX}/bin
	@mkdir -p ${DESTDIR}${PREFIX}/bin
	@cp bm ${DESTDIR}${PREFIX}/bin
	@chmod 755 ${DESTDIR}${PREFIX}/bin/bm

uninstall:
	@echo removing scripts
	rm -f ${DESTDIR}${PREFIX}/bin/bm

.PHONY: all check dist install uninstall
