package Echolot::Fromlines;

# (c) 2002 Peter Palfrader <peter@palfrader.org>
# $Id: Fromlines.pm,v 1.2 2003/02/18 06:57:07 weasel Exp $
#

=pod

=head1 Name

Echolot::Thesaurus - build from header page

=head1 DESCRIPTION

This package builds the from header page with the information we
received from pings.

=cut

use strict;
use English;
use Echolot::Log;


sub build_fromlines() {
	return 1 unless Echolot::Config::get()->{'fromlines'};

	my $data;
	my @remailers = Echolot::Globals::get()->{'storage'}->get_remailers();

	for my $remailer (@remailers) {
		my $addr = $remailer->{'address'};
		my $nick = Echolot::Globals::get()->{'storage'}->get_nick($addr);
		next unless defined $nick;
		my $caps = Echolot::Globals::get()->{'storage'}->get_capabilities($addr);
		my $middleman = $caps =~ m/\bmiddle\b/;


		for my $user_supplied (0, 1) {
			$data->{$user_supplied}->{$addr}->{'nick'} = $nick;
			$data->{$user_supplied}->{$addr}->{'address'} = $addr;
			
			my @types = Echolot::Globals::get()->{'storage'}->get_types($addr);
			my $from_types;
			for my $type (@types) {
				my $from_info =  Echolot::Globals::get()->{'storage'}->get_fromline($addr, $type, $user_supplied);
				my $from = $from_info->{'from'};
				$from = 'Not Available' unless defined $from;
				$from = 'Middleman Remailer' if $middleman;
				push @{$from_types->{$from}}, $type;
			};
			my $types_from;
			for my $from (sort keys %$from_types) {
				my $types = join ", ", sort { $a cmp $b } @{$from_types->{$from}};
				$types_from->{$types} = $from;
			};
			my @types_from = map {
					{
						nick => $nick,
						address => $addr,
						types => $_,
						from => Echolot::Tools::escape_HTML_entities($types_from->{$_})
					}
				} sort { $a cmp $b } keys %$types_from;
			$data->{$user_supplied}->{$addr}->{'data'} = \@types_from;
		};

		# Remove user supplied if identical
		my $f0 = join ':', map { $_->{'types'} .':'.$_->{'from'}}  @{$data->{0}->{$addr}->{'data'}};
		my $f1 = join ':', map { $_->{'types'} .':'.$_->{'from'}}  @{$data->{1}->{$addr}->{'data'}};
		if ($f0 eq $f1) {
			delete $data->{1}->{$addr};
		};
	};

	my @data0 = map {$data->{0}->{$_}} (sort { $data->{0}->{$a}->{'nick'} cmp $data->{0}->{$b}->{'nick'} } keys (%{$data->{0}}));
	my @data1 = map {$data->{1}->{$_}} (sort { $data->{1}->{$a}->{'nick'} cmp $data->{1}->{$b}->{'nick'} } keys (%{$data->{1}}));

	Echolot::Tools::write_HTML_file(
		Echolot::Config::get()->{'fromlinesindexfile'},
		'fromlinesindexfile',
		Echolot::Config::get()->{'buildfromlines'},
		default => \@data0,
		usersupplied => \@data1);
};


1;
# vim: set ts=4 shiftwidth=4:
