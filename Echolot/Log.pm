package Echolot::Log;

# (c) 2002 Peter Palfrader <peter@palfrader.org>
# $Id: Log.pm,v 1.3 2003/01/14 06:32:22 weasel Exp $
#

=pod

=head1 Name

Echolot::Globals - echolot global variables

=head1 DESCRIPTION

=cut

use strict;
use Carp qw{};
use Log::Dispatch::File;
use Log::Dispatch;

my $LOG;

my @monnames = qw{Jan Feb Mar Arp May Jun Jul Aug Sep Oct Nov Dec};
sub header_log(%) {
	my (%msg) = @_;

	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
	my $time = sprintf("%s %02d %02d:%02d:%02d",
		$monnames[$mon],
		$mday,
		$hour, $min, $sec);
	my $logstring = $time.' '.
		'['.uc($msg{'level'}).']'. ' '.
		$msg{'message'}."\n";
	$logstring =~ s/(?<=.)^/	/mg;
	return $logstring;
};

sub reopen() {
	$LOG->remove( 'file1' );
	$LOG->add( Log::Dispatch::File->new(
		name       => 'file1',
		min_level  => Echolot::Config::get()->{'loglevel'},
		filename   => Echolot::Config::get()->{'logfile'},
		mode       => 'append',
	));
};

sub init(%) {
	my (%args) = @_;

	$LOG = Log::Dispatch->new( callbacks => \&header_log );
	reopen();
};

sub debug($) {
	$LOG->debug(@_);
};
sub info($) {
	$LOG->info(@_);
};
sub notice($) {
	$LOG->notice(@_);
};
sub warn($) {
	$LOG->warning(@_);
};
sub warning($) {
	$LOG->warning(@_);
};
sub error($) {
	$LOG->error(@_);
};
sub critical($) {
	$LOG->critical(@_);
};
sub alert($) {
	$LOG->alert(@_);
};
sub emergency($) {
	$LOG->emergency(@_);
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
