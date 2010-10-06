include config.mk

SRC=ffphonelog.vala
OBJ=ffphonelog.o

all: ffphonelog

ffphonelog: ${OBJ}
	${CC} -o $@ ${LDFLAGS} ${PKG_LIBS} ${OBJ}

.c.o:
	${CC} -c ${CFLAGS} ${PKG_CFLAGS} $<

ffphonelog.c: ${SRC}
	valac -C ${VALAFLAGS} ${SRC}
	touch ffphonelog.c

clean:
	rm -f ffphonelog ${OBJ} ffphonelog.c

dist:
	mkdir -p ffphonelog-${VERSION}/data
	cp Makefile config.mk ffphonelog.vala ffphonelog.bb \
		 ffphonelog-${VERSION}
	cp data/ffphonelog.desktop data/ffphonelog.png \
		data/general.png data/made.png data/missed.png \
		data/received.png data/made-mini.png \
		data/missed-mini.png data/received-mini.png \
		ffphonelog-${VERSION}/data
	tar zcf ffphonelog-${VERSION}.tar.gz ffphonelog-${VERSION}
	rm -r ffphonelog-${VERSION}

install:
	install -d ${DESTDIR}${PREFIX}/bin
	install -m 755  ffphonelog ${DESTDIR}${PREFIX}/bin
	install -d ${DESTDIR}${PREFIX}/share/applications
	install -m 644 data/ffphonelog.desktop \
		${DESTDIR}${PREFIX}/share/applications
	install -d ${DESTDIR}${PREFIX}/share/pixmaps
	install -m 644 data/ffphonelog.png ${DESTDIR}${PREFIX}/share/pixmaps
	install -d ${DESTDIR}${PREFIX}/share/ffphonelog/icons
	install -m 644 data/general.png data/made.png data/missed.png \
		data/received.png data/made-mini.png \
		data/missed-mini.png data/received-mini.png \
		${DESTDIR}${PREFIX}/share/ffphonelog/icons

do_%:
	bitbake -c $* -b ffphonelog.bb

ipk: clean do_clean do_package_write

ipk-install:
	scp -q ${IPK_DIR}/${IPK_BASENAME} "${NEO}:"
	ssh ${NEO} opkg install ${IPK_BASENAME}

ipk-info:
	dpkg --info ${IPK_DIR}/${IPK_BASENAME}
	dpkg --contents ${IPK_DIR}/${IPK_BASENAME}
	ls -lh ${IPK_DIR}/${IPK_BASENAME}

autodetect-options:
	echo -e "\n# update config.mk with" && \
	bitbake -e | grep -E "^DEPLOY_DIR_IPK=|^BASE_PACKAGE_ARCH="

.PHONY: all clean dist install ipk ipk-install ipk-info autodetect-options
