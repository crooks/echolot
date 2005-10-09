package Echolot::Report;

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

Echolot::Report - Summarize status of remailers

=head1 DESCRIPTION

This package prints the summary of remailers/addresses.

=cut

use strict;
use English;
use Echolot::Log;

sub print_summary(;$) {
	my ($manual) = @_;

	my @addresses = sort { $a->{'address'} cmp $b->{'address'} } Echolot::Globals::get()->{'storage'}->get_addresses();
	my $report = "*** Status summary ***\n";

	for my $remailer (@addresses) {
		my $addr = $remailer->{'address'};
		$report .= "$addr (ID: $remailer->{'id'}): ".uc($remailer->{'status'})."; ".
			"Fetch/Ping/Show: ".
			($remailer->{'fetch'} ? '1' : '0') .
			($remailer->{'pingit'} ? '1' : '0') .
			($remailer->{'showit'} ? '1' : '0') .
			"; TTL: $remailer->{'ttl'}\n";
		$report .= "  Resurection TTL: $remailer->{'resurrection_ttl'}\n" if (defined $remailer->{'resurrection_ttl'} && ($remailer->{'status'} eq 'ttl timeout'));
		for my $type (Echolot::Globals::get()->{'storage'}->get_types($addr)) {
			$report .= "  Type: $type: ".join(', ', Echolot::Globals::get()->{'storage'}->get_keys($addr, $type))."\n";
		};
	};
	if (defined $manual) {
		Echolot::Log::notice($report);
	} else {
		Echolot::Log::info($report);
	}

	return 1;
};

1;
# vim: set ts=4 shiftwidth=4:
