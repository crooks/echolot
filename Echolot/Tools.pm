package Echolot::Tools;

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

Echolot::Tools - Tools for echolot

=head1 DESCRIPTION


=cut

use strict;
use HTML::Template;
use Digest::MD5 qw{};
use IO::Select;
use IO::Handle;
use GnuPG::Interface;
use Echolot::Log;
use English;

sub hash($) {
	my ($data) = @_;
	($data) = $data =~ m/(.*)/s;	# untaint
	my $hash = Digest::MD5::md5_hex($data);
	return $hash;
};

sub make_random($;%) {
	my ($length, %args) = @_;

	my $random;

	open (FH, Echolot::Config::get()->{'dev_random'}) or
		Echolot::Log::warn("Cannot open ".Echolot::Config::get()->{'dev_random'}." for reading: $!."),
		return 0;
	read(FH, $random, $length) or
		Echolot::Log::warn("Cannot read from ".Echolot::Config::get()->{'dev_random'}.": $!."),
		return 0;
	close (FH) or
		Echolot::Log::warn("Cannot close ".Echolot::Config::get()->{'dev_random'}.": $!."),
		return 0;

	$random = unpack('H*', $random)
		if ($args{'armor'} == 1);

	return $random;
};

sub make_mac($) {
	my ($token) = @_;

	my $mac = hash($token . Echolot::Globals::get()->{'storage'}->get_secret() );
	return $mac;
};

sub makeShortNumHash($) {
	my ($text) = @_;

	my $hash = Echolot::Tools::make_mac($text);
	$hash = substr($hash, 0, 4);
	my $sum = hex($hash);
	return $sum;
};

sub verify_mac($$) {
	my ($token, $mac) = @_;
	
	return (hash($token . Echolot::Globals::get()->{'storage'}->get_secret() )  eq  $mac);
};

sub make_address($) {
	my ($subsystem) = @_;
	
	my $token = $subsystem.'='.time();
	my $hash = hash($token . Echolot::Globals::get()->{'storage'}->get_secret() );
	my $cut_hash = substr($hash, 0, Echolot::Config::get()->{'hash_len'});
	my $complete_token = $token.'='.$cut_hash;
	my $address = Echolot::Config::get()->{'recipient_delimiter'} ne ''?
		Echolot::Config::get()->{'my_localpart'}.
			Echolot::Config::get()->{'recipient_delimiter'}.
			$complete_token.
			'@'.
			Echolot::Config::get()->{'my_domain'}
		:
		Echolot::Config::get()->{'my_localpart'}.
			'@'.
			Echolot::Config::get()->{'my_domain'}.
			'('.
			$complete_token.
			')';
	
	return $address;
};

sub verify_address_tokens($) {
	my ($address) = @_;

	my ($type, $timestamp, $received_hash);
	if (Echolot::Config::get()->{'recipient_delimiter'} ne '') {
		my $delimiter = quotemeta( Echolot::Config::get()->{'recipient_delimiter'});
		($type, $timestamp, $received_hash) = $address =~ /$delimiter (.*) = (\d+) = ([0-9a-f]+) @/x or
		($type, $timestamp, $received_hash) = $address =~ /\( (.*) = (\d+) = ([0-9a-f]+) \)/x or
			Echolot::Log::debug("Could not parse to header '$address'."),
			return undef;
	} else {
		($type, $timestamp, $received_hash) = $address =~ /\( (.*) = (\d+) = ([0-9a-f]+) \)/x or
			Echolot::Log::debug("Could not parse to header '$address'."),
			return undef;
	};

	my $token = $type.'='.$timestamp;
	my $hash = Echolot::Tools::hash($token . Echolot::Globals::get()->{'storage'}->get_secret() );
	my $cut_hash = substr($hash, 0, Echolot::Config::get()->{'hash_len'});

	($cut_hash eq $received_hash) or
		Echolot::Log::info("Hash mismatch in '$address'."),
		return undef;

	return 
		{ timestamp => $timestamp,
		  token => $type };
};

sub send_message(%) {
	my (%args) = @_;

	defined($args{'To'}) or
		Echolot::Log::cluck ('No recipient address given.'),
		return 0;
	$args{'Subject'} = '(no subject)' unless (defined $args{'Subject'});
	$args{'Body'} = '' unless (defined $args{'Body'});
	$args{'From_'} =
		Echolot::Config::get()->{'my_localpart'}.
		'@'.
		Echolot::Config::get()->{'my_domain'};
	if (defined $args{'Token'}) {
		$args{'From'} = make_address( $args{'Token'} );
	} else {
		$args{'From'} = $args{'From_'};
	};
	$args{'Subject'} = 'none' unless (defined $args{'Subject'});
	
	my @lines = map { $_."\n" } split (/\r?\n/, $args{'Body'});

	open(SENDMAIL, '|'.Echolot::Config::get()->{'sendmail'}.' -f '.$args{'From_'}.' -t')
		or Echolot::Log::warn("Cannot run sendmail: $!."),
		return 0;
	printf SENDMAIL "From: %s\n", $args{'From'};
	printf SENDMAIL "To: %s\n", $args{'To'};
	printf SENDMAIL "Subject: %s\n", $args{'Subject'};
	printf SENDMAIL "\n";
	for my $line (@lines) {
		print SENDMAIL $line;
	};
	close SENDMAIL;

	return 1;
};

sub make_monthname($) {
	my ($month) = @_;
	my @MON  = qw{Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec};
	return $MON[$month];
};

sub make_dayname($) {
	my ($day) = @_;
	my @WDAY = qw{Sun Mon Tue Wed Thu Fri Sat};
	return $WDAY[$day];
};

sub date822($) {
	my ($date) = @_;

	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday) = gmtime($date);
	# 14 Aug 2002 17:11:12 +0100
	return sprintf("%s, %02d %s %d %02d:%02d:%02d +0000",
		make_dayname($wday),
		$mday,
		make_monthname($mon),
		$year + 1900,
		$hour,
		$min,
		$sec);
};

sub write_meta_information($%) {
	my ($file, %data) = @_;

	return 1 unless Echolot::Config::get()->{'write_meta_files'};

	$file .= Echolot::Config::get()->{'meta_extension'};
	open (F, ">$file") or
		Echolot::Log::warn ("Cannot open $file: $!."),
		return 0;
	if (defined $data{'Expires'}) {
		my $date = date822($data{'Expires'});
		print F "Expires: $date\n";
	};
	close(F);
	return 1;
};

sub escape_HTML_entities($) {
	my ($in) = @_;

	$in =~ s/&/&amp;/;
	$in =~ s/"/&quot;/;
	$in =~ s/</&lt;/;
	$in =~ s/>/&gt;/;

	return $in;
};

sub write_HTML_file($$;$%) {
	my ($origfile, $template_file, $expire, %templateparams) = @_;

	my $operator = Echolot::Config::get()->{'operator_address'};
	$operator =~ s/@/./;

	for my $lang ( keys %{Echolot::Config::get()->{'templates'}} ) {
		my $template =  HTML::Template->new(
			filename => Echolot::Config::get()->{'templates'}->{$lang}->{$template_file},
			strict => 0,
			die_on_bad_params => 0,
			global_vars => 1 );
		$template->param ( %templateparams );
		$template->param ( CURRENT_TIMESTAMP => scalar gmtime() );
		$template->param ( SITE_NAME => Echolot::Config::get()->{'sitename'} );
		$template->param ( separate_rlist => Echolot::Config::get()->{'separate_rlists'} );
		$template->param ( combined_list => Echolot::Config::get()->{'combined_list'} );
		$template->param ( thesaurus => Echolot::Config::get()->{'thesaurus'} );
		$template->param ( fromlines => Echolot::Config::get()->{'fromlines'} );
		$template->param ( version => Echolot::Globals::get()->{'version'} );
		$template->param ( operator => $operator );
		$template->param ( expires => date822( time + $expire ));

		my $file = $origfile;
		$file .= '.'.$lang unless ($lang eq 'default');
		$file .= '.html';

		open(F, '>'.$file) or
			Echolot::Log::warn("Cannot open $file: $!."),
			return 0;
		print F $template->output() or
			Echolot::Log::warn("Cannot print to $file: $!."),
			return 0;
		close (F) or
			Echolot::Log::warn("Cannot close $file: $!."),
			return 0;

		if (defined $expire) {
			write_meta_information($file,
				Expires => time + $expire) or
				Echolot::Log::debug ("Error while writing meta information for $file."),
				return 0;
		};
	};

	return 1;
};

sub make_gpg_fds() {
	my %fds = (
		stdin => IO::Handle->new(),
		stdout => IO::Handle->new(),
		stderr => IO::Handle->new(),
		status => IO::Handle->new() );
	my $handles = GnuPG::Handles->new( %fds );
	return ($fds{'stdin'}, $fds{'stdout'}, $fds{'stderr'}, $fds{'status'}, $handles);
};

sub readwrite_gpg($$$$$) {
	my ($in, $inputfd, $stdoutfd, $stderrfd, $statusfd) = @_;

	Echolot::Log::trace("Entering readwrite_gpg.");

	local $INPUT_RECORD_SEPARATOR = undef;
	my $sout = IO::Select->new();
	my $sin = IO::Select->new();
	my $offset = 0;

	Echolot::Log::trace("input is $inputfd; output is $stdoutfd; err is $stderrfd; status is ".(defined $statusfd ? $statusfd : 'undef').".");

	$inputfd->blocking(0);
	$stdoutfd->blocking(0);
	$statusfd->blocking(0) if defined $statusfd;
	$stderrfd->blocking(0);
	$sout->add($stdoutfd);
	$sout->add($stderrfd);
	$sout->add($statusfd) if defined $statusfd;
	$sin->add($inputfd);

	my ($stdout, $stderr, $status) = ("", "", "");

	my ($readyr, $readyw);
	while ($sout->count() > 0 || (defined($sin) && ($sin->count() > 0))) {
		Echolot::Log::trace("select waiting for ".($sout->count())." fds.");
		($readyr, $readyw, undef) = IO::Select::select($sout, $sin, undef, 42);
		Echolot::Log::trace("ready: write: ".(defined $readyw ? scalar @$readyw : 'none')."; read: ".(defined $readyr ? scalar @$readyr : 'none'));
		for my $wfd (@$readyw) {
			Echolot::Log::trace("writing to $wfd.");
			my $written = 0;
			if ($offset != length($in)) {
				$written = $wfd->syswrite($in, length($in) - $offset, $offset);
			}
			unless (defined ($written)) {
				Echolot::Log::warn("Error while writing to GnuPG: $!");
				close $wfd;
				$sin->remove($wfd);
				$sin = undef;
			} else {
				$offset += $written;
				if ($offset == length($in)) {
					Echolot::Log::trace("writing to $wfd done.");
					close $wfd;
					$sin->remove($wfd);
					$sin = undef;
				}
			}
		}

		next unless (defined(@$readyr)); # Wait some more.

		for my $rfd (@$readyr) {
			if ($rfd->eof) {
				Echolot::Log::trace("reading from $rfd done.");
				$sout->remove($rfd);
				close($rfd);
				next;
			}
			Echolot::Log::trace("reading from $rfd.");
			if ($rfd == $stdoutfd) {
				$stdout .= <$rfd>;
				next;
			}
			if (defined $statusfd && $rfd == $statusfd) {
				$status .= <$rfd>;
				next;
			}
			if ($rfd == $stderrfd) {
				$stderr .= <$rfd>;
				next;
			}
		}
	}
	Echolot::Log::trace("readwrite_gpg done.");
	return ($stdout, $stderr, $status);
};

