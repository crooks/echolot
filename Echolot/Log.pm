package Echolot::Log;

# (c) 2002 Peter Palfrader <peter@palfrader.org>
# $Id: Log.pm,v 1.7 2003/02/18 06:38:09 weasel Exp $
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
