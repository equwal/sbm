include config.mk

all:
	@echo Nothing to build: use make install, make uninstall, or make dist.

dist:
	@echo creating dist tarball
	@mkdir -p sbm-${VERSION}-temp
	@cp -R Makefile config.mk bm  sbm-${VERSION}-temp
	@mv sbm-${VERSION}-temp sbm-${VERSION}
	@tar -cf sbm-${VERSION}.tar sbm-${VERSION}
	@gzip sbm-${VERSION}.tar
	@rm -rf sbm-${VERSION}

install:
	@echo installing scripts to ${DESTDIR}${PREFIX}/bin
	@mkdir -p ${DESTDIR}${PREFIX}
	@cp bm ${DESTDIR}${PREFIX}/bin
	@chmod 755 ${DESTDIR}${PREFIX}/bin/bm

uninstall:
	@echo removing scripts
	rm -f ${DESTDIR}${PREFIX}/bin/bm
