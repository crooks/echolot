package Echolot::Commands;

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

Echolot::Commands - manage commands like add key, set ttl etc.

=head1 DESCRIPTION

This package provides functions for sending out and receiving pings.

=cut

use strict;
use Echolot::Log;
use Fcntl ':flock'; # import LOCK_* constants
#use Fcntl ':seek'; # import SEEK_* constants
use POSIX; # import SEEK_* constants (older perls don't have SEEK_ in Fcntl)
use English;

sub addCommand($) {
	my ($command) = @_;

	my $filename = Echolot::Config::get()->{'commands_file'};
	open(FH, ">>$filename" ) or
		Echolot::Log::warn("Cannot open $filename for appending $!."),
		return 0;
	flock(FH, LOCK_EX) or
		Echolot::Log::warn("Cannot get exclusive lock on $filename: $!."),
		return 0;
	
	print FH $command,"\n";
	
	flock(FH, LOCK_UN) or
		Echolot::Log::warn("Cannot unlock $filename: $!.");
	close(FH) or
		Echolot::Log::warn("Cannot close $filename: $!.");
};

sub processCommands($) {
	my $filename = Echolot::Config::get()->{'commands_file'};

	(-e $filename) or
		return 1;
	my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size, $atime,$mtime,$ctime,$blksize,$blocks)= stat $filename;
	($size > 0) or
		return 1;
	
	open(FH, "+<$filename" ) or
		Echolot::Log::warn("Cannot open $filename for reading: $!."),
		return 0;
	flock(FH, LOCK_EX) or
		Echolot::Log::warn("Cannot get exclusive lock on $filename: $!."),
		return 0;
	

	while (<FH>) {
		chomp;
		my ($command, @args) = split;

		if ($command eq 'add') {
			Echolot::Globals::get()->{'storage'}->add_address(@args);
		} elsif ($command eq 'set') {
			Echolot::Globals::get()->{'storage'}->set_stuff(@args);
		} elsif ($command eq 'getkeyconf') {
			Echolot::Globals::get()->{'scheduler'}->schedule('getkeyconf', 0, time(), \@args );
		} elsif ($command eq 'sendpings') {
			Echolot::Globals::get()->{'scheduler'}->schedule('ping', 0, time(), \@args );
		} elsif ($command eq 'sendchainpings') {
			Echolot::Globals::get()->{'scheduler'}->schedule('chainping', 0, time(), \@args );
		} elsif ($command eq 'buildstats') {
			Echolot::Globals::get()->{'scheduler'}->schedule('buildstats', 0, time() );
		} elsif ($command eq 'buildkeys') {
			Echolot::Globals::get()->{'scheduler'}->schedule('buildkeys', 0, time() );
		} elsif ($command eq 'buildthesaurus') {
			Echolot::Globals::get()->{'scheduler'}->schedule('buildthesaurus', 0, time() );
		} elsif ($command eq 'buildfromlines') {
			Echolot::Globals::get()->{'scheduler'}->schedule('buildfromlines', 0, time() );
		} elsif ($command eq 'summary') {
			@args = ('manual');
			Echolot::Globals::get()->{'scheduler'}->schedule('summary', 0, time(), \@args );
		} elsif ($command eq 'delete') {
			Echolot::Globals::get()->{'storage'}->delete_remailer(@args);
		} elsif ($command eq 'setremailercaps') {
			my $addr = shift @args;
			my $conf = join(' ', @args);
			Echolot::Conf::set_caps_manually($addr, $conf);
		} elsif ($command eq 'deleteremailercaps') {
			Echolot::Globals::get()->{'storage'}->delete_remailercaps(@args);
		} else {
			Echolot::Log::warn("Unkown command: '$_'.");
		};
	};

	seek(FH, 0, SEEK_SET) or
		Echolot::Log::warn("Cannot seek to start '$filename': $!."),
		return 0;
	truncate(FH, 0) or
		Echolot::Log::warn("Cannot truncate '$filename' to zero length: $!."),
		return 0;
	flock(FH, LOCK_UN) or
		Echolot::Log::warn("Cannot unlock '$filename': $!.");
	close(FH) or
		Echolot::Log::warn("Cannot close '$filename': $!.");
};

1;
# vim: set ts=4 shiftwidth=4:
