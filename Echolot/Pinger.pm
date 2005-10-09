package Echolot::Pinger;

#
# $Id$
#
# This file is part of Echolot - a Pinger for anonymous remailers.
#
# Copyright (c) 2002, 2003, 2004 Peter Palfrader <peter@palfrader.org>
#
# This program is free software. you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301 USA
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

sub do_mix_ping($$$$$$) {
	my ($address, $type, $keyid, $to, $with_from, $body) = @_;

	($type eq 'mix') or
		Echolot::Log::warn("types should really be mix ($type)."),
		return 0;

	my %key = Echolot::Globals::get()->{'storage'}->get_key($address, $type, $keyid);
	Echolot::Pinger::Mix::ping(
		$body,
		$to,
		$with_from,
		[ $key{'nick'} ],
		{ $keyid => \%key } ) or
		return 0;

	return 1;
};

sub do_cpunk_ping($$$$$$) {
	my ($address, $type, $keyid, $to, $with_from, $body) = @_;

	my $keyhash = {};
	if ($type ne 'cpunk-clear') {
		my %key = Echolot::Globals::get()->{'storage'}->get_key($address, $type, $keyid);
		$keyhash->{$keyid} = \%key;
	};
	Echolot::Pinger::CPunk::ping(
		$body,
		$to,
		$with_from,
		[ { address    => $address,
		    keyid      => $keyid,
		    encrypt    => ($type ne 'cpunk-clear'),
		    pgp2compat => ($type eq 'cpunk-rsa') } ],
		$keyhash ) or
		return 0;

	return 1;
};

sub do_ping($$$$) {
	my ($type, $address, $key, $with_from) = @_;
	
	my $now = time();
	my $token = join(':', $address, $type, $key, $with_from, $now);
	my $mac = Echolot::Tools::make_mac($token);
	my $body = "remailer: $address\n".
		"type: $type\n".
		"key: $key\n".
		"with_from: $with_from\n".
		"sent: $now\n".
		"mac: $mac\n".
		Echolot::Tools::make_garbage();
	$body = Echolot::Tools::crypt_symmetrically($body, 'encrypt');
		
	my $to = Echolot::Tools::make_address('ping');
	if ($type eq 'mix') {
		do_mix_ping($address, $type, $key, $to, $with_from, $body);
	} elsif ($type eq 'cpunk-rsa' || $type eq 'cpunk-dsa' || $type eq 'cpunk-clear') {
		do_cpunk_ping($address, $type, $key, $to, $with_from, $body);
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

	my @remailers = Echolot::Globals::get()->{'storage'}->get_addresses();
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

				my $with_from = (int($timemod / $send_every_n_calls)) % 2;
				Echolot::Log::debug("ping calling $type, $address, $key, $with_from.");
				do_ping($type, $address, $key, $with_from);
			}
		};
	};
	return 1;
};


sub receive($$$$) {
	my ($header, $msg, $token, $timestamp) = @_;

	my $now = time();

	my $body;
	my $bot = 0;
	my $top = 0;
	# < 2.0beta34 didn't encrypt pings.
	if ($msg =~ /^-----BEGIN PGP MESSAGE-----/m) {
		# work around borken middleman remailers that have a problem with some
		# sort of end of line characters and randhopping them through reliable
		# remailers..
		# they add an empty line between each usefull line
		$msg =~ s/(\r?\n)\r?\n/$1/g if ($msg =~ /^-----BEGIN PGP MESSAGE-----\r?\n\r?\n/m);

		$top = ($msg =~ m/^\S.*-----BEGIN PGP MESSAGE-----/ms) ? 1 : 0;
		$bot = ($msg =~ m/^-----END PGP MESSAGE-----.*\S/ms) ? 1 : 0;

		$body = Echolot::Tools::crypt_symmetrically($msg, 'decrypt');
	};
	$body = $msg unless defined $body;

	my ($addr) = $body =~ /^remailer: (.*)$/m;
	my ($type) = $body =~ /^type: (.*)$/m;
	my ($key) = $body =~ /^key: (.*)$/m;
	my ($sent) = $body =~ /^sent: (.*)$/m;
	my ($with_from) = $body =~ /^with_from: (.*)$/m;
	my ($mac) = $body =~ /^mac: (.*)$/m;

	my @values = ($addr, $type, $key, defined $with_from ? $with_from : 'undef', $sent, $mac); # undef was added after 2.0.10
	my $cleanstring = join ":", map { defined() ? $_ : "undef" } @values;
	my @values_obsolete = ($addr, $type, $key, $sent, $mac); # <= 2.0.10

	(grep { ! defined() } @values_obsolete) and
		Echolot::Log::warn("Received ping at $timestamp has undefined values: $cleanstring."),
		return 0;

	pop @values;
	pop @values_obsolete;
	Echolot::Tools::verify_mac(join(':', @values), $mac) or
		Echolot::Tools::verify_mac(join(':', @values_obsolete), $mac) or # old style without with_from
			Echolot::Log::warn("Received ping at $timestamp has wrong mac; $cleanstring."),
			return 0;

	Echolot::Globals::get()->{'storage'}->register_pingdone($addr, $type, $key, $sent, $now - $sent) or
		return 0;

	if (defined $with_from) { # <= 2.0.10 didn't have with_from
		my ($from) = $header =~ /From: (.*)/i;
		$from = 'undefined' unless defined $from;
		Echolot::Globals::get()->{'storage'}->register_fromline($addr, $type, $with_from, $from, $top, $bot);
	};

	return 1;
};

1;
# vim: set ts=4 shiftwidth=4:
