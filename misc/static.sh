#!/bin/sh

APPNAME="plcrtd"
STRIP="none" #ppi"
LINKTYPE="static" #allow-dynamic"
BIN_DIR="bin"
RC_FILE=${HOME}/.staticperlrc
SP_FILE=${HOME}/staticperl
BOOT_FILE="../src/main.pl"


if [ -f ${RC_FILE} ]; then
	. ${RC_FILE}
else
	echo "${RC_FILE}: not found"
	exit 1
fi

if [ ! -d "${BIN_DIR}" ]; then
	mkdir ${BIN_DIR} || exit 1
fi

${SP_FILE} mkapp ${BIN_DIR}/$APPNAME --boot ${BOOT_FILE} \
-Msort.pm \
-Mfeature.pm \
-Mvars \
-Mutf8 \
-Mutf8_heavy.pl \
-MErrno \
-MFcntl \
-MPOSIX \
-MSocket \
-MCarp \
-MEncode \
-Mcommon::sense \
-MEV \
-MGuard \
-MAnyEvent \
-MAnyEvent::Handle \
-MAnyEvent::Socket \
-MAnyEvent::Impl::EV \
-MAnyEvent::Util \
-MAnyEvent::Log \
-MGetopt::Long \
-MFile::Spec::Functions \
-MJSON::XS \
-MSys::Syslog \
-MFeersum \
-MHTTP::Body \
-MHTML::Entities \
--strip ${STRIP} \
--${LINKTYPE} \
--usepacklists \
--add "../src/app/feersum.pl app/feersum.pl" \
--add "../src/backend/feersum.pl backend/feersum.pl" \
$@
