package Echolot::Mailin;

# (c) 2002 Peter Palfrader <peter@palfrader.org>
# $Id: Mailin.pm,v 1.5 2002/07/11 17:45:59 weasel Exp $
#

=pod

=head1 Name

Echolot::Mailin - Incoming Mail Dispatcher for Echolot

=head1 DESCRIPTION


=cut

use strict;
use warnings;
use Carp qw{cluck};
use English;
use Echolot::Globals;

sub make_sane_name() {
	my $result = time().'.'.$PROCESS_ID.'_'.Echolot::Globals::get()->{'internal_counter'}++.'.'.Echolot::Globals::get()->{'hostname'};
	return $result;
};

sub sane_move($$) {
	my ($from, $to) = @_;

	my $link_success = link($from, $to);
	$link_success or
		cluck("Cannot link $from to $to: $! - Trying move"),
		rename($from, $to) or 
			cluck("Renaming $from to $to didn't work either: $!"),
			return 0;
			
	$link_success && (unlink($from) or 
		cluck("Cannot unlink $from: $!") );
	return 1;
};

sub handle($) {
	my ($file) = @_;

	open (FH, $file) or 
		cluck("Cannot open file $file: $!"),
		return 0;
	
	my $to;
	while (<FH>) {
		chomp;
		last if $_ eq '';

		if (m/^To:\s*(.*?)\s*$/) {
			$to = $1;
		};
	};
	my $body = join('', <FH>);
	close (FH) or
		cluck("Cannot close file $file: $!");

	(defined $to) or
		cluck("No To header found in $file"),
		return 0;
	
	my $address_result = Echolot::Tools::verify_address_tokens($to) or
		cluck("Verifying '$to' failed"),
		return 0;
		
	my $type = $address_result->{'token'};
	my $timestamp = $address_result->{'timestamp'};
	
	Echolot::Conf::remailer_conf($body, $type, $timestamp), return 1 if ($type =~ /^conf\./);
	Echolot::Conf::remailer_key($body, $type, $timestamp), return 1 if ($type =~ /^key\./);
	Echolot::Conf::remailer_help($body, $type, $timestamp), return 1 if ($type =~ /^help\./);
	Echolot::Conf::remailer_stats($body, $type, $timestamp), return 1 if ($type =~ /^stats\./);
	Echolot::Conf::remailer_adminkey($body, $type, $timestamp), return 1 if ($type =~ /^adminkey\./);

	Echolot::Pinger::receive($body, $type, $timestamp), return 1 if ($type eq 'ping');

	cluck("Didn't know what to do with '$to'"),
	return 0;
};

sub process() {
	my $mailindir = Echolot::Config::get()->{'mailindir'};
	my $targetdir = Echolot::Config::get()->{'mailerrordir'};
	my @files = ();
	for my $sub (qw{new cur}) {
		opendir(DIR, $mailindir.'/'.$sub) or
			cluck("Cannot open direcotry '$mailindir/$sub': $!"),
			return 0;
		push @files, map { $sub.'/'.$_ } grep { ! /^\./ } readdir(DIR);
		closedir(DIR) or
			cluck("Cannot close direcotry '$mailindir/$sub': $!");
	};
	Echolot::Globals::get()->{'storage'}->delay_commit();
	for my $file (@files) {
		$file =~ /^(.*)$/s or
			confess("I really should match here. ('$file').");
		$file = $1;
		if (handle($mailindir.'/'.$file)) {
			unlink($mailindir.'/'.$file);
		} else {
			my $name = make_sane_name();
			sane_move($mailindir.'/'.$file, $targetdir.'/new/'.$name) or
				cluck("Sane moving of $mailindir/$file to $targetdir/new/$name failed");
		};
	};
	Echolot::Globals::get()->{'storage'}->enable_commit();
};

1;

# vim: set ts=4 shiftwidth=4:
