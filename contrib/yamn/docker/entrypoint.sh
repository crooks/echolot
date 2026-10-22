#!/bin/bash
# Entrypoint of the Echolot yamn pinger images (see README.md here).
#
#   run        (default) set up on first start, then run pingd, plus
#              Postfix in the standalone image
#   selftest   run contrib/yamn/test/selftest.sh and exit
#   <command>  run any other command, e.g. "bash"
set -euo pipefail

home=${ECHOLOT_HOME:-/var/lib/echolot}
mode=${PINGER_MAIL:-hostmail}

log() { echo "echolot-entrypoint: $*" >&2; }
die() { log "$*"; exit 1; }

case "${1:-run}" in
run) ;;
selftest)
	exec runuser -u pinger -- env HOME=/tmp TMPDIR=/tmp YAMN="$YAMN" \
		sh /opt/echolot/contrib/yamn/test/selftest.sh
	;;
*) exec "$@" ;;
esac

# --- Settings ----------------------------------------------------------
domain=${PINGER_DOMAIN:?set PINGER_DOMAIN to the mail domain of the pinger}
localpart=${PINGER_LOCALPART:-pinger}
address="$localpart@$domain"
operator=${PINGER_OPERATOR:-postmaster@$domain}
sitename=${PINGER_SITENAME:-$domain}

# --- The pinger user and its directories --------------------------------
if [ -n "${PINGER_UID:-}" ] && [ "$PINGER_UID" != "$(id -u pinger)" ]; then
	usermod -u "$PINGER_UID" pinger
fi
if [ -n "${PINGER_GID:-}" ] && [ "$PINGER_GID" != "$(id -g pinger)" ]; then
	groupmod -g "$PINGER_GID" pinger
fi
mkdir -p "$home/mail/new" "$home/mail/cur" "$home/mail/tmp" "$home/mixhome" /run/echolot
chown pinger:pinger "$home" "$home/mail" "$home/mail/new" "$home/mail/cur" \
	"$home/mail/tmp" "$home/mixhome" /run/echolot
# Echolot finds its HTML templates relative to its home directory.
ln -sfn /opt/echolot/templates "$home/templates"
chown -h pinger:pinger "$home/templates"

# --- Configuration files, created on the first start -------------------
# Delete them (or edit them) to change the settings; they are not
# overwritten while they exist.
if [ ! -e "$home/pingd.conf" ]; then
	log "creating $home/pingd.conf for $address"
	cat >"$home/pingd.conf" <<EOF
# Created by the container on its first start; see
# /opt/echolot/contrib/yamn/pingd.conf for the reasons behind the settings.
\$CONFIG = {
	'sitename'            => '$sitename',
	'my_localpart'        => '$localpart',
	'my_domain'           => '$domain',
	'operator_address'    => '$operator',
	'recipient_delimiter' => '+',
	'mixmaster'           => '/opt/echolot/contrib/yamn/yamn-ping',
	'mixhome'             => '$home/mixhome',
	'do_pings'            => { 'mix' => 1 },
	'which_chainpings'    => { 'mix' => [ qw{mix} ] },
	'getkeyconf_every_nth_time' => 72,
	'buildkeys'           => 60*60,
	'addresses_default_ttl' => 20,
	'templates' => { 'default' => {
		'indexfile'          => '/opt/echolot/contrib/yamn/templates/echolot.html',
		'mlist'              => '/opt/echolot/contrib/yamn/templates/mlist.html',
		'mlist2'             => '/opt/echolot/contrib/yamn/templates/mlist2.html',
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
	'pidfile'             => '/run/echolot/pingd.pid',
	'logfile'             => 'pingd.log',
	'loglevel'            => '${PINGER_LOGLEVEL:-info}',
};
1;
EOF
	chown pinger:pinger "$home/pingd.conf"
fi
if [ ! -e "$home/mixhome/yamn.yml" ]; then
	log "creating $home/mixhome/yamn.yml"
	cat >"$home/mixhome/yamn.yml" <<EOF
# Created by the container on its first start; see
# /opt/echolot/contrib/yamn/yamn.yml.
urls:
    fetch: false
mail:
    pipe: "/usr/sbin/sendmail -f $address -t"
remailer:
    address: $address
stats:
    num_copies: 1
    use_expired: true
EOF
	chown pinger:pinger "$home/mixhome/yamn.yml"
fi
# A stale pid file can't survive a container restart: /run is fresh.
rm -f /run/echolot/pingd.pid

# --- Mail ------------------------------------------------------------------
setup_msmtp() {
	# Outgoing mail of Echolot and yamn goes through /usr/sbin/sendmail,
	# i.e. msmtp, to the host's MTA or a relay.  Incoming mail must be
	# delivered by the host into $home/mail (a Maildir).
	local host=${SMTP_HOST:?set SMTP_HOST, the mail server to send through}
	{
		echo "defaults"
		echo "syslog off"
		echo "account default"
		echo "host $host"
		echo "port ${SMTP_PORT:-25}"
		echo "domain $domain"
		case "${SMTP_TLS:-starttls}" in
		off) echo "tls off" ;;
		on) echo "tls on"; echo "tls_starttls off" ;;
		*) echo "tls on"; echo "tls_starttls on" ;;
		esac
		echo "tls_trust_file /etc/ssl/certs/ca-certificates.crt"
		[ "${SMTP_TLS_VERIFY:-on}" = off ] && echo "tls_certcheck off"
		if [ -n "${SMTP_USER:-}" ]; then
			echo "auth on"
			echo "user $SMTP_USER"
			echo "password ${SMTP_PASSWORD:?set SMTP_PASSWORD with SMTP_USER}"
		fi
	} >/etc/msmtprc
	chmod 644 /etc/msmtprc
	if [ -n "${SMTP_USER:-}" ]; then
		chown root:pinger /etc/msmtprc
		chmod 640 /etc/msmtprc
	fi
	log "outgoing mail via $host:${SMTP_PORT:-25} (tls ${SMTP_TLS:-starttls})"
}

setup_postfix() {
	local hostname=${PINGER_HOSTNAME:-$domain}
	local cert=${TLS_CERT:-$home/tls/cert.pem}
	local key=${TLS_KEY:-$home/tls/key.pem}
	if [ ! -e "$cert" ] && [ -z "${TLS_CERT:-}" ]; then
		log "no TLS certificate given; creating a self-signed one in $home/tls"
		mkdir -p "$home/tls"
		openssl req -x509 -newkey rsa:3072 -nodes -days 3650 \
			-subj "/CN=$hostname" -keyout "$key" -out "$cert" 2>/dev/null
		chmod 600 "$key"
	fi
	[ -r "$cert" ] && [ -r "$key" ] || die "TLS certificate $cert or key $key not readable"
	echo "$hostname" >/etc/mailname
	postconf -e \
		"compatibility_level = 3.6" \
		"myhostname = $hostname" \
		"mydomain = $domain" \
		"myorigin = $domain" \
		"mydestination = $domain, localhost" \
		"mynetworks = 127.0.0.0/8 [::1]/128" \
		"inet_interfaces = all" \
		"inet_protocols = ${INET_PROTOCOLS:-all}" \
		"recipient_delimiter = +" \
		"home_mailbox = mail/" \
		"alias_maps = hash:/etc/aliases" \
		"alias_database = hash:/etc/aliases" \
		"smtpd_relay_restrictions = permit_mynetworks, reject_unauth_destination" \
		"smtpd_recipient_restrictions = permit_mynetworks, reject_unauth_destination" \
		"smtpd_tls_cert_file = $cert" \
		"smtpd_tls_key_file = $key" \
		"smtpd_tls_security_level = may" \
		"smtp_tls_security_level = may" \
		"smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt" \
		"message_size_limit = 1048576" \
		"maillog_file = /dev/stdout"
	if [ -n "${RELAYHOST:-}" ]; then
		postconf -e "relayhost = $RELAYHOST"
		if [ -n "${RELAY_USER:-}" ]; then
			echo "$RELAYHOST ${RELAY_USER}:${RELAY_PASSWORD:?set RELAY_PASSWORD with RELAY_USER}" \
				>/etc/postfix/sasl_passwd
			chmod 600 /etc/postfix/sasl_passwd
			postmap /etc/postfix/sasl_passwd
			postconf -e "smtp_sasl_auth_enable = yes" \
				"smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd" \
				"smtp_sasl_security_options = noanonymous" \
				"smtp_tls_security_level = encrypt"
		fi
		log "outgoing mail via relay $RELAYHOST"
	else
		postconf -e "relayhost ="
		log "outgoing mail directly to the recipients' MX (port 25 outbound must be open)"
	fi
	# Per-domain routes for outgoing mail, for hosts that can't send on
	# port 25: TRANSPORT_MAPS="mixmin.net smtp:[fleegle.mixmin.net]:2525;
	# virebent.art smtps:[mail.virebent.art]:465".  "smtps:" means TLS from
	# the start (port 465).
	postconf -M "smtps/unix=smtps unix - - n - - smtp"
	postconf -P "smtps/unix/smtp_tls_wrappermode=yes" \
		"smtps/unix/smtp_tls_security_level=encrypt"
	if [ -n "${TRANSPORT_MAPS:-}" ]; then
		echo "$TRANSPORT_MAPS" | tr ';' '\n' | sed 's/^[[:space:]]*//; /^$/d' \
			>/etc/postfix/transport
		postmap /etc/postfix/transport
		postconf -e "transport_maps = hash:/etc/postfix/transport"
		while read -r d t; do log "mail for $d goes to $t"; done </etc/postfix/transport
	else
		postconf -e "transport_maps ="
	fi
	# Run the Postfix services without chroot: the container is the boundary.
	postconf -F '*/*/chroot = n'
	# Mail for root, postmaster and abuse goes to the operator.  If the
	# operator's address is in the pinger's own domain it can't be
	# delivered here, so it ends up in Echolot's Maildir, which discards it.
	# POSTMASTER_TO=pinger discards it, e.g. if the operator's mail server
	# can't be reached from here.
	local alias_to=${POSTMASTER_TO:-$operator}
	case "$alias_to" in
	*@"$domain")
		log "warning: set PINGER_OPERATOR to an address outside $domain to receive postmaster mail"
		alias_to=pinger
		;;
	esac
	printf 'root: %s\npostmaster: %s\nabuse: %s\n' "$alias_to" "$alias_to" "$alias_to" >/etc/aliases
	newaliases
	postfix check
	log "receiving mail for $domain as $hostname (TLS certificate $cert)"
}

case "$mode" in
hostmail) setup_msmtp ;;
postfix) setup_postfix ;;
*) die "unknown PINGER_MAIL=$mode" ;;
esac

# --- Run -------------------------------------------------------------------
pids=()
stop() {
	log "stopping"
	for p in "${pids[@]}"; do kill -TERM "$p" 2>/dev/null || true; done
	wait || true
	exit "${1:-0}"
}
trap 'stop 0' TERM INT

if [ "$mode" = postfix ]; then
	postfix start-fg &
	pids+=($!)
	# Reload Postfix when certbot renews the certificate.
	(
		cert=${TLS_CERT:-$home/tls/cert.pem}
		last=$(stat -L -c %Y "$cert")
		while sleep 3600; do
			now=$(stat -L -c %Y "$cert" 2>/dev/null || echo "$last")
			if [ "$now" != "$last" ]; then
				log "TLS certificate changed, reloading Postfix"
				postfix reload || true
				last=$now
			fi
		done
	) &
	pids+=($!)
fi

runuser -u pinger -- /opt/echolot/pingd start &
pids+=($!)
# pingd logs to pingd.log (it can't open the container's stdout as the
# pinger user); copy it to the container log.
if [ "${PINGER_LOG:-stdout}" = stdout ]; then
	touch "$home/pingd.log" && chown pinger:pinger "$home/pingd.log"
	tail -n 0 -F "$home/pingd.log" &
	pids+=($!)
fi

# Seed the remailer list once, after pingd has started.
if [ -n "${PINGER_REMAILERS:-}" ] && [ ! -e "$home/.remailers-added" ]; then
	for _ in $(seq 60); do [ -e /run/echolot/pingd.pid ] && break; sleep 1; done
	for a in $PINGER_REMAILERS; do
		log "adding remailer $a"
		runuser -u pinger -- /opt/echolot/pingd add "$a" || true
	done
	runuser -u pinger -- /opt/echolot/pingd getkeyconf || true
	touch "$home/.remailers-added"
fi

# Stop the container when pingd or Postfix stops, so the restart policy
# can start it again.
set +e
wait -n
status=$?
log "a service exited with status $status"
stop 1
