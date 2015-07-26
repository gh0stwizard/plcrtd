#!/bin/sh

APPNAME="plcrtd"
STRIP="none" #ppi"
LINKTYPE="static" #allow-dynamic"
BIN_DIR="bin"
RC_FILE=${HOME}/.staticperlrc
SP_FILE=${HOME}/staticperl
BOOT_FILE="../src/main.pl"


if [ -r ${RC_FILE} ]; then
	. ${RC_FILE}
else
	echo "${RC_FILE}: not found"
	exit 1
fi

[ -d ${BIN_DIR} ] || mkdir ${BIN_DIR} || exit 1

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
-MUnQLite \
-MFile::Path \
-MData::Dumper \
-MTemplate \
-MTemplate::Filters \
-MTemplate::Stash::XS \
--strip ${STRIP} \
--${LINKTYPE} \
--usepacklists \
--add "../src/app/feersum.pl app/feersum.pl" \
--add "../src/backend/feersum.pl backend/feersum.pl" \
--add "../src/modules/Local/DB/UnQLite.pm Local/DB/UnQLite.pm" \
--add "../src/modules/Local/OpenSSL/Conf.pm Local/OpenSSL/Conf.pm" \
--add "../src/modules/Local/OpenSSL/Script/Revoke.pm Local/OpenSSL/Script/Revoke.pm" \
$@
