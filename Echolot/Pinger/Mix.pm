package Echolot::Pinger::Mix;

# (c) 2002 Peter Palfrader <peter@palfrader.org>
# $Id: Mix.pm,v 1.1 2002/06/11 09:53:35 weasel Exp $
#

=pod

=head1 Name

Echolot::Pinger::Mix - send mix pings

=head1 DESCRIPTION

This package provides functions for sending mixmaster (type II) pings.

=cut

use strict;
use warnings;
use Carp qw{cluck};
use English;

sub ping($$$$) {
	my ($body, $to, $chain, $keys) = @_;

	my $keyring = Echolot::Config::get()->{'Pinger::Mix'}->{'mixdir'}.'/pubring.mix';
	open (F, '>'.$keyring) or
		cluck("Cannot open $keyring for writing: $!"),
		return 0;
	for my $keyid (keys %$keys) {
		print (F $keys->{$keyid}->{'summary'}, "\n\n");
		print (F $keys->{$keyid}->{'key'},"\n\n");
	};
	close (F) or
		cluck("Cannot close $keyring"),
		return 0;
	
	open(MIX, "|".Echolot::Config::get()->{'Pinger::Mix'}->{'mix'}." -m -S -l $chain") or
		cluck("Cannot exec mixpinger: $!"),
		return 0;
	print MIX "To: $to\n\n$body";
	close (MIX);
	    
	return 1;
};

1;
# vim: set ts=4 shiftwidth=4:
