VERSION = 0.1

PREFIX = /usr/local
DATADIR = ${PREFIX}/share
PKGDATADIR = ${DATADIR}/ffphonelog

VALAFLAGS = --pkg elm --pkg posix --pkg gio-2.0
INCS = $(shell pkg-config --cflags elementary ecore evas gio-2.0)
LIBS = $(shell pkg-config --libs elementary ecore evas gio-2.0)

CPPFLAGS = -DPKGDATADIR=\"${PKGDATADIR}\"
CC=cc
CFLAGS = ${CPPFLAGS} ${INCS} ${CFLAGS_APPEND}
LDFLAGS = ${LIBS} ${LDFLAGS_APPEND}

OE_TOPDIR = $(shell which bitbake | sed s:/bitbake/bin/bitbake::)
NEO=192.168.0.202

# can be autodetected with: make autodetect-options
BASE_PACKAGE_ARCH=armv4t
DEPLOY_DIR_IPK=${OE_TOPDIR}/tmp/deploy/ipk
DISTRO_PR=.6

IPK_BASENAME=ffphonelog_${VERSION}-r0${DISTRO_PR}_${BASE_PACKAGE_ARCH}.ipk
IPK_DIR=${DEPLOY_DIR_IPK}/${BASE_PACKAGE_ARCH}
