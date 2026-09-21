include config.mk

SCRIPTS = bm bm-migrate bm-import bm-check bm-html bm-title bm-commit bm-watch
TESTS = test/run.sh test/fakemenu test/fakefzf

all:
	@echo Nothing to build: use make install, make uninstall, make check, or make dist.

check:
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck -s sh ${SCRIPTS} ${TESTS}; \
	else \
		echo shellcheck not found: skipping lint; \
	fi
	@sh test/run.sh

dist:
	@echo creating dist tarball
	@mkdir -p sbm-${VERSION}-temp
	@cp -R Makefile config.mk README TODO ${SCRIPTS} usertags engines test contrib sbm-${VERSION}-temp
	@mv sbm-${VERSION}-temp sbm-${VERSION}
	@tar -cf sbm-${VERSION}.tar sbm-${VERSION}
	@gzip sbm-${VERSION}.tar
	@rm -rf sbm-${VERSION}

install:
	@echo installing ${TOOLS} to ${DESTDIR}${PREFIX}/bin
	@mkdir -p ${DESTDIR}${PREFIX}/bin
	@for tool in ${TOOLS}; do \
		cp $$tool ${DESTDIR}${PREFIX}/bin/ && \
		chmod 755 ${DESTDIR}${PREFIX}/bin/$$tool || exit 1; \
	done

uninstall:
	@echo removing scripts
	@for tool in ${SCRIPTS}; do rm -f ${DESTDIR}${PREFIX}/bin/$$tool; done

.PHONY: all check dist install uninstall
