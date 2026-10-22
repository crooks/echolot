#!/bin/sh
# selftest.sh: run this Echolot tree against a local yamn remailer, without
# an MTA, and check the whole cycle: key and conf requests, pubring.mix, a
# ping through yamn, mlist2.txt, and the yamn HTML pages.
#
# Usage (as a normal user; pingd refuses to run as root):
#     YAMN=/path/to/yamn contrib/yamn/test/selftest.sh
# Needs perl with GnuPG::Interface and HTML::Template, and gpg.
# Set KEEP=1 to keep the work directory for inspection.
set -eu

yamn=${YAMN:?set YAMN to the yamn binary}
case $yamn in /*) ;; *) yamn=$(command -v "$yamn") ;; esac
if [ "$(id -u)" = 0 ]; then
	echo "selftest.sh: run as a normal user, pingd refuses to run as root" >&2
	exit 1
fi
here=$(cd "$(dirname "$0")" && pwd)
src=$(cd "$here/../../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/echolot-selftest.XXXXXX")

cleanup() {
	if [ -e "$work/pingd.pid" ]; then
		kill "$(cut -d' ' -f1 "$work/pingd.pid")" 2>/dev/null || true
		sleep 2
	fi
	# Echolot's gpg calls start a gpg-agent for the test's GnuPG home.
	gpgconf --homedir "$work/echolot/gnupghome" --kill gpg-agent 2>/dev/null || true
	if [ "${KEEP:-}" = 1 ]; then
		echo "work directory kept: $work"
	else
		rm -rf "$work"
	fi
}
trap cleanup EXIT

fail() {
	echo "FAIL: $*" >&2
	echo "--- pingd.log" >&2
	tail -20 "$work/echolot/pingd.log" >&2 || true
	echo "--- mail.log" >&2
	cat "$work/mail.log" >&2 || true
	exit 1
}

# wait_for DESCRIPTION SECONDS COMMAND...: retry COMMAND until it succeeds.
wait_for() {
	what=$1 secs=$2
	shift 2
	i=0
	until "$@" >/dev/null 2>&1; do
		i=$((i + 1))
		[ $i -le "$secs" ] || fail "timed out waiting for $what"
		sleep 1
	done
	echo "ok: $what"
}

remailer() {
	(cd "$work/rem" && "$yamn" -M -S --nodummy --dir "$work/rem" \
		--config "$work/rem/yamn.yml" >>"$work/rem/yamn.log" 2>&1)
}

# Layout: the Echolot tree, a remailer and Echolot's mixhome.
mkdir -p "$work/echolot"
(cd "$src" && tar cf - --exclude=.git --exclude=./data --exclude=./results \
	--exclude=./pingd.conf --exclude=./pingd.log .) | (cd "$work/echolot" && tar xf -)
for d in rem/Maildir echolot/mail; do
	mkdir -p "$work/$d/new" "$work/$d/cur" "$work/$d/tmp"
done
mkdir -p "$work/mixhome"

export YAMN="$yamn"
# pingd finds pingd.conf and keeps its state in ECHOLOT_HOME if that is set
# (as in the Docker image), so point it at the test copy.
export ECHOLOT_HOME="$work/echolot"
unset ECHOLOT_CONF
export FAKESENDMAIL_LOG="$work/mail.log"
export FAKESENDMAIL_ROUTES="remailer.test=$work/rem/Maildir pinger.test=$work/echolot/mail"
sendmail="$here/fakesendmail"

cat >"$work/rem/yamn.yml" <<EOT
remailer:
    name: testrem
    address: rem@remailer.test
    exit: true
mail:
    pipe: "$sendmail -t"
urls:
    fetch: false
EOT
cat >"$work/mixhome/yamn.yml" <<EOT
urls:
    fetch: false
mail:
    pipe: "$sendmail -t"
remailer:
    address: pinger@pinger.test
stats:
    num_copies: 1
    use_expired: true
EOT
cat >"$work/echolot/pingd.conf" <<EOT
\$CONFIG = {
	'sitename'            => 'selftest',
	'my_localpart'        => 'pinger',
	'my_domain'           => 'pinger.test',
	'operator_address'    => 'admin@pinger.test',
	'recipient_delimiter' => '+',
	'sendmail'            => '$sendmail',
	'mixmaster'           => '$work/echolot/contrib/yamn/yamn-ping',
	'mixhome'             => '$work/mixhome',
	'do_pings'            => { 'mix' => 1 },
	'which_chainpings'    => { 'mix' => [ qw{mix} ] },
	'processmail'         => 5,
	'templates' => { 'default' => {
		'indexfile'          => 'contrib/yamn/templates/echolot.html',
		'mlist'              => 'contrib/yamn/templates/mlist.html',
		'mlist2'             => 'contrib/yamn/templates/mlist2.html',
		'thesaurusindexfile' => 'templates/thesaurusindex.html',
		'fromlinesindexfile' => 'templates/fromlinesindex.html',
		'rlist'              => 'templates/rlist.html',
		'rlist-rsa'          => 'templates/rlist-rsa.html',
		'rlist-dsa'          => 'templates/rlist-dsa.html',
		'rlist-clear'        => 'templates/rlist-clear.html',
		'rlist2'             => 'templates/rlist2.html',
		'rlist2-rsa'         => 'templates/rlist2-rsa.html',
		'rlist2-dsa'         => 'templates/rlist2-dsa.html',
		'rlist2-clear'       => 'templates/rlist2-clear.html',
		'clist'              => 'templates/clist.html',
	} },
	'pidfile'             => '$work/pingd.pid',
	'loglevel'            => 'debug',
};
1;
EOT

# The remailer creates its key on its first run.
remailer
grep -q 'Begin Mix Key' "$work/rem/key.txt" || fail "the remailer didn't create a key"
keyid=$(head -1 "$work/rem/key.txt" | awk '{print $3}')
[ -n "$keyid" ] || fail "can't read the remailer's keyid"
echo "ok: remailer key $keyid"

cd "$work/echolot"
./pingd --detach start >/dev/null
wait_for "pingd started" 10 test -e "$work/pingd.pid"
./pingd add rem@remailer.test
./pingd getkeyconf rem@remailer.test
wait_for "remailer-key request sent" 30 grep -q "remailer-key" "$work/mail.log"

remailer
wait_for "key reply parsed" 60 grep -q "Setting mix key for rem@remailer.test: $keyid" pingd.log
wait_for "conf reply parsed" 60 grep -q "Setting capabilities for rem@remailer.test" pingd.log

./pingd buildkeys
wait_for "pubring.mix built" 60 grep -q "^testrem rem@remailer.test $keyid " results/pubring.mix

./pingd sendpings rem@remailer.test
wait_for "ping sent through yamn" 60 grep -q "registering pingout for rem@remailer.test" pingd.log
grep -q "Mixmaster said on stderr" pingd.log && fail "yamn reported a problem sending the ping"

remailer
wait_for "ping returned" 60 grep -q "registering pingdone .* for rem@remailer.test" pingd.log

./pingd buildstats
wait_for "mlist2.txt built" 60 grep -q "^testrem " results/mlist2.txt
wait_for "echolot.html built from the yamn template" 60 \
	grep -q -e "-->Type II (Mixmaster) remailers" results/echolot.html
grep -q "testrem" results/mlist2.html || fail "mlist2.html lists no remailer"
echo "PASS"
