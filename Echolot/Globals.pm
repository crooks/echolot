package Echolot::Globals;

# (c) 2002 Peter Palfrader <peter@palfrader.org>
# $Id: Globals.pm,v 1.2 2002/06/20 04:27:37 weasel Exp $
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
	$GLOBALS->{'internalcounter'} = 1;
};

sub initStorage {
	$GLOBALS->{'storage'}   = new Echolot::Storage::File ( datadir => Echolot::Config::get()->{'storage'}->{'File'}->{'basedir'} );
};

sub get() {
	return $GLOBALS;
};

1;
# vim: set ts=4 shiftwidth=4:
