package Echolot::Pinger;

# (c) 2002 Peter Palfrader <peter@palfrader.org>
# $Id: Pinger.pm,v 1.4 2002/06/11 11:05:52 weasel Exp $
#

=pod

=head1 Name

Echolot::Pinger - actual sending and receiving of Pings.

=head1 DESCRIPTION

This package provides functions for sending out and receiving pings.

=cut

use strict;
use warnings;
use Carp qw{cluck};
use English;
use Echolot::Pinger::Mix;

sub makeHash($) {
	my ($text) = @_;
	my $sum = 0;
	for (my $i=0; $i < length($text); $i++) {
		$sum += ord( substr($text, $i, 1) )
	};
	return $sum;
};

sub do_mix_ping($$$$$) {
	my ($address, $keyid, $time, $to, $body) = @_;

	my %key = Echolot::Globals::get()->{'storage'}->get_key($address, 'mix', $keyid);
	Echolot::Pinger::Mix::ping(
		$body,
		$to,
		$key{'nick'},
		{ $keyid => \%key } ) or
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
		
	my $to = Echolot::Tools::make_address('ping');
	if ($type eq 'mix') {
		do_mix_ping($address, $key, $now, $to, $body);
	} else {
		cluck ("Don't know how to handle ping type $type");
		return 0;
	};

	Echolot::Globals::get()->{'storage'}->register_pingout($address, $type, $key, $now);
	return 1;
};

sub send_pings() {
	my $call_intervall = Echolot::Config::get()->{'pinger_interval'};
	my $send_every_n_calls = Echolot::Config::get()->{'ping_every_nth_time'};

	my $now = time();

	my @remailers = Echolot::Globals::get()->{'storage'}->get_remailers();
	for my $remailer (@remailers) {
		my $timemod = ($now / $call_intervall);
		my $this_call_id = $timemod % $send_every_n_calls;

		my $this_remailer_id = makeHash($remailer) % $send_every_n_calls;
		
		next unless ($this_call_id eq $this_remailer_id);

		for my $type (Echolot::Globals::get()->{'storage'}->get_types($remailer)) {
			for my $key (Echolot::Globals::get()->{'storage'}->get_keys($remailer, $type)) {
				do_ping($type, $remailer, $key);
			}
		};
	};
	return 1;
};


sub receive($$$) {
	my ($body, $token, $timestamp) = @_;

	my $now = time();

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

	print "Foo\n";
	(defined $addr && defined $type && defined $key && defined $sent && defined $mac) or
		warn ("Received ping at $timestamp has undefined values: $cleanstring\n"), #FIXME: logging
		return 0;

	print "Foo\n";
	Echolot::Tools::verify_mac($addr.':'.$type.':'.$key.':'.$sent, $mac) or
		warn ("Received ping at $timestamp has wrong mac; $cleanstring\n"), #FIXME: logging
		return 0;

	print "Foo\n";
	Echolot::Globals::get()->{'storage'}->register_pingdone($addr, $type, $key, $sent, $now - $sent) or
		return 0;
	
	return 1;
};

1;
# vim: set ts=4 shiftwidth=4:
