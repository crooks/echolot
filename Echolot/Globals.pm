package Echolot::Globals;

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

Echolot::Globals - echolot global variables

=head1 DESCRIPTION

=cut

use strict;
use Carp;

my $GLOBALS;

sub init(%) {
	my (%args) = @_;

	my $hostname = `hostname`;
	$hostname =~ /^([a-zA-Z0-9_.-]*)$/;
	$hostname = $1 || 'unknown';
	$GLOBALS->{'hostname'} = $hostname;
	$GLOBALS->{'internalcounter'} = 1;
	$GLOBALS->{'version'} = $args{'version'};
};

sub initStorage {
	$GLOBALS->{'storage'}   = new Echolot::Storage::File ( datadir => Echolot::Config::get()->{'storage'}->{'File'}->{'basedir'} );
};

sub get() {
	return $GLOBALS;
};

1;
# vim: set ts=4 shiftwidth=4:
