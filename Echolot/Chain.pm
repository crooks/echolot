package Echolot::Chain;

# (c) 2002 Peter Palfrader <peter@palfrader.org>
# $Id: Chain.pm,v 1.1 2003/02/14 05:03:15 weasel Exp $
#

=pod

=head1 Name

Echolot::Chain - actual sending and receiving of Chain-Pings.

=head1 DESCRIPTION

This package provides functions for sending out and receiving chain-pings.

=cut

use strict;
use English;
use Echolot::Log;
use Echolot::Pinger::Mix;
use Echolot::Pinger::CPunk;

sub do_mix_chainping($$$$$$$$) {
	my ($addr1, $type1, $keyid1, $addr2, $type2, $keyid2, $to, $body) = @_;

	($type1 eq 'mix' && $type2 eq 'mix') or
		Echolot::Log::warn("both types should really be mix ($type1, $type2)."),
		return 0;

	my %key1 = Echolot::Globals::get()->{'storage'}->get_key($addr1, $type1, $keyid1);
	my %key2 = Echolot::Globals::get()->{'storage'}->get_key($addr2, $type2, $keyid2);
	Echolot::Pinger::Mix::ping(
		$body,
		$to,
		[ $key1{'nick'}    , $key2{'nick'}     ],
		{ $keyid1 => \%key1, $keyid2 => \%key2 } ) or
		return 0;

	return 1;
};

sub do_cpunk_ping($$$$$$$$) {
	my ($addr1, $type1, $keyid1, $addr2, $type2, $keyid2, $to, $body) = @_;

	my $keyhash = {};
	if ($type1 ne 'cpunk-clear') {
		my %key = Echolot::Globals::get()->{'storage'}->get_key($addr1, $type1, $keyid1);
		$keyhash->{$keyid1} = \%key;
	};
	if ($type2 ne 'cpunk-clear') {
		my %key = Echolot::Globals::get()->{'storage'}->get_key($addr2, $type2, $keyid2);
		$keyhash->{$keyid2} = \%key;
	};
	Echolot::Pinger::CPunk::ping(
		$body,
		$to,
		[ { address    => $addr1,
		    keyid      => $keyid1,
		    encrypt    => ($type1 ne 'cpunk-clear'),
		    pgp2compat => ($type1 eq 'cpunk-rsa') },
		  { address    => $addr2,
		    keyid      => $keyid2,
		    encrypt    => ($type2 ne 'cpunk-clear'),
		    pgp2compat => ($type2 eq 'cpunk-rsa') } ],
		$keyhash ) or
		return 0;

	return 1;
};

sub do_chainping($$$$$$$) {
	my ($chaintype, $addr1, $type1, $key1, $addr2, $type2, $key2) = @_;
	
	my $now = time();
	my $token = join(':', $chaintype, $addr1, $type1, $key1, $addr2, $type2, $key2, $now);
	my $mac = Echolot::Tools::make_mac($token);
	my $body = "chaintype: $chaintype\n".
		"remailer1: $addr1\n".
		"type1: $type1\n".
		"key1: $key1\n".
		"remailer2: $addr2\n".
		"type2: $type2\n".
		"key2: $key2\n".
		"sent: $now\n".
		"mac: $mac\n";
	$body = Echolot::Tools::crypt_symmetrically($body, 'encrypt');
		
	my $to = Echolot::Tools::make_address('chainping');
	if ($chaintype eq 'mix') {
		do_mix_chainping($addr1, $type1, $key1, $addr2, $type2, $key2, $to, $body);
	} elsif ($chaintype eq 'cpunk') {
		do_cpunk_chainping($addr1, $type1, $key1, $addr2, $type2, $key2, $to, $body);
	} else {
		Echolot::Log::warn("Don't know how to handle chain ping type $chaintype.");
		return 0;
	};

	Echolot::Globals::get()->{'storage'}->register_chainpingout($chaintype, $addr1, $type1, $key1, $addr2, $type2, $key2, $now);
	return 1;
};

sub remailer_supports_chaintype($$) {
	my ($address, $type) = @_;

	my %supports = map { $_ => 1} Echolot::Globals::get()->{'storage'}->get_types($address);
	for my $type (@{Echolot::Config::get()->{'do_chainpings'}->{$type}}) {
		return $type if $supports{$type};
	};
	return 0;
};
sub get_latest_key($$) {
	my ($address, $type) = @_;

	my $latest = 0;
	my $chosen = undef;
	for my $keyid (Echolot::Globals::get()->{'storage'}->get_keys($address, $type)) {
		my $key = Echolot::Globals::get()->{'storage'}->get_key($address, $type, $keyid);
		$chosen = $keyid if $latest < $key->{'last_updated'};
	};
	return $chosen;
};

sub send_pings($;$$) {
	my ($scheduled_for, $which1, $which2) = @_;

	$which1 = '' unless defined $which1;
	$which2 = '' unless defined $which2;

	my $call_intervall = Echolot::Config::get()->{'chainpinger_interval'};
	my $send_every_n_calls = Echolot::Config::get()->{'chainping_every_nth_time'};

	my $timemod = int ($scheduled_for / $call_intervall);
	my $this_call_id = $timemod % $send_every_n_calls;
	my $session_id = int ($scheduled_for / ($call_intervall * $send_every_n_calls));

	my @remailers = Echolot::Globals::get()->{'storage'}->get_remailers();
	for my $rem1 (@remailers) {
		next unless $rem1->{'pingit'};
		my $addr1 = $rem1->{'address'};

		next unless (
			$which1 eq 'all' ||
			$which1 eq $addr1 ||
			$which1 eq '');

		for my $chaintype (keys %{Echolot::Config::get()->{'do_chainpings'}}) {
			my $type1 = remailer_supports_chaintype($addr1, $chaintype);;
			next unless $type1;
			my $key1 = get_latest_key($addr1, $type1);

			for my $rem2 (@remailers) {
				next unless $rem2->{'pingit'};
				my $addr2 = $rem2->{'address'};

				next unless (
					$which2 eq 'all' ||
					$which2 eq $addr2 ||
					$which2 eq '');

				my $type2 = remailer_supports_chaintype($addr2, $chaintype);;
				next unless $type2;
				my $key2 = get_latest_key($addr2, $type2);


				next unless (
					(($which1 eq $addr1 || $which1 eq 'all' ) && ($which2 eq $addr2 ||  $which2 eq 'all')) ||
					(($which1 eq '' && $which2 eq '') && ($this_call_id eq (Echolot::Tools::makeShortNumHash($addr1.$addr2.$chaintype.$session_id) % $send_every_n_calls))));

				Echolot::Log::debug("chainping calling $chaintype, $addr1 ($type1, $key1) - $addr2 ($type2, $key2)");
				do_chainping($chaintype, $addr1, $type1, $key1, $addr2, $type2, $key2);
			};
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

	my ($chaintype) = $body =~ /^chaintype (.*)$/m;
	my ($addr1) = $body =~ /^remailer1: (.*)$/m;
	my ($type1) = $body =~ /^type1: (.*)$/m;
	my ($key1) = $body =~ /^key1: (.*)$/m;
	my ($addr2) = $body =~ /^remailer2: (.*)$/m;
	my ($type2) = $body =~ /^type2: (.*)$/m;
	my ($key2) = $body =~ /^key2: (.*)$/m;
	my ($sent) = $body =~ /^sent: (.*)$/m;
	my ($mac) = $body =~ /^mac: (.*)$/m;

	my @values = ($chaintype, $addr1, $type1, $key1, $addr2, $type2, $key2, $sent, $mac);
	my $cleanstring = join ":", map { defined() ? $_ : "undef" } @values;

	(grep { ! defined() } @values) and
		Echolot::Log::warn("Received chainping at $timestamp has undefined values: $cleanstring."),
		return 0;

	pop @values;
	Echolot::Tools::verify_mac(join(':', @values), $mac) or
		Echolot::Log::warn("Received chainping at $timestamp has wrong mac; $cleanstring."),
		return 0;

	Echolot::Globals::get()->{'storage'}->register_chainpingdone($chaintype, $addr1, $type1, $key1, $addr2, $type2, $key2, $now - $sent) or
		return 0;
	
	return 1;
};

1;
# vim: set ts=4 shiftwidth=4:
