package Echolot::Mailin;

# (c) 2002 Peter Palfrader <peter@palfrader.org>
# $Id: Mailin.pm,v 1.1 2002/06/05 04:05:40 weasel Exp $
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
	
	my $delimiter = quotemeta( Echolot::Config::get()->{'recipient_delimiter'});
	my ($type, $timestamp, $received_hash) = $to =~ /$delimiter (.*) = (\d+) = ([0-9a-f]+) @/x or
		cluck("Could not parse to header '$to'"),
		return 0;

	my $token = $type.'='.$timestamp;
	my $hash = Echolot::Tools::hash($token . Echolot::Globals::get()->{'storage'}->get_secret() );
	my $cut_hash = substr($hash, 0, Echolot::Config::get()->{'hash_len'});

	($cut_hash eq $received_hash) or
		cluck("Hash mismatch in '$to'"),
		return 0;
	
	Echolot::Conf::remailer_conf($body, $type, $timestamp), return 1 if ($type =~ /^conf\./);
	Echolot::Conf::remailer_key($body, $type, $timestamp), return 1 if ($type =~ /^key\./);
	Echolot::Conf::remailer_help($body, $type, $timestamp), return 1 if ($type =~ /^help\./);
	Echolot::Conf::remailer_stats($body, $type, $timestamp), return 1 if ($type =~ /^stats\./);

	Echolot::Ping::receive($body, $type, $timestamp), return 1 if ($type =~ /^ping\./);

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
	for my $file (@files) {
		$file =~ /^(.*)$/s or
			croak("I really should match here. ('$file').");
		$file = $1;
		if (handle($mailindir.'/'.$file)) {
			unlink($mailindir.'/'.$file);
		} else {
			my $name = make_sane_name();
			sane_move($mailindir.'/'.$file, $targetdir.'/new/'.$name) or
				cluck("Sane moving of $mailindir/$file to $targetdir/new/$name failed");
		};
	};
};

1;

# vim: set ts=4 shiftwidth=4:
