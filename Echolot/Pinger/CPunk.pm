package Echolot::Pinger::CPunk;

# (c) 2002 Peter Palfrader <peter@palfrader.org>
# $Id: CPunk.pm,v 1.1 2002/06/18 17:18:40 weasel Exp $
#

=pod

=head1 Name

Echolot::Pinger::CPunk - send cypherpunk pings

=head1 DESCRIPTION

This package provides functions for sending cypherpunk (type I) pings.

=cut

use strict;
use warnings;
use Carp qw{cluck};
use English;
use GnuPG::Interface;
use IO::Handle;

sub encrypt_to($$$$) {
	my ($msg, $recipient, $keys, $pgp2compat) = @_;

	(defined $keys->{$recipient}) or
		cluck ("Key for recipient $recipient is not defined"),
		return undef;
	(defined $keys->{$recipient}->{'key'}) or
		cluck ("Key->key for recipient $recipient is not defined"),
		return undef;
	my $keyring = Echolot::Config::get()->{'tmpdir'}.'/'.
		Echolot::Globals::get()->{'hostname'}.".".time.'.'.$PROCESS_ID.'_'.Echolot::Globals::get()->{'internalcounter'}++.'.keyring';
	
	my $GnuPG = new GnuPG::Interface;
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
		command_args => [qw{--no-options --no-default-keyring --fast-list-mode --keyring}, $keyring, '--', '-' ],
		handles      => $handles );
	print $stdin_fh $keys->{$recipient}->{'key'};
	close($stdin_fh);

	my $stdout = join '', <$stdout_fh>; close($stdout_fh);
	my $stderr = join '', <$stderr_fh>; close($stderr_fh);
	my $status = join '', <$status_fh>; close($status_fh);

	waitpid $pid, 0;

	($stdout eq '') or
		cluck("GnuPG returned something in stdout '$stdout' while adding key for '$recipient': So what?\n");
	#($stderr eq '') or
		#cluck("GnuPG returned something in stderr: '$stderr' while adding key for '$recipient'; returning\n"),
		#return undef;
	($status =~ /^^\[GNUPG:\] IMPORTED $recipient /m) or
		cluck("GnuPG status '$status' didn't indicate key for '$recipient' was imporeted correctly. Returning\n"),
		return undef;











	$GnuPG->options->hash_init(
		armor   => 1,
		recipients => [ $recipient ] );

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
	my $command_args = [qw{--no-options --always-trust --no-default-keyring --keyring}, $keyring];
	my $plaintextfile;
	if ($pgp2compat) {
		#pgp2compat requires files, cannot use stdin

		$plaintextfile = Echolot::Config::get()->{'tmpdir'}.'/'.
			Echolot::Globals::get()->{'hostname'}.".".time.'.'.$PROCESS_ID.'_'.Echolot::Globals::get()->{'internalcounter'}++.'.plaintext';
		open (F, '>'.$plaintextfile) or
			cluck("Cannot open $plaintextfile for writing: $!"),
			return 0;
		print (F $msg);
		close (F) or
			cluck("Cannot close $plaintextfile"),
			return 0;


		push @$command_args, qw{--pgp2 --cipher-algo 3DES}, $plaintextfile;
		#push @$command_args, '--load-extension', 'idea', '--pgp2', $plaintextfile;
	} else {
		#push @$command_args, qw{ --pgp6 };
		#push @$command_args, qw{--disable-mdc --no-force-v4-certs --no-comment --escape-from --force-v3-sigs --no-ask-sig-expire --no-ask-cert-expire --digest-algo MD5 --compress-algo 1 --cipher-algo 3DES };
		#push @$command_args, qw{--rfc1991  --no-openpgp --disable-mdc  --no-force-v4-certs  --no-comment --escape-from    --force-v3-sigs   --no-ask-sig-expire --no-ask-cert-expire --digest-algo MD5 --compress-algo 1};
	};
		

	$pid = $GnuPG->encrypt(
		command_args => $command_args,
		handles      => $handles );
	unless ($pgp2compat) {
		print $stdin_fh $msg;
	};
	close($stdin_fh);

	$stdout = join '', <$stdout_fh>; close($stdout_fh);
	$stderr = join '', <$stderr_fh>; close($stderr_fh);
	$status = join '', <$status_fh>; close($status_fh);

	waitpid $pid, 0;

	#($stderr eq '') or
		#cluck("GnuPG returned something in stderr: '$stderr' while encrypting to '$recipient'; returning"),
		#return undef;
	(($status =~ /^^\[GNUPG:\] BEGIN_ENCRYPTION\s/m) &&
	 ($status =~ /^^\[GNUPG:\] END_ENCRYPTION\s/m)) or
		cluck("GnuPG status '$status' didn't indicate message to '$recipient' was encrypted correctly. Returning\n"),
		return undef;

	unlink ($keyring) or
		cluck("Cannot unlink tmp keyring '$keyring'"),
		return undef;

	(defined $plaintextfile) and 
		( unlink ($plaintextfile) or
			cluck("Cannot unlink tmp keyring '$plaintextfile'"),
			return undef);


	my $result;

	if ($pgp2compat) {
		#pgp2compat requires files, cannot use stdin

		$plaintextfile .= '.asc';
		open (F, '<'.$plaintextfile) or
			cluck("Cannot open $plaintextfile for reading $!"),
			return 0;
		$result = join '', <F>;
		close (F) or
			cluck("Cannot close $plaintextfile"),
			return 0;

		(defined $plaintextfile) and 
			( unlink ($plaintextfile) or
				cluck("Cannot unlink tmp keyring '$plaintextfile'"),
				return undef);
	} else {
		$result = $stdout;
	};

	$result =~ s,^Version: .*$,Version: N/A,m;
	return $result;
};

sub ping($$$$$) {
	my ($body, $to, $chain, $keys, $pgp2compat) = @_;

	my $msg = $body;

	for my $hop (reverse @$chain) {
		$msg = "::\n".
			"Anon-To: $to\n".
			"\n".
			$msg;
		my $encrypted = encrypt_to($msg, $hop->{'keyid'}, $keys, $pgp2compat);
		(defined $encrypted) or 
			cluck("Encrypted is undefined"),
			return undef;
		$msg = "::\n".
			"Encrypted: PGP\n".
			"\n".
			$encrypted;
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