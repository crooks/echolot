package Echolot::Globals;

# (c) 2002 Peter Palfrader <peter@palfrader.org>
# $Id: Globals.pm,v 1.1 2002/06/05 04:05:40 weasel Exp $
#

=pod

=head1 Name

Echolot::Globals - echolot global variables

=head1 DESCRIPTION

=cut

use strict;
use warnings;
use Carp;

my $GLOBALS;

sub init {
	my $hostname = `hostname`;
	$hostname =~ /^([a-zA-Z0-9_-]*)$/;
	$hostname = $1 || 'unknown';
	$GLOBALS->{'hostname'} = $hostname;
	$GLOBALS->{'storage'}   = new Echolot::Storage::File ( datadir => Echolot::Config::get()->{'storage'}->{'File'}->{'basedir'} );
	$GLOBALS->{'internalcounter'} = 1;
};

sub get() {
	return $GLOBALS;
};

1;
# vim: set ts=4 shiftwidth=4:
