package Echolot::Thesaurus;

# (c) 2002 Peter Palfrader <peter@palfrader.org>
# $Id: Thesaurus.pm,v 1.1 2002/07/06 00:50:27 weasel Exp $
#

=pod

=head1 Name

Echolot::Thesaurus - build thesaurus pages

=head1 DESCRIPTION

This package provides necessary functions for the thesaurus.

=cut

use strict;
use warnings;
use Carp qw{cluck};
use English;


sub build_thesaurus() {
	return 1 unless Echolot::Config::get()->{'thesaurus'};

	my $dir = Echolot::Config::get()->{'thesaurusdir'};
	opendir(DIR, $dir) or 
		cluck ("Cannot open '$dir': $!"),
		return 0;
	my @files = grep { ! /^\./ } readdir(DIR);
	closedir(DIR);

	my $data;
	for my $filename (@files) {
	    my ($id, $what) = $filename =~ /^(\d+)-(adminkey|conf|help|key|stats)$/;
		next unless (defined $id && defined $what);

	    my $remailer = Echolot::Globals::get()->{'storage'}->get_address_by_id($id);
		next return 0 unless defined $remailer;
		
		my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
			$atime,$mtime,$ctime,$blksize,$blocks)
			= stat($dir.'/'.$filename);

		my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday)
			= gmtime($mtime);

		my $date = sprintf("%04d-%02d-%02d %02d:%02d",
			$year+1900, $mon+1, $mday,
			$hour, $min);


		$data->{$remailer->{'address'}}->{$what} = {
			'href' => $filename,
			'date' => $date,
		};
	};


	for my $addr (keys (%$data)) {
		my $nick = Echolot::Globals::get()->{'storage'}->get_nick($addr);
		$data->{$addr}->{'nick'} = defined $nick ? $nick : 'N/A';
	};

	my $file = Echolot::Config::get()->{'thesaurusindexfile'};
	open (F, ">$file") or
		cluck ("Cannot open '$file': $!"),
		return 0;
	print F '<html><head><title>Thesaurus</title></head><body><h1>Thesaurus</h1><table border=1>'."\n";
	print F "<tr><tr><th>nick</th><th>Address</th><th>conf</th><th>help</th><th>key</th><th>stats</th><th>adminkey</th></tr>\n";

	for my $addr (sort { $data->{$a}->{'nick'} cmp $data->{$b}->{'nick'} } keys (%$data)) {
		printf F "<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>\n",
			$data->{$addr}->{'nick'},
			$addr,
			defined ($data->{$addr}->{'conf'}) ?
				sprintf('<a href="%s">%s</a>', $data->{$addr}->{'conf'}->{'href'}, $data->{$addr}->{'conf'}->{'date'}) : 'N/A',
			defined ($data->{$addr}->{'help'}) ?
				sprintf('<a href="%s">%s</a>', $data->{$addr}->{'help'}->{'href'}, $data->{$addr}->{'help'}->{'date'}) : 'N/A',
			defined ($data->{$addr}->{'key'}) ?
				sprintf('<a href="%s">%s</a>', $data->{$addr}->{'key'}->{'href'}, $data->{$addr}->{'key'}->{'date'}) : 'N/A',
			defined ($data->{$addr}->{'stats'}) ?
				sprintf('<a href="%s">%s</a>', $data->{$addr}->{'stats'}->{'href'}, $data->{$addr}->{'stats'}->{'date'}) : 'N/A',
			defined ($data->{$addr}->{'adminkey'}) ?
				sprintf('<a href="%s">%s</a>', $data->{$addr}->{'adminkey'}->{'href'}, $data->{$addr}->{'adminkey'}->{'date'}) : 'N/A';
	};
	print F '</table></body>';
	close (F);
};

1;
# vim: set ts=4 shiftwidth=4:
