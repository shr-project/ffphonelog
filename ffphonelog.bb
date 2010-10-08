DESCRIPTION = "Finger friendly phonelog"
LICENSE = "GPLv3"
AUTHOR = "Łukasz Pankowski <lukpank@o2.pl>"
MAINTAINER = "Łukasz Pankowski <lukpank@o2.pl>"
SECTION = "x11/applications"
PRIORITY = "optional"
DEPENDS = "libeflvala"
RDEPENDS = "phoneuid"
PV = "0.0.1"
PR = "r0"

SRC_URI = "file://ffphonelog-${PV}.tar.gz"

PACKAGES = "${PN} ${PN}-dbg"
FILES_${PN} += "${datadir}/applications ${datadir}/pixmaps"

do_install() {
	oe_runmake install DESTDIR=${D}
}
