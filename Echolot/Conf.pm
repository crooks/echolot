package Echolot::Conf;

# (c) 2002 Peter Palfrader <peter@palfrader.org>
# $Id: Conf.pm,v 1.2 2002/06/10 05:12:55 weasel Exp $
#

=pod

=head1 Name

Echolot::Conf - remailer Configuration/Capabilities

=head1 DESCRIPTION

This package provides functions for requesting, parsing, and analyzing
remailer-conf and remailer-key replies.

=cut

use strict;
use warnings;
use Carp qw{cluck};


sub send_requests() {
	Echolot::Globals::get()->{'storage'}->delay_commit();
	for my $remailer (Echolot::Globals::get()->{'storage'}->get_addresses()) {
		next unless ($remailer->{'status'} eq 'active');
		for my $type (qw{conf key help stats}) {
			Echolot::Tools::send_message(
				'To' => $remailer->{'address'},
				'Subject' => 'remailer-'.$type,
				'Token' => $type.'.'.$remailer->{'id'})
		};
		Echolot::Globals::get()->{'storage'}->decrease_ttl($remailer->{'address'});
	};
	Echolot::Globals::get()->{'storage'}->enable_commit();
};

sub remailer_conf($$$) {
	my ($conf, $token, $time) = @_;

	my ($id) = $token =~ /^conf\.(\d+)$/;
	(defined $id) &&
		cluck ("Returned token '$token' has no id at all"),
		return 0;

	cluck("Could not find id in token '$token'"), return 0 unless defined $id;
	my ($remailer_type) = ($conf =~ /^\s*Remailer-Type:\s* (.*?) \s*$/imx);
	cluck("No remailer type found in remailer_conf from '$token'"), return 0 unless defined $remailer_type;
	my ($remailer_caps) = ($conf =~ /^\s*(  \$remailer{".*"}  \s*=\s*  "<.*@.*>.*";   )\s*$/imx);
	cluck("No remailer caps found in remailer_conf from '$token'"), return 0 unless defined $remailer_caps;
	my ($remailer_nick, $remailer_address) = ($remailer_caps =~ /^\s*  \$remailer{"(.*)"}  \s*=\s*  "<(.*@.*)>.*";   \s*$/ix);
	cluck("No remailer nick found in remailer_caps from '$token': '$remailer_caps'"), return 0 unless defined $remailer_nick;
	cluck("No remailer address found in remailer_caps from '$token': '$remailer_caps'"), return 0 unless defined $remailer_address;
	

	my $remailer = Echolot::Globals::get()->{'storage'}->get_address_by_id($id);
	cluck("No remailer found for id '$id'"), return 0 unless defined $remailer;
	if ($remailer->{'address'} ne $remailer_address) {
		# Address mismatch -> Ignore reply and add $remailer_address to prospective addresses
		cluck("Remailer address mismatch $remailer->{'address'} vs $remailer_address. Adding latter to prospective remailers.");
		Echolot::Globals::get()->{'storage'}->add_prospective_address($remailer_address, 'conf-reply');
	} else {
		Echolot::Globals::get()->{'storage'}->restore_ttl( $remailer->{'address'} );
		Echolot::Globals::get()->{'storage'}->set_caps($remailer_type, $remailer_caps, $remailer_nick, $remailer_address, $time);
	}

	return 1;
};

sub remailer_key($$$) {
	my ($conf, $token, $time) = @_;

	my ($id) = $token =~ /^key\.(\d+)$/;
	(defined $id) or
		cluck ("Returned token '$token' has no id at all"),
		return 0;

	my $remailer = Echolot::Globals::get()->{'storage'}->get_address_by_id($id);
	cluck("No remailer found for id '$id'"), return 0 unless defined $remailer;
# -----Begin Mix Key-----
# 7f6d997678b19ccac110f6e669143126
# 258
# AASyedeKiP1/UKyfrBz2K6gIhv4jfXIaHo8dGmwD
# KqkG3DwytgSySSY3wYm0foT7KvEnkG2aTi/uJva/
# gymE+tsuM8l8iY1FOiXwHWLDdyUBPbrLjRkgm7GD
# Y7ogSjPhVLeMpzkSyO/ryeUfLZskBUBL0LxjLInB
# YBR3o6p/RiT0EQAAAAAAAAAAAAAAAAAAAAAAAAAA
# AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
# AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
# AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
# AAAAAAAAAAAAAAAAAAAAAQAB
# -----End Mix Key-----

	my %mixmasters;
	# rot26 rot26@mix.uucico.de 7f6d997678b19ccac110f6e669143126 2.9b33 MC
	my @mix_confs = ($conf =~ /^[a-z0-9]+ \s+ \S+\@\S+ \s+ [0-9a-f]{32} (?:\s+ \S+ \s+ \S+)?/xmg);
	my @mix_keys = ($conf =~ /^-----Begin \s Mix \s Key-----\r?\n
	                          [0-9a-f]{32}\r?\n
							  \d+\r?\n
							  (?:[a-zA-Z0-9+\/]*\r?\n)+
							  -----End \s Mix \s Key-----$/xmg );
	for (@mix_confs) {
		my ($nick, $address, $keyid, $version, $caps) = /^([a-z0-9]+) \s+ (\S+@\S+) \s+ ([0-9a-f]{32}) (?:(\S+) \s+ (\S+))?/x;
		$mixmasters{$keyid} = {
			nick	=> $nick,
			address => $address,
			version => $version,
			caps    => $caps,
			summary => $_
		};
	};
	for (@mix_keys) {
		my ($keyid) =  /^-----Begin \s Mix \s Key-----\r?\n
	                          ([0-9a-f]{32})\r?\n
							  \d+\r?\n
							  (?:[a-zA-Z0-9+\/]*\r?\n)+
							  -----End \s Mix \s Key-----$/xmg;
		$mixmasters{$keyid}->{'key'} = $_;
	};

	for my $keyid (keys %mixmasters) {
		my $remailer_address = $mixmasters{$keyid}->{'address'};
		(defined $mixmasters{$keyid}->{'nick'} && ! defined $mixmasters{$keyid}->{'key'}) and
			cluck("Mixmaster key header without key in reply from $remailer_address"),
			next;
		(! defined $mixmasters{$keyid}->{'nick'} && defined $mixmasters{$keyid}->{'key'}) and
			cluck("Mixmaster key without key header in reply from $remailer_address"),
			next;

		if ($remailer->{'address'} ne $remailer_address) {
			# Address mismatch -> Ignore reply and add $remailer_address to prospective addresses
			cluck("Remailer address mismatch $remailer->{'address'} vs $remailer_address. Adding latter to prospective remailers.");
			Echolot::Globals::get()->{'storage'}->add_prospective_address($remailer_address, 'key-reply');
		} else {
			Echolot::Globals::get()->{'storage'}->restore_ttl( $remailer->{'address'} );
			Echolot::Globals::get()->{'storage'}->set_key(
				'mix',
				$mixmasters{$keyid}->{'nick'},
				$mixmasters{$keyid}->{'address'},
				$mixmasters{$keyid}->{'key'},
				$keyid,
				$mixmasters{$keyid}->{'version'},
				$mixmasters{$keyid}->{'caps'},
				$mixmasters{$keyid}->{'summary'},
				$time);
		}
	};

	return 1;
};

sub remailer_stats($$$) {
	my ($conf, $token, $time) = @_;

	#print "Remailer stats\n";
};

sub remailer_help($$$) {
	my ($conf, $token, $time) = @_;

	#print "Remailer help\n";
};

1;
# vim: set ts=4 shiftwidth=4:
