package Echolot::Pinger::CPunk;

# (c) 2002 Peter Palfrader <peter@palfrader.org>
# $Id: CPunk.pm,v 1.13 2003/02/15 11:43:41 weasel Exp $
#

=pod

=head1 Name

Echolot::Pinger::CPunk - send cypherpunk pings

=head1 DESCRIPTION

This package provides functions for sending cypherpunk (type I) pings.

=cut

use strict;
use English;
use GnuPG::Interface;
use IO::Handle;
use Echolot::Log;

sub encrypt_to($$$$) {
	my ($msg, $recipient, $keys, $pgp2compat) = @_;

	(defined $keys->{$recipient}) or
		Echolot::Log::warn("Key for recipient $recipient is not defined."),
		return undef;
	(defined $keys->{$recipient}->{'key'}) or
		Echolot::Log::warn("Key->key for recipient $recipient is not defined."),
		return undef;
	my $keyring = Echolot::Config::get()->{'tmpdir'}.'/'.
		Echolot::Globals::get()->{'hostname'}.".".time.'.'.$PROCESS_ID.'_'.Echolot::Globals::get()->{'internalcounter'}++.'.keyring';
	
	my $GnuPG = new GnuPG::Interface;
	$GnuPG->call( Echolot::Config::get()->{'gnupg'} ) if (Echolot::Config::get()->{'gnupg'});
	$GnuPG->options->hash_init( 
		homedir => Echolot::Config::get()->{'gnupghome'} );
	$GnuPG->options->meta_interactive( 0 );

	my ( $stdin_fh, $stdout_fh, $stderr_fh, $status_fh )
		= ( IO::Handle->new(),
		IO::Handle->new(),
		IO::Handle->new(),
		IO::Handle->new(),
		);
	my $handles = GnuPG::Handles->new (
		stdin      => $stdin_fh,
		stdout     => $stdout_fh,
		stderr     => $stderr_fh,
		status     => $status_fh
		);
	my $pid = $GnuPG->wrap_call(
		commands     => [ '--import' ],
		command_args => [qw{--no-options --no-secmem-warning --no-default-keyring --fast-list-mode --keyring}, $keyring, '--', '-' ],
		handles      => $handles );
	print $stdin_fh $keys->{$recipient}->{'key'};
	close($stdin_fh);

	my $stdout = join '', <$stdout_fh>; close($stdout_fh);
	my $stderr = join '', <$stderr_fh>; close($stderr_fh);
	my $status = join '', <$status_fh>; close($status_fh);

	waitpid $pid, 0;

	($stdout eq '') or
		Echolot::Log::info("GnuPG returned something in stdout '$stdout' while adding key for '$recipient': So what?");
	#($stderr eq '') or
		#Echolot::Log::warn("GnuPG returned something in stderr: '$stderr' while adding key for '$recipient'; returning."),
		#return undef;
	($status =~ /^^\[GNUPG:\] IMPORTED $recipient /m) or
		Echolot::Log::info("GnuPG status '$status' didn't indicate key for '$recipient' was imported correctly."),
		return undef;






	$msg =~ s/\r?\n/\r\n/g;




	$GnuPG->options->hash_init(
		armor   => 1 );

	( $stdin_fh, $stdout_fh, $stderr_fh, $status_fh )
		= ( IO::Handle->new(),
		IO::Handle->new(),
		IO::Handle->new(),
		IO::Handle->new(),
		);
	$handles = GnuPG::Handles->new (
		stdin      => $stdin_fh,
		stdout     => $stdout_fh,
		stderr     => $stderr_fh,
		status     => $status_fh
		);
	my $command_args = [qw{--no-options --no-secmem-warning --always-trust --no-default-keyring --cipher-algo 3DES --keyring}, $keyring, '--recipient', $recipient];
	my $plaintextfile;

	if ($pgp2compat) {
		push @$command_args, qw{--pgp2};
	};
	# Files are required for compaitibility with PGP 2.*
	# we also use files in all other cases since there is a bug in either GnuPG or GnuPG::Interface
	# that let Echolot die if in certain cases:
	#  If a key is unuseable because it expired and we want to encrypt something to it
	#  pingd dies if there is only enough time between calling encrypt() and printing the message
	#  to GnuPG. (a sleep 1 triggered that reproduceably)
	$plaintextfile = Echolot::Config::get()->{'tmpdir'}.'/'.
		Echolot::Globals::get()->{'hostname'}.".".time.'.'.$PROCESS_ID.'_'.Echolot::Globals::get()->{'internalcounter'}++.'.plaintext';
	open (F, '>'.$plaintextfile) or
		Echolot::Log::warn("Cannot open $plaintextfile for writing: $!."),
		return 0;
	print (F $msg);
	close (F) or
		Echolot::Log::warn("Cannot close $plaintextfile."),
		return 0;
	push @$command_args, $plaintextfile;

	$pid = $GnuPG->encrypt(
		command_args => $command_args,
		handles      => $handles );
	close($stdin_fh);

	$stdout = join '', <$stdout_fh>; close($stdout_fh);
	$stderr = join '', <$stderr_fh>; close($stderr_fh);
	$status = join '', <$status_fh>; close($status_fh);

	waitpid $pid, 0;

	#($stderr eq '') or
		#Echolot::Log::warn("GnuPG returned something in stderr: '$stderr' while encrypting to '$recipient'."),
		#return undef;
	($status =~ /^\[GNUPG:\] KEYEXPIRED (\d+)/m) and
		Echolot::Log::info("Key $recipient expired at ".scalar gmtime($1)." UTC"),
		return undef;
	(($status =~ /^\[GNUPG:\] BEGIN_ENCRYPTION\s/m) &&
	 ($status =~ /^\[GNUPG:\] END_ENCRYPTION\s/m)) or
		Echolot::Log::info("GnuPG status '$status' didn't indicate message to '$recipient' was encrypted correctly (stderr: $stderr; args: ".join(' ', @$command_args).")."),
		return undef;

	unlink ($keyring) or
		Echolot::Log::warn("Cannot unlink tmp keyring '$keyring'."),
		return undef;
	unlink ($keyring.'~'); # gnupg does those evil backups

	(defined $plaintextfile) and 
		( unlink ($plaintextfile) or
			Echolot::Log::warn("Cannot unlink tmp keyring '$plaintextfile'."),
			return undef);


	my $result;

	$plaintextfile .= '.asc';
	open (F, '<'.$plaintextfile) or
		Echolot::Log::warn("Cannot open $plaintextfile for reading: $!."),
		return 0;
	$result = join '', <F>;
	close (F) or
		Echolot::Log::warn("Cannot close $plaintextfile."),
		return 0;

	(defined $plaintextfile) and 
		( unlink ($plaintextfile) or
			Echolot::Log::warn("Cannot unlink tmp keyring '$plaintextfile'."),
			return undef);

	$result =~ s,^Version: .*$,Version: N/A,m;
	return $result;
};

sub ping($$$$) {
	my ($body, $to, $chain, $keys) = @_;

	my $msg = $body;

	for my $hop (reverse @$chain) {
		$msg = "::\n".
			"Anon-To: $to\n".
			"\n".
			$msg;

		if ($hop->{'encrypt'}) {
			my $encrypted = encrypt_to($msg, $hop->{'keyid'}, $keys, $hop->{'pgp2compat'});
			(defined $encrypted) or 
				Echolot::Log::debug("Encrypted is undefined."),
				return undef;
			$msg = "::\n".
				"Encrypted: PGP\n".
				"\n".
				$encrypted;
		};
		$to = $hop->{'address'};
	}

	Echolot::Tools::send_message(
		To	=> $to,
		Body => $msg
	);

	return 1;
};

1;
# vim: set ts=4 shiftwidth=4:
