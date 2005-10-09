package Echolot::Mailin;

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

Echolot::Mailin - Incoming Mail Dispatcher for Echolot

=head1 DESCRIPTION


=cut

use strict;
use English;
use Echolot::Globals;
use Echolot::Log;
use Fcntl ':flock'; # import LOCK_* constants
use POSIX; # import SEEK_* constants (older perls don't have SEEK_ in Fcntl)


sub make_sane_name() {
	my $result = time().'.'.$PROCESS_ID.'_'.Echolot::Globals::get()->{'internal_counter'}++.'.'.Echolot::Globals::get()->{'hostname'};
	return $result;
};

sub sane_move($$) {
	my ($from, $to) = @_;

	my $link_success = link($from, $to);
	$link_success or
		Echolot::Log::warn("Cannot link $from to $to: $!."),
		return 0;
		#- Trying move"),
		#rename($from, $to) or 
		#	cluck("Renaming $from to $to didn't work either: $!"),
		#	return 0;
			
	$link_success && (unlink($from) or 
		Echolot::Log::warn("Cannot unlink $from: $!.") );
	return 1;
};

sub handle($) {
	my ($lines) = @_;

	my $i=0;
	my $body = '';
	my $header = '';
	my $to;
	for ( ; $i < scalar @$lines; $i++) {
		my $line = $lines->[$i];
		chomp($line);
		last if $line eq '';
		$header .= $line."\n";

		if ($line =~ m/^To:\s*(.*?)\s*$/) {
			$to = $1;
		};
	};
	for ( ; $i < scalar @$lines; $i++) {
		$body .= $lines->[$i];
	};

	(defined $to) or
		Echolot::Log::info("No To header found in mail."),
		return 0;
	
	my $address_result = Echolot::Tools::verify_address_tokens($to) or
		Echolot::Log::debug("Verifying '$to' failed."),
		return 0;
		
	my $type = $address_result->{'token'};
	my $timestamp = $address_result->{'timestamp'};
	
	Echolot::Conf::remailer_conf($body, $type, $timestamp), return 1 if ($type =~ /^conf\./);
	Echolot::Conf::remailer_key($body, $type, $timestamp), return 1 if ($type =~ /^key\./);
	Echolot::Conf::remailer_help($body, $type, $timestamp), return 1 if ($type =~ /^help\./);
	Echolot::Conf::remailer_stats($body, $type, $timestamp), return 1 if ($type =~ /^stats\./);
	Echolot::Conf::remailer_adminkey($body, $type, $timestamp), return 1 if ($type =~ /^adminkey\./);

	Echolot::Pinger::receive($header, $body, $type, $timestamp), return 1 if ($type eq 'ping');
	Echolot::Chain::receive($header, $body, $type, $timestamp), return 1 if ($type eq 'chainping');

	Echolot::Log::warn("Didn't know what to do with '$to'."),
	return 0;
};

sub handle_file($) {
	my ($file) = @_;

	open (FH, $file) or 
		Echolot::Log::warn("Cannot open file $file: $!,"),
		return 0;
	my @lines = <FH>;
	my $body = join('', <FH>);
	close (FH) or
		Echolot::Log::warn("Cannot close file $file: $!.");

	return handle(\@lines);
};

sub read_mbox($) {
	my ($file) = @_;

	my @mail;
	my $mail = [];
	my $blank = 1;

	open(FH, '+<'. $file) or
		Echolot::Log::warn("cannot open '$file': $!."),
		return undef;
	flock(FH, LOCK_EX) or
		Echolot::Log::warn("cannot gain lock on '$file': $!."),
		return undef;

	while(<FH>) {
		if($blank && /\AFrom .*\d{4}/) {
			push(@mail, $mail) if scalar(@{$mail});
			$mail = [ $_ ];
			$blank = 0;
		} else {
			$blank = m#\A\Z# ? 1 : 0;
			push @$mail, $_;
		}
	}
	push(@mail, $mail) if scalar(@{$mail});

	seek(FH, 0, SEEK_SET) or
		Echolot::Log::warn("cannot seek to start of '$file': $!."),
		return undef;
	truncate(FH, 0) or
		Echolot::Log::warn("cannot truncate '$file' to zero size: $!."),
		return undef;
	flock(FH, LOCK_UN) or
		Echolot::Log::warn("cannot release lock on '$file': $!."),
		return undef;
	close(FH);

	return \@mail;
}

sub read_maildir($) {
	my ($dir) = @_;

	my @mail;

	my @files;
	for my $sub (qw{new cur}) {
		opendir(DIR, $dir.'/'.$sub) or
			Echolot::Log::warn("Cannot open direcotry '$dir/$sub': $!."),
			return undef;
		push @files, map { $sub.'/'.$_ } grep { ! /^\./ } readdir(DIR);
		closedir(DIR) or
			Echolot::Log::warn("Cannot close direcotry '$dir/$sub': $!.");
	};

	for my $file (@files) {
		$file =~ /^(.*)$/s or
			Echolot::Log::confess("I really should match here. ('$file').");
		$file = $1;

		my $mail = [];
		open(FH, $dir.'/'.$file) or
			Echolot::Log::warn("cannot open '$dir/$file': $!."),
			return undef;
		@$mail = <FH>;
		close(FH);

		push @mail, $mail;
	};

	for my $file (@files) {
		unlink $dir.'/'.$file or
			Echolot::Log::warn("cannot unlink '$dir/$file': $!.");
	};


	return \@mail;
}

sub storemail($$) {
	my ($path, $mail) = @_;

	my $tmpname = $path.'/tmp/'.make_sane_name();
	open (F, '>'.$tmpname) or
		Echolot::Log::warn("Cannot open $tmpname: $!."),
		return undef;
	print F join ('', @$mail);
	close F;
	
	my $i;
	for ($i = 0; $i < 5; $i++ ) {
		my $targetname = $path.'/cur/'.make_sane_name();
		sane_move($tmpname, $targetname) or
			sleep 1, next;
		last;
	};

	return undef if ($i == 5);
	return 1;
};

sub process() {
	my $inmail       = Echolot::Config::get()->{'mailin'};
	my $mailerrordir = Echolot::Config::get()->{'mailerrordir'};

	my $mails = (-d $inmail) ?
		read_maildir($inmail) :
		( ( -e $inmail ) ? read_mbox($inmail) : [] );

	Echolot::Globals::get()->{'storage'}->delay_commit();
	for my $mail (@$mails) {
		unless (handle($mail)) {
			if (Echolot::Config::get()->{'save_errormails'}) {
				Echolot::Log::info("Saving mail with unknown destination (probably a bounce) to mail-errordir.");
				my $name = make_sane_name();
				storemail($mailerrordir, $mail) or
					Echolot::Log::warn("Could not store a mail.");
			} else {
				Echolot::Log::info("Trashing mail with unknown destination (probably a bounce).");
			};
		};
	};
	Echolot::Globals::get()->{'storage'}->enable_commit();
};

1;

# vim: set ts=4 shiftwidth=4:
