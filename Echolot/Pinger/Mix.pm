package Echolot::Pinger::Mix;

# (c) 2002 Peter Palfrader <peter@palfrader.org>
# $Id: Mix.pm,v 1.13 2003/02/17 14:44:15 weasel Exp $
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
	
	$ENV{'MIXPATH'} = Echolot::Config::get()->{'mixhome'};
	open(MIX, "|".Echolot::Config::get()->{'mixmaster'}." -m -S -l $chaincomma 2>/dev/null") or
		Echolot::Log::warn("Cannot exec mixpinger: $!."),
		return 0;
	print MIX "From: Echolot Pinger <$address>\n"
		if $with_from;
	print MIX "To: $to\n\n$body\n";
	close (MIX);
	    
	return 1;
};

1;
# vim: set ts=4 shiftwidth=4:
