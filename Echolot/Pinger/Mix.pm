package Echolot::Pinger::Mix;

# (c) 2002 Peter Palfrader <peter@palfrader.org>
# $Id: Mix.pm,v 1.14 2003/04/29 18:15:37 weasel Exp $
#

=pod

=head1 Name

Echolot::Pinger::Mix - send mix pings

=head1 DESCRIPTION

This package provides functions for sending mixmaster (type II) pings.

=cut

use strict;
use English;
use IO::Handle;
use Echolot::Log;

sub ping($$$$$) {
	my ($body, $to, $with_from, $chain, $keys) = @_;

	my $chaincomma = join (',', @$chain);

	my $keyring = Echolot::Config::get()->{'mixhome'}.'/pubring.mix';
	open (F, '>'.$keyring) or
		Echolot::Log::warn("Cannot open $keyring for writing: $!."),
		return 0;
	for my $keyid (keys %$keys) {
		print (F $keys->{$keyid}->{'summary'}, "\n\n");
		print (F $keys->{$keyid}->{'key'},"\n\n");
	};
	close (F) or
		Echolot::Log::warn("Cannot close $keyring: $!."),
		return 0;

	my $type2list = Echolot::Config::get()->{'mixhome'}.'/type2.list';
	open (F, '>'.$type2list) or
		Echolot::Log::warn("Cannot open $type2list for writing: $!."),
		return 0;
	for my $keyid (keys %$keys) {
		print (F $keys->{$keyid}->{'summary'}, "\n");
	};
	close (F) or
		Echolot::Log::warn("Cannot close $type2list: $!."),
		return 0;
	
	my $mixcfg = Echolot::Config::get()->{'mixhome'}.'/mix.cfg';
	my $address = Echolot::Config::get()->{'my_localpart'} . '@' .
	              Echolot::Config::get()->{'my_domain'};
	my $sendmail = Echolot::Config::get()->{'sendmail'};
	open (F, ">$mixcfg") or
		Echolot::Log::warn("Cannot open $mixcfg for writing: $!."),
		return 0;
	print (F "REMAIL          n\n");
	print (F "NAME            Echolot Pinger\n");
	print (F "ADDRESS         $address\n");
	print (F "PUBRING         pubring.mix\n");
	print (F "TYPE2LIST       type2.list\n");
	print (F "SENDMAIL        $sendmail -f $address -t\n");
	print (F "VERBOSE         0\n");
	close (F) or
		Echolot::Log::warn("Cannot close $mixcfg: $!."),
		return 0;
	
	my ($stdinR, $stdinW) = (IO::Handle->new(), IO::Handle->new());
	my ($stdoutR, $stdoutW) = (IO::Handle->new(), IO::Handle->new());
	my ($stderrR, $stderrW) = (IO::Handle->new(), IO::Handle->new());
	pipe $stdinR, $stdinW;
	pipe $stdoutR, $stdoutW;
	pipe $stderrR, $stderrW;
	my $pid = fork();
	defined $pid or
		Echolot::Log::warn("Cannot fork for calling mixmaster: $!."),
		return 0;
	unless ($pid) { # child
		$stdinW->close;
		$stdoutR->close;
		$stderrR->close;
		close STDIN;
		close STDOUT;
		close STDERR;
		open (STDIN, "<&".$stdinR->fileno) or Echolot::Log::warn ("Cannot dup stdinR (fd ".$stdinR->fileno.") as STDIN: $!");
		open (STDOUT, ">&".$stdoutW->fileno) or Echolot::Log::warn ("Cannot dup stdoutW (fd ".$stdoutW->fileno.") as STDOUT: $!");
		open (STDERR, ">&".$stderrW->fileno) or Echolot::Log::warn ("Cannot dup stderrW (fd ".$stderrW->fileno.") as STDERE: $!");
		$ENV{'MIXPATH'} = Echolot::Config::get()->{'mixhome'};
		{ exec(Echolot::Config::get()->{'mixmaster'}, qw{-m -S -l}, $chaincomma); };
		Echolot::Log::warn("Cannot exec mixpinger: $!.");
		exit(1);
	};
	$stdinR->close;
	$stdoutW->close;
	$stderrW->close;

	my $msg;
	$msg .= "From: Echolot Pinger <$address>\n" if $with_from;
	$msg .= "To: $to\n\n$body\n";

	Echolot::Log::debug("mixping: fds: stdinW $stdinW; stdoutR $stdoutR; stderrR $stderrR."),
	my ($stdout, $stderr, undef) = Echolot::Tools::readwrite_gpg($msg, $stdinW, $stdoutR, $stderrR, undef);
	waitpid $pid, 0;

	$stderr =~ s/\n+$//;
	Echolot::Log::debug("Mixmaster said on unfiltered stderr: $stderr") if ($stderr ne '');
	$stderr =~ s/^Chain: .*//mg;
	$stderr =~ s/^Warning: The message has a From: line.*//mg;
	$stderr =~ s/\n+$//;
	Echolot::Log::info("Mixmaster said on stdout: $stdout") if ($stdout ne '');
	Echolot::Log::warn("Mixmaster said on stderr: $stderr") if ($stderr ne '');

	return 1;
};

1;
# vim: set ts=4 shiftwidth=4:
