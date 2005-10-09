package Echolot::Thesaurus;

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

Echolot::Thesaurus - build thesaurus pages

=head1 DESCRIPTION

This package provides necessary functions for the thesaurus.

=cut

use strict;
use English;
use Echolot::Log;


sub save_thesaurus($$$) {
	my ($otype, $oid, $data) = @_;

	return 1 unless Echolot::Config::get()->{'thesaurus'};

	my ($type) = $otype =~ /^([a-z-]+)$/;
	Echolot::Log::cluck("type '$otype' is not clean in save_thesaurus."), return 0 unless defined $type;
	my ($id) = $oid =~ /^([0-9]+)$/;
	Echolot::Log::cluck("id '$oid' is not clean in save_thesaurus."), return 0 unless defined $id;

	my $file = Echolot::Config::get()->{'thesaurusdir'}.'/'.$id.'.'.$type;
	open (F, ">$file") or
		Echolot::Log::warn ("Cannot open '$file': $!."),
		return 0;
	print F $data;
	close (F);

	return 1;
};

sub build_thesaurus() {
	return 1 unless Echolot::Config::get()->{'thesaurus'};

	my $dir = Echolot::Config::get()->{'thesaurusdir'};
	opendir(DIR, $dir) or 
		Echolot::Log::warn ("Cannot open '$dir': $!."),
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
		my $caps = Echolot::Globals::get()->{'storage'}->get_capabilities($remailer->{'address'});
		next unless defined $caps;
		next unless $caps !~ m/\btesting\b/i;
		
		my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
			$atime,$mtime,$ctime,$blksize,$blocks)
			= stat($dir.'/'.$filename);

		if ($mtime < $expire_date) {
			unlink ($dir.'/'.$filename) or
				Echolot::Log::warn("Cannot unlink expired $filename.");
			Echolot::Log::info("Expired thesaurus file $filename.");
			next;
		};

		my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday)
			= gmtime($mtime);

		my $date = sprintf("%04d-%02d-%02d", $year+1900, $mon+1, $mday);
		my $time = sprintf("%02d:%02d", $hour, $min);


		$data->{$remailer->{'address'}}->{$what.'_href'} = $filename;
		$data->{$remailer->{'address'}}->{$what.'_date'} = $date;
		$data->{$remailer->{'address'}}->{$what.'_time'} = $time;
		$data->{$remailer->{'address'}}->{'id'} = $id;
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
		'thesaurusindexfile',
		Echolot::Config::get()->{'buildthesaurus'},
		remailers => \@data);

	open(F, ">$dir/index.txt") or
		Echolot::Log::warn ("Cannot open '$dir/index.txt': $!."),
		return 0;
	for my $remailer (@data) {
		printf F "%s\t%s\t%s\n", $remailer->{'nick'}, $remailer->{'id'}, $remailer->{'address'};
	};
	close(F) or
		Echolot::Log::warn ("Cannot close '$dir/index.txt': $!."),
		return 0;
};


1;
# vim: set ts=4 shiftwidth=4:
