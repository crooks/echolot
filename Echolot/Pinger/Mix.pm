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
	
	my($wtr, $rdr, $err);
	my $pid = open3($wtr, $rdr, $err, "|-");
	defined $pid or
		Echolot::Log::warn("Cannot fork for calling mixmaster: $!."),
		return 0;
	unless ($pid) { # child
		$ENV{'MIXPATH'} = Echolot::Config::get()->{'mixhome'};
		{ exec(Echolot::Config::get()->{'mixmaster'}, qw{-m -S -l}, $chaincomma); };
		Echolot::Log::warn("Cannot exec mixpinger: $!.");
		exit(1);
	};
	my $msg;
	$msg .= "From: Echolot Pinger <$address>\n" if $with_from;
	$msg .= "To: $to\n\n$body\n";

	my ($stdout, $stderr, undef) = Echolot::Tools::readwrite_gpg($msg, $wtr, $rdr, $err, undef);
	waitpid $pid, 0;

	$stderr =~ s/^Chain: .*//mg;
	$stderr =~ s/^Warning: The message has a From: line.*//mg;
	Echolot::Log::info("Mixmaster said on stdout: $stdout");
	Echolot::Log::warn("Mixmaster said on stderr: $stderr");

	return 1;
};

1;
# vim: set ts=4 shiftwidth=4:
