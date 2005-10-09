package Echolot::Conf;

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

Echolot::Conf - remailer Configuration/Capabilities

=head1 DESCRIPTION

This package provides functions for requesting, parsing, and analyzing
remailer-conf and remailer-key replies.

=head1 CAVEATS

When parsing OpenPGP keys only the address of the primary user id is taken into
account (This is the one with the latest self signature I think).

=cut

use strict;
use Echolot::Log;
use GnuPG::Interface;


sub is_not_a_remailer($) {
	my ($reply) = @_;
	if ($reply =~ /^\s* not \s+ a \s+ remailer\b/xi) {
		return 1;
	} else {
		return 0;
	};
};

sub send_requests($;$) {
	my ($scheduled_for, $which) = @_;

	$which = '' unless defined $which;

	my $call_intervall = Echolot::Config::get()->{'getkeyconf_interval'};
	my $send_every_n_calls = Echolot::Config::get()->{'getkeyconf_every_nth_time'};

	my $timemod = int ($scheduled_for / $call_intervall);
	my $this_call_id = $timemod % $send_every_n_calls;
	my $session_id = int ($scheduled_for / ($call_intervall * $send_every_n_calls));

	Echolot::Globals::get()->{'storage'}->delay_commit();
	
	for my $remailer (Echolot::Globals::get()->{'storage'}->get_addresses()) {
		next unless ($remailer->{'status'} eq 'active');
		next unless ($remailer->{'fetch'});
		my $address = $remailer->{'address'};

		next unless (
			$which eq 'all' ||
			$which eq $address ||
			$which eq '');

		for my $type (qw{conf key help stats adminkey}) {

			next unless (
				$which eq $address ||
				$which eq 'all' ||
				(($which eq '') && ($this_call_id == (Echolot::Tools::makeShortNumHash($address.$type.$session_id) % $send_every_n_calls))));

			Echolot::Log::debug("Sending $type request to ".$address.".");

			my $source_text = Echolot::Config::get()->{'remailerxxxtext'};
			my $template =  HTML::Template->new(
				scalarref => \$source_text,
				strict => 0,
				global_vars => 1 );
			$template->param ( address => $address );
			$template->param ( operator_address => Echolot::Config::get()->{'operator_address'} );
			my $body = $template->output();

			Echolot::Tools::send_message(
				'To' => $address,
				'Subject' => 'remailer-'.$type,
				'Token' => $type.'.'.$remailer->{'id'},
				'Body' => $body);

			Echolot::Globals::get()->{'storage'}->decrease_ttl($address) if (($type eq 'conf') && ($which eq ''));
		};
	};
	Echolot::Globals::get()->{'storage'}->enable_commit();
};

sub check_resurrection() {
	Echolot::Globals::get()->{'storage'}->delay_commit();
	for my $remailer (Echolot::Globals::get()->{'storage'}->get_addresses()) {
		next unless ($remailer->{'status'} eq 'ttl timeout');
		next unless ($remailer->{'fetch'});
		next unless ($remailer->{'resurrection_ttl'});
		Echolot::Log::debug("Sending request to ".$remailer->{'address'}." to check for resurrection.");
		for my $type (qw{conf key help stats adminkey}) {
			Echolot::Tools::send_message(
				'To' => $remailer->{'address'},
				'Subject' => 'remailer-'.$type,
				'Token' => $type.'.'.$remailer->{'id'})
		};
		Echolot::Globals::get()->{'storage'}->decrease_resurrection_ttl($remailer->{'address'});
	};
	Echolot::Globals::get()->{'storage'}->enable_commit();
};


sub remailer_caps($$$;$) {
	my ($conf, $token, $time, $dontexpire) = @_;

	my ($id) = $token =~ /^conf\.(\d+)$/;
	(defined $id) or
		Echolot::Log::info("Returned token '$token' has no id at all."),
		return 0;

	Echolot::Log::info("Could not find id in token '$token'."), return 0 unless defined $id;
	my ($remailer_type) = ($conf =~ /^\s*Remailer-Type:\s* (.*?) \s*$/imx);
	Echolot::Log::info("No remailer type found in remailer_caps from '$token'."), return 0 unless defined $remailer_type;
	my ($remailer_caps) = ($conf =~ /^\s*(  \$remailer{".*"}  \s*=\s*  "<.*@.*>.*";   )\s*$/imx);
	Echolot::Log::info("No remailer caps found in remailer_caps from '$token'."), return 0 unless defined $remailer_caps;
	my ($remailer_nick, $remailer_address) = ($remailer_caps =~ /^\s*  \$remailer{"(.*)"}  \s*=\s*  "<(.*@.*)>.*";   \s*$/ix);
	Echolot::Log::info("No remailer nick found in remailer_caps from '$token': '$remailer_caps'."), return 0 unless defined $remailer_nick;
	Echolot::Log::info("No remailer address found in remailer_caps from '$token': '$remailer_caps'."), return 0 unless defined $remailer_address;
	

	my $remailer = Echolot::Globals::get()->{'storage'}->get_address_by_id($id);
	Echolot::Log::info("No remailer found for id '$id'."), return 0 unless defined $remailer;
	if ($remailer->{'address'} ne $remailer_address) {
		# Address mismatch -> Ignore reply and add $remailer_address to prospective addresses
		Echolot::Log::info("Remailer address mismatch $remailer->{'address'} vs $remailer_address. Adding latter to prospective remailers.");
		Echolot::Globals::get()->{'storage'}->add_prospective_address($remailer_address, 'self-capsstring-conf', $remailer_address);
	} else {
		Echolot::Log::debug("Setting capabilities for $remailer_address");
		Echolot::Globals::get()->{'storage'}->restore_ttl( $remailer->{'address'} );
		Echolot::Globals::get()->{'storage'}->set_caps($remailer_type, $remailer_caps, $remailer_nick, $remailer_address, $time, $dontexpire);

		# if remailer is cpunk and not pgponly
		if (($remailer_caps =~ /\bcpunk\b/) && !($remailer_caps =~ /\bpgponly\b/)) {
			Echolot::Globals::get()->{'storage'}->set_key(
				'cpunk-clear',
				$remailer_nick,
				$remailer->{'address'},
				'N/A',
				'none',
				'N/A',
				'N/A',
				'N/A',
				$time);
		}
	}


	# Fetch prospective remailers from reliable's remailer-conf reply:
	my @lines = split /\r?\n/, $conf;

	while (1) {
		my $head;
		while (@lines) {
			$head = $lines[0];
			chomp $head;
			shift @lines;
			last if ($head eq 'SUPPORTED CPUNK (TYPE I) REMAILERS' ||
				 $head eq 'SUPPORTED MIXMASTER (TYPE II) REMAILERS');
		};
		last unless defined $head;
		my $wanting = $head eq 'SUPPORTED CPUNK (TYPE I) REMAILERS' ? 1 :
		              $head eq 'SUPPORTED MIXMASTER (TYPE II) REMAILERS' ? 2 :
		              undef;
		last unless defined $wanting;

		while (@lines) {
			$head = $lines[0];
			chomp $head;
			shift @lines;
			if ($wanting == 1) {
				last unless ($head =~ /<(.*?@.*?)>/);
				Echolot::Globals::get()->{'storage'}->add_prospective_address($1, 'reliable-caps-reply-type1', $remailer_address);
			} elsif ($wanting == 2) {
				last unless ($head =~ /\s(.*?@.*?)\s/);
				Echolot::Globals::get()->{'storage'}->add_prospective_address($1, 'reliable-caps-reply-type2', $remailer_address);
			} else {
				Echolot::Log::confess("Shouldn't be here. wanting == $wanting.");
			};
		};
	};

	return 1;
};

sub remailer_conf($$$) {
	my ($reply, $token, $time) = @_;

	my ($id) = $token =~ /^conf\.(\d+)$/;
	(defined $id) or
		Echolot::Log::info ("Returned token '$token' has no id at all."),
		return 0;

	my $remailer = Echolot::Globals::get()->{'storage'}->get_address_by_id($id);
	Echolot::Log::info("No remailer found for id '$id'."), return 0 unless defined $remailer;
	Echolot::Log::debug("Received remailer-conf reply for $remailer."),

	Echolot::Globals::get()->{'storage'}->not_a_remailer($id), return 1
		if (is_not_a_remailer($reply));
	Echolot::Thesaurus::save_thesaurus('conf', $id, $reply);


	remailer_caps($reply, $token, $time);
};

sub set_caps_manually($$) {
	my ($addr, $caps) = @_;

	defined $addr or
		Echolot::Log::info("Address not defined."),
		return 0;
	defined $caps or
		Echolot::Log::info("Caps not defined."),
		return 0;

	Echolot::Log::info("Setting caps for $addr manually to $caps.");

	my $remailer = Echolot::Globals::get()->{'storage'}->get_address($addr);
	defined $remailer or
		Echolot::Log::info("Remailer address $addr did not give a valid remailer."),
		return 0;
	my $id = $remailer->{'id'};
	defined $id or
		Echolot::Log::info("Remailer address $addr did not give a remailer with an id."),
		return 0;
	my $token = 'conf.'.$id;

	my $conf = "Remailer-Type: set-manually\n$caps";
	remailer_caps($conf, $token, time, 1);

	return 1;
};

sub parse_mix_key($$$) {
	my ($reply, $time, $remailer) = @_;

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
	my @mix_confs = ($reply =~ /^
		[a-z0-9]+
		\s+
		\S+\@\S+
		\s+
		[0-9a-f]{32}
		.*?$/xmg);
	my @mix_keys = ($reply =~ /^-----Begin \s Mix \s Key-----\r?\n
	                          [0-9a-f]{32}\r?\n
							  \d+\r?\n
							  (?:[a-zA-Z0-9+\/]*\r?\n)+
							  -----End \s Mix \s Key-----$/xmg );
	for (@mix_confs) {
		my ($nick, $address, $keyid, $version, $caps, $created, $expires) = /^
			([a-z0-9]+)
			\s+
			(\S+@\S+)
			\s+
			([0-9a-f]{32})
			(?: [ \t]+
			   (\S+)
			   (?: [ \t]+
			      (\S+)
			      (?: [ \t]+
			         (\d{4}-\d{2}-\d{2})
			         (?: [ \t]+
			            (\d{4}-\d{2}-\d{2})
			         )?
			      )?
			   )?
			)? .*?/x;
		$mixmasters{$keyid} = {
			nick	=> $nick,
			address => $address,
			version => $version,
			caps    => $caps,
			created => $created,
			expires => $expires,
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
		(defined $mixmasters{$keyid}->{'nick'}) or
			Echolot::Log::info("Could not parse a remailer-key reply."),
			next;
		(defined $mixmasters{$keyid}->{'nick'} && ! defined $mixmasters{$keyid}->{'key'}) and
			Echolot::Log::info("Mixmaster key header without key in reply from $remailer_address."),
			next;
		(! defined $mixmasters{$keyid}->{'nick'} && defined $mixmasters{$keyid}->{'key'}) and
			Echolot::Log::info("Mixmaster key without key header in reply from $remailer_address."),
			next;
		my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday) = gmtime();
		my $today = sprintf("%04d-%02d-%02d", $year+1900, $mon+1, $mday);
		(defined $mixmasters{$keyid}->{'created'} && ($today lt $mixmasters{$keyid}->{'created'})) and
			Echolot::Log::info("Mixmaster key for $remailer_address created in the future ($today < ".$mixmasters{$keyid}->{'created'}.")."),
			next;
		(defined $mixmasters{$keyid}->{'expires'} && ($mixmasters{$keyid}->{'expires'} lt $today)) and
			Echolot::Log::info("Mixmaster key for $remailer_address expired (".$mixmasters{$keyid}->{'expires'}." < $today)."),
			next;

		if ($remailer->{'address'} ne $remailer_address) {
			# Address mismatch -> Ignore reply and add $remailer_address to prospective addresses
			Echolot::Log::info("Remailer address mismatch $remailer->{'address'} vs $remailer_address. Adding latter to prospective remailers.");
			Echolot::Globals::get()->{'storage'}->add_prospective_address($remailer_address, 'self-capsstring-key', $remailer_address);
		} else {
			Echolot::Log::debug("Setting mix key for $remailer_address: $keyid");
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

sub parse_cpunk_key($$$) {
	my ($reply, $time, $remailer) = @_;

	my $GnuPG = new GnuPG::Interface;
	$GnuPG->call( Echolot::Config::get()->{'gnupg'} ) if (Echolot::Config::get()->{'gnupg'});
	$GnuPG->options->hash_init(
		homedir => Echolot::Config::get()->{'gnupghome'} );
	$GnuPG->options->meta_interactive( 0 );
	my %cypherpunk;

	my @pgp_keys = ($reply =~ /^-----BEGIN \s PGP \s PUBLIC \s KEY \s BLOCK-----\r?\n
	                          (?:.+\r?\n)*
	                          \r?\n
	                          (?:[a-zA-Z0-9+\/=]*\r?\n)+
	                          -----END \s PGP \s PUBLIC \s KEY \s BLOCK-----$/xmg );
	for my $key (@pgp_keys) {
		my ( $stdin_fh, $stdout_fh, $stderr_fh, $status_fh, $handles ) = Echolot::Tools::make_gpg_fds();
		my $pid = $GnuPG->wrap_call(
			commands     => [qw{--with-colons}],
			command_args => [qw{--no-options --no-secmem-warning --no-default-keyring --fast-list-mode}],
			handles      => $handles );
		my ($stdout, $stderr, $status) = Echolot::Tools::readwrite_gpg($key, $stdin_fh, $stdout_fh, $stderr_fh, $status_fh);
		waitpid $pid, 0;

		($stderr eq '') or 
			Echolot::Log::info("GnuPG returned something in stderr: '$stderr' when checking key '$key'; So what?");
		($status eq '') or 
			Echolot::Log::info("GnuPG returned something in status '$status' when checking key '$key': So what?");
		
		my @included_keys = $stdout =~ /^pub:.*$/mg;
		(scalar @included_keys >= 2) &&
			# FIXME handle more than one key per block nicely
			Echolot::Log::debug ("Cannot handle more than one key per block nicely (correctly) yet. Found ".(scalar @included_keys)." in one block from ".$remailer->{'address'}.".");
		for my $included_key (@included_keys) {
			my ($type, $keyid, $uid) = $included_key =~ /pub::\d+:(\d+):([0-9A-F]+):[^:]+:[^:]*:::([^:]+):/;
			(defined $uid) or
				Echolot::Log::info ("Unexpected format of '$included_key' by ".$remailer->{'address'}."; Skipping."),
				next;
			my ($address) = $uid =~ /<(.*?)>/;
			$cypherpunk{$keyid} = {
				address => $address,
				type => $type,
				key => $key       # FIXME handle more than one key per block correctly
			};
		};
	};

	for my $keyid (keys %cypherpunk) {
		my $remailer_address = $cypherpunk{$keyid}->{'address'};

		if ($remailer->{'address'} ne $remailer_address) {
			# Address mismatch -> Ignore reply and add $remailer_address to prospective addresses
			Echolot::Log::info("Remailer address mismatch $remailer->{'address'} vs $remailer_address id key $keyid. Adding latter to prospective remailers.");
			Echolot::Globals::get()->{'storage'}->add_prospective_address($remailer_address, 'self-capsstring-key', $remailer_address);
		} else {
			Echolot::Globals::get()->{'storage'}->restore_ttl( $remailer->{'address'} );
			# 1 .. RSA
			# 17 .. DSA
			if ($cypherpunk{$keyid}->{'type'} == 1 || $cypherpunk{$keyid}->{'type'} == 17 ) {
				Echolot::Log::debug("Setting cpunk key for $remailer_address: $keyid; type ".$cypherpunk{$keyid}->{'type'});
				Echolot::Globals::get()->{'storage'}->set_key(
					(($cypherpunk{$keyid}->{'type'} == 1) ? 'cpunk-rsa' :
					 (($cypherpunk{$keyid}->{'type'} == 17) ? 'cpunk-dsa' :
					  'ERROR')),
					$keyid, # as nick
					$cypherpunk{$keyid}->{'address'},
					$cypherpunk{$keyid}->{'key'},
					$keyid,
					'N/A',
					'N/A',
					'N/A',
					$time);
			} else {
				Echolot::Log::info("$keyid from $remailer_address has algoid ".$cypherpunk{$keyid}->{'type'}.". Cannot handle those.");
			};
		}
	};

	return 1;
};

sub remailer_key($$$) {
	my ($reply, $token, $time) = @_;

	my $cp_reply = $reply;
	$cp_reply =~ s/^- -/-/gm; # PGP Signed messages

	my ($id) = $token =~ /^key\.(\d+)$/;
	(defined $id) or
		Echolot::Log::info ("Returned token '$token' has no id at all."),
		return 0;

	my $remailer = Echolot::Globals::get()->{'storage'}->get_address_by_id($id);
	Echolot::Log::info("No remailer found for id '$id'."), return 0 unless defined $remailer;
	Echolot::Log::debug("Received remailer-keys reply for $remailer."),

	Echolot::Globals::get()->{'storage'}->not_a_remailer($id), return 1
		if (is_not_a_remailer($reply));
	Echolot::Thesaurus::save_thesaurus('key', $id, $reply);

	parse_mix_key($cp_reply, $time, $remailer);
	parse_cpunk_key($cp_reply, $time, $remailer);

	return 1;
};

sub remailer_stats($$$) {
	my ($reply, $token, $time) = @_;

	my ($id) = $token =~ /^stats\.(\d+)$/;
	(defined $id) or
		Echolot::Log::info ("Returned token '$token' has no id at all."),
		return 0;


	my $remailer = Echolot::Globals::get()->{'storage'}->get_address_by_id($id);
	Echolot::Log::info("No remailer found for id '$id'."), return 0 unless defined $remailer;
	Echolot::Log::debug("Received remailer-stats reply for $remailer."),

	Echolot::Globals::get()->{'storage'}->not_a_remailer($id), return 1
		if (is_not_a_remailer($reply));
	Echolot::Thesaurus::save_thesaurus('stats', $id, $reply);
};

sub remailer_help($$$) {
	my ($reply, $token, $time) = @_;

	my ($id) = $token =~ /^help\.(\d+)$/;
	(defined $id) or
		Echolot::Log::info ("Returned token '$token' has no id at all."),
		return 0;

	my $remailer = Echolot::Globals::get()->{'storage'}->get_address_by_id($id);
	Echolot::Log::info("No remailer found for id '$id'."), return 0 unless defined $remailer;
	Echolot::Log::debug("Received remailer-help reply for $remailer."),

	Echolot::Globals::get()->{'storage'}->not_a_remailer($id), return 1
		if (is_not_a_remailer($reply));
	Echolot::Thesaurus::save_thesaurus('help', $id, $reply);
};

sub remailer_adminkey($$$) {
	my ($reply, $token, $time) = @_;

	my ($id) = $token =~ /^adminkey\.(\d+)$/;
	(defined $id) or
		Echolot::Log::info ("Returned token '$token' has no id at all."),
		return 0;

	my $remailer = Echolot::Globals::get()->{'storage'}->get_address_by_id($id);
	Echolot::Log::info("No remailer found for id '$id'."), return 0 unless defined $remailer;
	Echolot::Log::debug("Received remailer-adminkey reply for $remailer."),

	Echolot::Globals::get()->{'storage'}->not_a_remailer($id), return 1
		if (is_not_a_remailer($reply));
	Echolot::Thesaurus::save_thesaurus('adminkey', $id, $reply);
};

1;
# vim: set ts=4 shiftwidth=4:
