package Echolot::Fromlines;

# (c) 2002 Peter Palfrader <peter@palfrader.org>
# $Id: Fromlines.pm,v 1.4 2003/02/21 06:37:35 weasel Exp $
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
		next unless $remailer->{'showit'};
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
				my $disclaim_top = $from_info->{'disclaim_top'} ? 1 : 0;
				my $disclaim_bot = $from_info->{'disclaim_bot'} ? 1 : 0;
				my $frominfo = $disclaim_top.':'.$disclaim_bot.':'.$from;
				push @{$from_types->{$frominfo}}, $type;
			};
			my $types_from;
			for my $frominfo (sort keys %$from_types) {
				my $types = join ", ", sort { $a cmp $b } @{$from_types->{$frominfo}};
				$types_from->{$types} = $frominfo;
			};
			my @types_from = map {
					my ($disclaim_top, $disclaim_bot, $from) = split (/:/, $types_from->{$_}, 3);
					{
						nick => $nick,
						address => $addr,
						types => $_,
						disclaim_top => $disclaim_top,
						disclaim_bot => $disclaim_bot,
						from => Echolot::Tools::escape_HTML_entities($from)
					}
				} sort { $a cmp $b } keys %$types_from;
			$data->{$user_supplied}->{$addr}->{'data'} = \@types_from;
		};

		# Remove user supplied if identical
		my $f0 = join ':', map {
				$_->{'disclaim_top'}.':'.$_->{'disclaim_bot'}.$_->{'types'}.':'.$_->{'from'}
			}  @{$data->{0}->{$addr}->{'data'}};
		my $f1 = join ':', map {
				$_->{'disclaim_top'}.':'.$_->{'disclaim_bot'}.$_->{'types'}.':'.$_->{'from'}
			}  @{$data->{1}->{$addr}->{'data'}};
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
