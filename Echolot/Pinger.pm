package Echolot::Pinger;

# (c) 2002 Peter Palfrader <peter@palfrader.org>
# $Id: Pinger.pm,v 1.22 2003/01/14 05:25:35 weasel Exp $
#

=pod

=head1 Name

Echolot::Pinger - actual sending and receiving of Pings.

=head1 DESCRIPTION

This package provides functions for sending out and receiving pings.

=cut

use strict;
use English;
use Echolot::Log;
use Echolot::Pinger::Mix;
use Echolot::Pinger::CPunk;

sub do_mix_ping($$$$$) {
	my ($address, $keyid, $time, $to, $body) = @_;

	my %key = Echolot::Globals::get()->{'storage'}->get_key($address, 'mix', $keyid);
	Echolot::Pinger::Mix::ping(
		$body,
		$to,
		[ $key{'nick'} ],
		{ $keyid => \%key } ) or
		return 0;

	return 1;
};

sub do_cpunk_ping($$$$$$) {
	my ($address, $type, $keyid, $time, $to, $body) = @_;

	my $keyhash;
	if ($type ne 'cpunk-clear') {
		my %key = Echolot::Globals::get()->{'storage'}->get_key($address, $type, $keyid);
		$keyhash = { $keyid => \%key };
	};
	Echolot::Pinger::CPunk::ping(
		$body,
		$to,
		[ { address => $address,
		    keyid   => $keyid,
			encrypt => ($type ne 'cpunk-clear') } ],
		$keyhash,
		$type eq 'cpunk-rsa' ) or
		return 0;

	return 1;
};

sub do_ping($$$) {
	my ($type, $address, $key) = @_;
	
	my $now = time();
	my $token = $address.':'.$type.':'.$key.':'.$now;
	my $mac = Echolot::Tools::make_mac($token);
	my $body = "remailer: $address\n".
		"type: $type\n".
		"key: $key\n".
		"sent: $now\n".
		"mac: $mac\n";
	$body = Echolot::Tools::crypt_symmetrically($body, 'encrypt');
		
	my $to = Echolot::Tools::make_address('ping');
	if ($type eq 'mix') {
		do_mix_ping($address, $key, $now, $to, $body);
	} elsif ($type eq 'cpunk-rsa' || $type eq 'cpunk-dsa' || $type eq 'cpunk-clear') {
		do_cpunk_ping($address, $type, $key, $now, $to, $body);
	} else {
		Echolot::Log::warn("Don't know how to handle ping type $type.");
		return 0;
	};

	Echolot::Globals::get()->{'storage'}->register_pingout($address, $type, $key, $now);
	return 1;
};

sub send_pings($;$) {
	my ($scheduled_for, $which) = @_;

	$which = '' unless defined $which;

	my $call_intervall = Echolot::Config::get()->{'pinger_interval'};
	my $send_every_n_calls = Echolot::Config::get()->{'ping_every_nth_time'};

	my $timemod = int ($scheduled_for / $call_intervall);
	my $this_call_id = $timemod % $send_every_n_calls;
	my $session_id = int ($scheduled_for / ($call_intervall * $send_every_n_calls));

	my @remailers = Echolot::Globals::get()->{'storage'}->get_remailers();
	for my $remailer (@remailers) {
		next unless $remailer->{'pingit'};
		my $address = $remailer->{'address'};

		next unless (
			$which eq 'all' ||
			$which eq $address ||
			$which eq '');

		for my $type (Echolot::Globals::get()->{'storage'}->get_types($address)) {
			next unless Echolot::Config::get()->{'do_pings'}->{$type};
			for my $key (Echolot::Globals::get()->{'storage'}->get_keys($address, $type)) {
				next unless (
					$which eq $address ||
					$which eq 'all' ||
					(($which eq '') && ($this_call_id eq (Echolot::Tools::makeShortNumHash($address.$type.$key.$session_id) % $send_every_n_calls))));

				Echolot::Log::debug("ping calling $type, $address, $key.");
				do_ping($type, $address, $key);
			}
		};
	};
	return 1;
};


sub receive($$$) {
	my ($msg, $token, $timestamp) = @_;

	my $now = time();

	my $body;
	if ($msg =~ /^-----BEGIN PGP MESSAGE-----/m) {
		# work around borken middleman remailers that have a problem with some
		# sort of end of line characters and randhopping them through reliable
		# remailers..
		# they add an empty line between each usefull line
		$msg =~ s/(\r?\n)\r?\n/$1/g if ($msg =~ /^-----BEGIN PGP MESSAGE-----\r?\n\r?\n/m);
		$body = Echolot::Tools::crypt_symmetrically($msg, 'decrypt');
	};
	$body = $msg unless defined $body;

	my ($addr) = $body =~ /^remailer: (.*)$/m;
	my ($type) = $body =~ /^type: (.*)$/m;
	my ($key) = $body =~ /^key: (.*)$/m;
	my ($sent) = $body =~ /^sent: (.*)$/m;
	my ($mac) = $body =~ /^mac: (.*)$/m;

	my $cleanstring = (defined $addr ? $addr : 'undef') . ':' .
	                  (defined $type ? $type : 'undef') . ':' .
	                  (defined $key  ? $key : 'undef') . ':' .
	                  (defined $sent ? $sent : 'undef') . ':' .
	                  (defined $mac  ? $mac : 'undef') . ':';

	(defined $addr && defined $type && defined $key && defined $sent && defined $mac) or
		Echolot::Log::warn("Received ping at $timestamp has undefined values: $cleanstring."),
		return 0;

	Echolot::Tools::verify_mac($addr.':'.$type.':'.$key.':'.$sent, $mac) or
		Echolot::Log::warn("Received ping at $timestamp has wrong mac; $cleanstring."),
		return 0;

	Echolot::Globals::get()->{'storage'}->register_pingdone($addr, $type, $key, $sent, $now - $sent) or
		return 0;
	
	return 1;
};

1;
# vim: set ts=4 shiftwidth=4:
