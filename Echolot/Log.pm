package Echolot::Log;

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

Echolot::Globals - echolot global variables

=head1 DESCRIPTION

=cut

use strict;
use Carp qw{};
#use Time::HiRes qw( gettimeofday );

my %LOGLEVELS = qw{
	trace		8
	debug		7
	info		6
	notice		5
	warn		4
	warning		4
	error		3
	critical	2
	alert		1
	emergency	0
};

my $LOGLEVEL;
my $LOGFILE;
my $LOGFH;

my @monnames = qw{Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec};
sub header_log($$) {
	my ($level, $msg) = @_;

	#my ($secs, $msecs) = gettimeofday();
	#my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime( $secs );
	#my $time = sprintf("%s %02d %02d:%02d:%02d.%06d",
	#	$monnames[$mon],
	#	$mday,
	#	$hour, $min, $sec, $msecs);
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
	my $time = sprintf("%s %02d %02d:%02d:%02d",
		$monnames[$mon],
		$mday,
		$hour, $min, $sec);
	my $prefix = $time.' ['.uc($level).'] ';
	my $logstring = $msg."\n";
	my $first = 0;
	$logstring =~ s/^/ $prefix . ($first++ ? '  ' : '' ) /emg;
	return $logstring;
};

sub reopen() {
	$LOGFH->close() if ($LOGFH->opened());

	open($LOGFH, ">>".$LOGFILE) or
		warn("Cannot open logfile $LOGFILE: $!");
};

sub init() {
	$LOGFILE = Echolot::Config::get()->{'logfile'};
	$LOGLEVEL = Echolot::Config::get()->{'loglevel'};
	$LOGFH = new IO::Handle;

	die ("Logfile not defined") unless defined ($LOGFILE);
	die ("Loglevel not defined") unless defined ($LOGLEVEL);
	die ("Loglevel $LOGLEVEL unkown") unless defined ($LOGLEVELS{$LOGLEVEL});

	$LOGLEVEL = $LOGLEVELS{$LOGLEVEL};

	reopen();
};

sub log_message($$) {
	my ($level, $msg) = @_;

	die("Loglevel $level unkown.") unless defined $LOGLEVELS{$level};
	return if $LOGLEVELS{$level} > $LOGLEVEL;

	$msg = header_log($level, $msg);
	print $LOGFH $msg;
	$LOGFH->flush();
};

sub trace($) {
	log_message('trace', $_[0]);
};
sub debug($) {
	log_message('debug', $_[0]);
};
sub info($) {
	log_message('info', $_[0]);
};
sub notice($) {
	log_message('notice', $_[0]);
};
sub warn($) {
	log_message('warn', $_[0]);
};
sub warning($) {
	log_message('warning', $_[0]);
};
sub error($) {
	log_message('error', $_[0]);
};
sub critical($) {
	log_message('critical', $_[0]);
};
sub alert($) {
	log_message('alert', $_[0]);
};
sub emergency($) {
	log_message('emergency', $_[0]);
};

sub logdie($) {
	my ($msg) = @_;
	critical($msg);
	die($msg);
};
sub cluck($) {
	my ($msg) = @_;
	my $longmess = Carp::longmess();
	$longmess =~ s/^/	/mg;
	$msg .= "\n".$longmess;
	warning($msg);
};
sub confess($) {
	my ($msg) = @_;
	my $longmess = Carp::longmess();
	$longmess =~ s/^/	/mg;
	$msg .= "\n".$longmess;
	error($msg);
	die($msg);
};

1;
# vim: set ts=4 shiftwidth=4:
