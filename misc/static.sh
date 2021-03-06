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
-MConfig \
-MConfig_heavy.pl \
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
-MEnv \
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
-MFile::Path \
-MData::Dumper \
-MTemplate \
-MTemplate::Filters \
-MTemplate::Stash::XS \
-MDBI \
-MDBD::SQLite \
-MIO::FDPass \
-MProc::FastSpawn \
-MAnyEvent::Fork \
-MAnyEvent::Fork::RPC \
-MAnyEvent::Fork::Pool \
--strip ${STRIP} \
--${LINKTYPE} \
--usepacklists \
--add "../src/app/feersum.pl app/feersum.pl" \
--add "../src/backend/feersum.pl backend/feersum.pl" \
--add "../src/modules/Local/Server/Hooks.pm Local/Server/Hooks.pm" \
--add "../src/modules/Local/Server/Settings.pm Local/Server/Settings.pm" \
--add "../src/modules/Local/DB.pm Local/DB.pm" \
--add "../src/modules/Local/DB/SQLite.pm Local/DB/SQLite.pm" \
--add "../src/modules/Local/OpenSSL/Command.pm Local/OpenSSL/Command.pm" \
--add "../src/modules/Local/Data/JSON.pm Local/Data/JSON.pm" \
--add "../src/modules/Local/Run.pm Local/Run.pm" \
--add "../src/modules/Local/OpenSSL/Conf.pm Local/OpenSSL/Conf.pm" \
--add "../src/modules/Local/OpenSSL/Script/Revoke.pm Local/OpenSSL/Script/Revoke.pm" \
$@
