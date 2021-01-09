include config.mk

all:


dist:
	@echo creating dist tarball
	@mkdir -p sbm-${VERSION}
	@cp -R LICENSE Makefile config.mk bin sbm-${VERSION}
	@tar -cf sbm-${VERSION}.tar sbm-${VERSION}
	@gzip sbm-${VERSION}.tar
	@rm -rf sbm-${VERSION}

install:
	@echo installing scripts to ${DESTDIR}${PREFIX}
	@mkdir -p ${DESTDIR}${PREFIX}
	@cd bin
	for i in bin/*; \
	do \
		cp $$i ${DESTDIR}${PREFIX}/bin; \
		chmod 755 ${DESTDIR}${PREFIX}/$$i;	\
	done; true

uninstall:
	@echo removing scripts
	@cd bin
	for i in ./*; \
	do \
		rm -f ${DESTDIR}${PREFIX}/bin/$$i;	\
	done; true


