VERSION = 0.0.1

PREFIX = /usr
PKG_CFLAGS = `pkg-config --cflags elementary dbus-glib-1`
PKG_LIBS = `pkg-config --libs elementary dbus-glib-1`
VALAFLAGS = --pkg elm --pkg dbus-glib-1 --pkg posix
CC=cc

OE_TOPDIR = `which bitbake | sed s:/bitbake/bin/bitbake::`
NEO=192.168.0.202

# can be autodetected with: make autodetect-options
BASE_PACKAGE_ARCH=armv4t
DEPLOY_DIR_IPK=${OE_TOPDIR}/tmp/deploy/ipk

IPK_BASENAME=ffphonelog_${VERSION}-r0.5_${BASE_PACKAGE_ARCH}.ipk
IPK_DIR=${DEPLOY_DIR_IPK}/${BASE_PACKAGE_ARCH}
