include config.mk

all:


dist:
	@echo creating dist tarball
	@mkdir -p sbm-${VERSION}-temp
	@cp -R Makefile config.mk bm  sbm-${VERSION}-temp
	@tar -cf sbm-${VERSION}.tar sbm-${VERSION}-temp
	@gzip sbm-${VERSION}.tar
	@rm -rf sbm-${VERSION}-temp

install:
	@echo installing scripts to ${DESTDIR}${PREFIX}/bin
	@mkdir -p ${DESTDIR}${PREFIX}
	@cp bm ${DESTDIR}${PREFIX}/bin
	@chmod 755 ${DESTDIR}${PREFIX}/bin/bm

uninstall:
	@echo removing scripts
	rm -f ${DESTDIR}${PREFIX}/bin/bm


