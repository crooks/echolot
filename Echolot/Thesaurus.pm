package Echolot::Thesaurus;

# (c) 2002 Peter Palfrader <peter@palfrader.org>
# $Id: Thesaurus.pm,v 1.12 2002/09/05 15:41:38 weasel Exp $
#

=pod

=head1 Name

Echolot::Thesaurus - build thesaurus pages

=head1 DESCRIPTION

This package provides necessary functions for the thesaurus.

=cut

use strict;
use Carp qw{cluck};
use English;


sub save_thesaurus($$$) {
	my ($otype, $oid, $data) = @_;

	return 1 unless Echolot::Config::get()->{'thesaurus'};

	my ($type) = $otype =~ /^([a-z-]+)$/;
	cluck("type '$otype' is not clean in save_thesaurus"), return 0 unless defined $type;
	my ($id) = $oid =~ /^([0-9]+)$/;
	cluck("id '$oid' is not clean in save_thesaurus"), return 0 unless defined $id;

	my $file = Echolot::Config::get()->{'thesaurusdir'}.'/'.$id.'.'.$type;
	open (F, ">$file") or
		cluck ("Cannot open '$file': $!"),
		return 0;
	print F $data;
	close (F);

	return 1;
};

sub build_thesaurus() {
	return 1 unless Echolot::Config::get()->{'thesaurus'};

	my $dir = Echolot::Config::get()->{'thesaurusdir'};
	opendir(DIR, $dir) or 
		cluck ("Cannot open '$dir': $!"),
		return 0;
	my @files = grep { ! /^\./ } readdir(DIR);
	closedir(DIR);


	my $expire_date = time() - Echolot::Config::get()->{'expire_thesaurus'};

	my $data;
	for my $filename (@files) {
	    my ($id, $what) = $filename =~ /^(\d+)\.(adminkey|conf|help|key|stats)$/;
		next unless (defined $id && defined $what);

		my $remailer = Echolot::Globals::get()->{'storage'}->get_address_by_id($id);
		next unless defined $remailer;
		next unless $remailer->{'showit'};
		
		my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
			$atime,$mtime,$ctime,$blksize,$blocks)
			= stat($dir.'/'.$filename);

		if ($mtime < $expire_date) {
			unlink ($dir.'/'.$filename) or
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
		if (defined $nick) {
			$data->{$addr}->{'nick'} = $nick;
			$data->{$addr}->{'address'} = $addr;
		} else {
			delete $data->{$addr};
		};
	};

	my @data = map {$data->{$_}} (sort { $data->{$a}->{'nick'} cmp $data->{$b}->{'nick'} } keys (%$data));


	Echolot::Tools::write_HTML_file(
		Echolot::Config::get()->{'thesaurusindexfile'},
		Echolot::Config::get()->{'templates'}->{'thesaurusindexfile'},
		Echolot::Config::get()->{'buildthesaurus'},
		remailers => \@data);
};


1;
# vim: set ts=4 shiftwidth=4:
