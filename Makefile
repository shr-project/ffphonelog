VAPIDIR = ${HOME}/src/libeflvala/vapi
VALAFLAGS = --vapidir=${VAPIDIR} --vapidir . --pkg dbus-glib-1 --pkg posix --pkg elementary
CFLAGS=`pkg-config --cflags elementary dbus-glib-1`
LDFLAGS=`pkg-config --libs elementary dbus-glib-1`


ffphonelog: ffphonelog.vala
	valac ${VALAFLAGS} ffphonelog.vala
