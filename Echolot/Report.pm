package Echolot::Report;

# (c) 2002 Peter Palfrader <peter@palfrader.org>
# $Id: Report.pm,v 1.1 2003/02/20 19:39:03 weasel Exp $
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

sub print_summary() {

	my @addresses = sort { $a->{'address'} cmp $b->{'address'} } Echolot::Globals::get()->{'storage'}->get_addresses();
	my %remailers = map { $_->{'address'} => $_ } Echolot::Globals::get()->{'storage'}->get_remailers();
	my $report = "*** Status summary ***\n";

	for my $remailer (@addresses) {
		my $addr = $remailer->{'address'};
		$report .= "$addr (ID: $remailer->{'id'}): ".uc($remailer->{'status'})."; Fetch/Ping/Show: $remailer->{'fetch'}$remailer->{'pingit'}$remailer->{'showit'}; TTL: $remailer->{'ttl'}\n";
		$report .= "  Resurection TTL: $remailer->{'resurrection_ttl'}\n" if (defined $remailer->{'resurrection_ttl'} && ($remailer->{'status'} eq 'ttl timeout'));
		if (defined $remailers{$addr}) {
			$report .= "  $remailers{$addr}->{'status'}\n";
			for my $type (Echolot::Globals::get()->{'storage'}->get_types($addr)) {
				$report .= "  Type: $type: ".join(', ', Echolot::Globals::get()->{'storage'}->get_keys($addr, $type))."\n";
			};
		};
	};
	Echolot::Log::info($report);

	return 1;
};

1;
# vim: set ts=4 shiftwidth=4:
