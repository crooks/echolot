package Echolot::Pinger::Mix;

# (c) 2002 Peter Palfrader <peter@palfrader.org>
# $Id: Mix.pm,v 1.5 2002/07/22 02:18:30 weasel Exp $
#

=pod

=head1 Name

Echolot::Pinger::Mix - send mix pings

=head1 DESCRIPTION

This package provides functions for sending mixmaster (type II) pings.

=cut

use strict;
use Carp qw{cluck};
use English;

sub ping($$$$) {
	my ($body, $to, $chain, $keys) = @_;

	my $chaincomma = join (',', @$chain);

	my $keyring = Echolot::Config::get()->{'mixhome'}.'/pubring.mix';
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

	my $type2list = Echolot::Config::get()->{'mixhome'}.'/type2.list';
	open (F, '>'.$type2list) or
		cluck("Cannot open $type2list for writing: $!"),
		return 0;
	for my $keyid (keys %$keys) {
		print (F $keys->{$keyid}->{'summary'}, "\n");
	};
	close (F) or
		cluck("Cannot close $type2list"),
		return 0;
	
	$ENV{'MIXPATH'} = Echolot::Config::get()->{'mixhome'};
	open(MIX, "|".Echolot::Config::get()->{'mixmaster'}." -m -S -l $chaincomma") or
		cluck("Cannot exec mixpinger: $!"),
		return 0;
	print MIX "To: $to\n\n$body\n";
	close (MIX);
	    
	return 1;
};

1;
# vim: set ts=4 shiftwidth=4:
