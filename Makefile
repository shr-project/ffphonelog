include config.mk

SRC=ffphonelog.vala
OBJ=ffphonelog.o

all: ffphonelog data/ffphonelog.edj

ffphonelog: ${OBJ}
	${CC} -o $@ ${LDFLAGS} ${OBJ}

.c.o:
	${CC} -c ${CFLAGS} $<

ffphonelog.c: ${SRC}
	valac -C ${VALAFLAGS} ${SRC}
	touch ffphonelog.c

data/ffphonelog.edj: data/ffphonelog.edc
	edje_cc -id data $< $@

clean:
	rm -f ffphonelog ${OBJ} ffphonelog.c data/ffphonelog.edj

dist:
	mkdir -p ffphonelog-${VERSION}/data
	cp Makefile config.mk ffphonelog.vala ffphonelog.bb \
		 ffphonelog-${VERSION}
	cp data/ffphonelog.desktop data/ffphonelog.png data/ffphonelog.edc \
		data/general.png data/made.png data/missed.png \
		data/received.png ffphonelog-${VERSION}/data
	tar zcf ffphonelog-${VERSION}.tar.gz ffphonelog-${VERSION}
	rm -r ffphonelog-${VERSION}

install:
	install -d ${DESTDIR}${PREFIX}/bin
	install -m 755  ffphonelog ${DESTDIR}${PREFIX}/bin
	install -d ${DESTDIR}${DATADIR}/applications
	install -m 644 data/ffphonelog.desktop \
		${DESTDIR}${DATADIR}/applications
	install -d ${DESTDIR}${DATADIR}/pixmaps
	install -m 644 data/ffphonelog.png ${DESTDIR}${DATADIR}/pixmaps
	install -d ${DESTDIR}${DATADIR}/ffphonelog
	install -m 644 data/ffphonelog.edj ${DESTDIR}${DATADIR}/ffphonelog

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
	@echo "# update config.mk with" && \
	bitbake -e | grep -E "^DEPLOY_DIR_IPK=|^BASE_PACKAGE_ARCH=|^DISTRO_PR="

.PHONY: all clean dist install ipk ipk-install ipk-info autodetect-options