sub crypt_symmetrically($$) {
	my ($msg, $direction) = @_;

	($direction eq 'encrypt' || $direction eq 'decrypt') or
		Echolot::Log::cluck("Wrong argument direction '$direction' passed to crypt_symmetrically."),
		return undef;

	my $GnuPG = new GnuPG::Interface;
	$GnuPG->call( Echolot::Config::get()->{'gnupg'} ) if (Echolot::Config::get()->{'gnupg'});
	$GnuPG->options->hash_init( 
		armor   => 1,
		homedir => Echolot::Config::get()->{'gnupghome'} );
	$GnuPG->options->meta_interactive( 0 );
	$GnuPG->passphrase( Echolot::Globals::get()->{'storage'}->get_secret() );

	my ( $stdin_fh, $stdout_fh, $stderr_fh, $status_fh, $handles ) = make_gpg_fds();
	my $pid = 
		$direction eq 'encrypt' ?
			$GnuPG->encrypt_symmetrically( handles      => $handles ) :
			$GnuPG->decrypt( handles      => $handles );
	my ($stdout, $stderr, $status) = readwrite_gpg($msg, $stdin_fh, $stdout_fh, $stderr_fh, $status_fh);
	waitpid $pid, 0;

	if ($direction eq 'encrypt') {
		(($status =~ /^\[GNUPG:\] BEGIN_ENCRYPTION\s/m) &&
		 ($status =~ /^\[GNUPG:\] END_ENCRYPTION\s/m)) or
			Echolot::Log::info("GnuPG status '$status' didn't indicate message was encrypted correctly (stderr: $stderr). Returning."),
			return undef;
	} elsif ($direction eq 'decrypt') {
		(($status =~ /^\[GNUPG:\] BEGIN_DECRYPTION\s/m) &&
		 ($status =~ /^\[GNUPG:\] DECRYPTION_OKAY\s/m) &&
		 ($status =~ /^\[GNUPG:\] END_DECRYPTION\s/m)) or
			Echolot::Log::info("GnuPG status '$status' didn't indicate message was decrypted correctly (stderr: $stderr). Returning."),
			return undef;
	};

	my $result = $stdout;
	$result =~ s,^Version: .*$,Version: N/A,m;
	return $result;
};

sub make_garbage() {

	my $file = Echolot::Config::get()->{'dev_urandom'};
	open(FH, $file) or
		Echolot::Log::warn("Cannot open $file: $!."),
		return "";
	my $random = '';
	my $want = int(rand(int(Echolot::Config::get()->{'random_garbage'} / 2)));
	my $i = 0;
	while ($want > 0) {
		my $buf;
		$want -= read(FH, $buf, $want);
		$random .= $buf;
		($i++ > 15 && $want > 0) and
			Echolot::Log::warn("Could not get enough garbage (still missing $want."),
			last;
	};
	close (FH) or
		Echolot::Log::warn("Cannot close $file: $!.");

	$random = unpack("H*", $random);
	$random = join "\n", grep { $_ ne '' } (split /(.{64})/, $random);
	$random = "-----BEGIN GARBAGE-----\n".
		$random."\n".
		"-----END GARBAGE-----\n";

	return $random;
};

sub read_file($;$) {
	my ($name, $fail_ok) = @_;

	unless (open (F, $name)) {
		Echolot::Log::warn("Could not open '$name': $!.") unless ($fail_ok);
		return undef;
	};
	local $/ = undef;
	my $result = <F>;
	close (F);

	return $result;
};

sub cleanup_tmp() {
	my $tmpdir = Echolot::Config::get()->{'tmpdir'};

	opendir(DIR, $tmpdir) or
		Echolot::Log::warn("Could not open '$tmpdir': $!."),
		return undef;
	my @files = grep { ! /^[.]/ } readdir(DIR);
	closedir(DIR);

	for my $file (@files) {
		unlink($tmpdir.'/'.$file) or
			Echolot::Log::warn("Could not unlink '$tmpdir/$file': $!.");
	};
};

1;

# vim: set ts=4 shiftwidth=4:
