#!/bin/sh

TARGET=bin/plcrtd
OPTIONS="--verbose -W /tmp -D /tmp/plcrtd-deploy"
STRIP=strip
PERL=perl
FIND=find
SH=/bin/sh

# checks every .pl and .pm file for syntax errors
export PERL5LIB=../src/modules
${FIND} ../src -regextype posix-extended -regex '.*.(pl|pm)$' | \
	xargs -n1 -I'{}' ${PERL} -c {} \
|| exit 1
unset PERL5LIB

# build an executable
${SH} static.sh || exit 1
# if strip is missing, just ignore that fact
${STRIP} --strip-unneeded -R .comment -R .note -R .note.ABI-tag ${TARGET}
# run an executable
./${TARGET} ${OPTIONS}
exit 0
