package Echolot::Thesaurus;

# (c) 2002 Peter Palfrader <peter@palfrader.org>
# $Id: Thesaurus.pm,v 1.4 2002/07/07 00:42:46 weasel Exp $
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
use HTML::Template;


sub build_thesaurus() {
	return 1 unless Echolot::Config::get()->{'thesaurus'};

	my $dir = Echolot::Config::get()->{'thesaurusdir'};
	opendir(DIR, $dir) or 
		cluck ("Cannot open '$dir': $!"),
		return 0;
	my @files = grep { ! /^\./ } readdir(DIR);
	closedir(DIR);


	my $exire_date = time() - Echolot::Config::get()->{'expire_thesaurus'};

	my $data;
	for my $filename (@files) {
	    my ($id, $what) = $filename =~ /^(\d+)-(adminkey|conf|help|key|stats)$/;
		next unless (defined $id && defined $what);

	    my $remailer = Echolot::Globals::get()->{'storage'}->get_address_by_id($id);
		next return 0 unless defined $remailer;
		
		my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
			$atime,$mtime,$ctime,$blksize,$blocks)
			= stat($dir.'/'.$filename);

		if ($mtime < $expire_date) {
			unlink ($filename) or
				cluck("Cannot unlink expired $filename");
			print ("Expired thesaurus file $filename\n") if
				Echolot::Config::get()->{'verbose'};
			next;
		};

		my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday)
			= gmtime($mtime);

		my $date = sprintf("%04d-%02d-%02d", $year+1900, $mon+1, $mday);
		my $time = sprintf("%02d:%02d", $hour, $min);


		$data->{$remailer->{'address'}}->{$what.'_href'} = $filename;
		$data->{$remailer->{'address'}}->{$what.'_date'} = $date;
		$data->{$remailer->{'address'}}->{$what.'_time'} = $time;
	};


	for my $addr (keys (%$data)) {
		my $nick = Echolot::Globals::get()->{'storage'}->get_nick($addr);
		$data->{$addr}->{'nick'} = defined $nick ? $nick : 'N/A';
		$data->{$addr}->{'address'} = $addr;
	};

	my @data = map {$data->{$_}} (sort { $data->{$a}->{'nick'} cmp $data->{$b}->{'nick'} } keys (%$data));

	my $template =  HTML::Template->new(
		filename => Echolot::Config::get()->{'templates'}->{'thesaurusindexfile'},
		global_vars => 1 );
	$template->param ( remailers => \@data );
	$template->param ( CURRENT_TIMESTAMP => scalar gmtime() );
	$template->param ( SITE_NAME => Echolot::Config::get()->{'sitename'} );
	

	my $file = Echolot::Config::get()->{'thesaurusindexfile'};
	open (F, ">$file") or
		cluck ("Cannot open '$file': $!"),
		return 0;
	print F $template->output();
	close F;

	return;

	print F '<html><head><title>Thesaurus</title></head><body><h1>Thesaurus</h1><table border=1>'."\n";
	print F "<tr><tr><th>nick</th><th>Address</th><th>conf</th><th>help</th><th>key</th><th>stats</th><th>adminkey</th></tr>\n";

	for my $addr (sort { $data->{$a}->{'nick'} cmp $data->{$b}->{'nick'} } keys (%$data)) {
		printf F '<tr><td>%s</td><td>%s</td><td align="center">%s</td><td align="center">%s</td><td align="center">%s</td><td align="center">%s</td><td align="center">%s</td></tr>'."\n",
			$data->{$addr}->{'nick'},
			$addr,
			defined ($data->{$addr}->{'conf'}) ?
				sprintf('<a href="%s">%s<br>%s</a>', $data->{$addr}->{'conf'}->{'href'}, $data->{$addr}->{'conf'}->{'date'},
				                                                                         $data->{$addr}->{'conf'}->{'time'}) : 'N/A',
			defined ($data->{$addr}->{'help'}) ?
				sprintf('<a href="%s">%s<br>%s</a>', $data->{$addr}->{'help'}->{'href'}, $data->{$addr}->{'help'}->{'date'},
				                                                                         $data->{$addr}->{'help'}->{'time'}) : 'N/A',
			defined ($data->{$addr}->{'key'}) ?
				sprintf('<a href="%s">%s<br>%s</a>', $data->{$addr}->{'key'}->{'href'}, $data->{$addr}->{'key'}->{'date'},
				                                                                        $data->{$addr}->{'key'}->{'time'}) : 'N/A',
			defined ($data->{$addr}->{'stats'}) ?
				sprintf('<a href="%s">%s<br>%s</a>', $data->{$addr}->{'stats'}->{'href'}, $data->{$addr}->{'stats'}->{'date'},
				                                                                          $data->{$addr}->{'stats'}->{'time'}) : 'N/A',
			defined ($data->{$addr}->{'adminkey'}) ?
				sprintf('<a href="%s">%s<br>%s</a>', $data->{$addr}->{'adminkey'}->{'href'}, $data->{$addr}->{'adminkey'}->{'date'},
				                                                                             $data->{$addr}->{'adminkey'}->{'time'}) : 'N/A',
	};
	print F '</table></body>';
	close (F);
};


1;
# vim: set ts=4 shiftwidth=4:
