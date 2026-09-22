include config.mk

BIN = bm bm-migrate bm-html bm-check
SCRIPTS = bm-import bm-title bm-commit bm-watch bm-sync
SRC = bm.c bm-migrate.c bm-html.c bm-check.c util.c
OBJ = ${SRC:.c=.o}
TESTS = test/run.sh test/fakemenu test/fakefzf

all: ${BIN}

config.h:
	cp config.def.h $@

${OBJ}: config.h util.h config.mk

.c.o:
	${CC} -c ${CFLAGS} $<

bm: bm.o util.o
	${CC} -o $@ bm.o util.o ${LDFLAGS}

bm-migrate: bm-migrate.o util.o
	${CC} -o $@ bm-migrate.o util.o ${LDFLAGS}

bm-html: bm-html.o util.o
	${CC} -o $@ bm-html.o util.o ${LDFLAGS}

bm-check: bm-check.o util.o
	${CC} -o $@ bm-check.o util.o ${LDFLAGS}

check: all
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck -s sh ${SCRIPTS} ${TESTS}; \
	else \
		echo shellcheck not found: skipping lint; \
	fi
	@sh test/run.sh

clean:
	rm -f ${BIN} ${OBJ} sbm-${VERSION}.tar.gz

dist: clean
	@echo creating dist tarball
	@mkdir -p sbm-${VERSION}-temp
	@cp -R Makefile config.mk config.def.h util.h ${SRC} README TODO LICENSE ${SCRIPTS} \
		usertags engines test contrib sbm-${VERSION}-temp
	@mv sbm-${VERSION}-temp sbm-${VERSION}
	@tar -cf sbm-${VERSION}.tar sbm-${VERSION}
	@gzip sbm-${VERSION}.tar
	@rm -rf sbm-${VERSION}

install: all
	@echo installing ${TOOLS} to ${DESTDIR}${PREFIX}/bin
	@mkdir -p ${DESTDIR}${PREFIX}/bin
	@for tool in ${TOOLS}; do \
		cp $$tool ${DESTDIR}${PREFIX}/bin/ && \
		chmod 755 ${DESTDIR}${PREFIX}/bin/$$tool || exit 1; \
	done

uninstall:
	@echo removing ${BIN} ${SCRIPTS} from ${DESTDIR}${PREFIX}/bin
	@for tool in ${BIN} ${SCRIPTS}; do rm -f ${DESTDIR}${PREFIX}/bin/$$tool; done

.PHONY: all check clean dist install uninstall
