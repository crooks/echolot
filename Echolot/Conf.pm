package Echolot::Conf;

# (c) 2002 Peter Palfrader <peter@palfrader.org>
# $Id: Conf.pm,v 1.1 2002/06/05 04:05:40 weasel Exp $
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
	cluck("Could not find id in token '$token'"), return 0 unless defined $id;
	my ($remailer_type) = ($conf =~ /^\s*Remailer-Type:\s* (.*?) \s*$/imx);
	cluck("No remailer type found in remailer_conf from '$token'"), return 0 unless defined $remailer_type;
	my ($remailer_caps) = ($conf =~ /^\s*(  \$remailer{".*"}  \s*=\s*  "<.*@.*>.*";   )\s*$/imx);
	cluck("No remailer caps found in remailer_conf from '$token'"), return 0 unless defined $remailer_caps;
	my ($remailer_nick, $remailer_address) = ($remailer_caps =~ /^\s*  \$remailer{"(.*)"}  \s*=\s*  "<(.*@.*)>.*";   \s*$/ix);
	cluck("No remailer nick found in remailer_caps from '$token': '$remailer_caps'"), return 0 unless defined $remailer_nick;
	cluck("No remailer address found in remailer_caps from '$token': '$remailer_caps'"), return 0 unless defined $remailer_address;
	

	my $remailer = Echolot::Globals::get()->{'storage'}->get_address_by_id($id);
	if ($remailer->{'address'} ne $remailer_address) {
		# Address mismatch -> Ignore reply and add $remailer_address to prospective addresses
		cluck("Remailer address mismatch $remailer->{'address'} vs $remailer_address. Adding latter to prospective remailers.");
		Echolot::Globals::get()->{'storage'}->add_prospective_address($remailer_address, 'conf-reply');
	} else {
		Echolot::Globals::get()->{'storage'}->restore_ttl( $remailer->{'address'} );
		Echolot::Globals::get()->{'storage'}->set_caps($remailer_type, $remailer_caps, $remailer_nick, $remailer_address, $time);
	}
};

sub remailer_key($$$) {
	my ($conf, $token, $time) = @_;

	print "Remailer key\n";
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
