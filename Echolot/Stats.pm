package Echolot::Stats;

# (c) 2002 Peter Palfrader <peter@palfrader.org>
# $Id: Stats.pm,v 1.1 2002/06/11 15:34:53 weasel Exp $
#

=pod

=head1 Name

Echolot::Stats - produce Stats, keyrings et al

=head1 DESCRIPTION

This package provides functions for generating remailer stats,
and keyrings.

=cut

use strict;
use warnings;
use Carp qw{cluck};

my $DAYS = 12;
my $SECS_PER_DAY = 24 * 60 * 60;
my @WDAY = qw{Sun Mon Tue Wed Thu Fri Sat};
my @MON  = qw{Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec};


sub makeDate() {
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday) = gmtime();
	sprintf("%s %02d %s %4d %02d:%02d:%02d GMT",
		$WDAY[$wday],
		$mday,
		$MON[$mon],
		$year + 1900,
		$hour,
		$min,
		$sec);
};

sub makeMinHr($$) {
	my ($sec, $includesec) = @_;
	my ($s, $m, $h);

	if (defined $sec) {
		$s = $sec % 60;
		$m = $sec / 60 % 60;
		$h = int ($sec / 60 / 60);
	};
	if ((! defined $h) || ($h > 99)) {
		$h = 99;
		$m = 59;
		$s = 59;
	};

	if ($includesec) {
		if    ($h) { return sprintf ("%2d:%02d:%02d", $h, $m, $s); }
		elsif ($m) { return sprintf (  "   %2d:%02d",     $m, $s); }
		else       { return sprintf (    "      %2d",         $s); };
	} else {
		if    ($h) { return sprintf ("%2d:%02d", $h, $m); }
		else       { return sprintf ( "  :%02d",     $m); };
	};
};
															  
sub build_mlist1_latencystr($) {
	my ($lat) = @_;

	my $str = '?' x $DAYS;
	for my $day (0 .. $DAYS - 1) {
		substr($str, $DAYS - 1 - $day, 1) = 
			(defined $lat->[$day]) ?
			 ($lat->[$day] <    300 ? '#' :
			  ($lat->[$day] <   3600 ? '*' :
			   ($lat->[$day] <  14400 ? '+' :
			    ($lat->[$day] <  86400 ? '-' :
			     ($lat->[$day] < 172800 ? '.' :
			      '_'
			)))))
			: ' ';
	};
	return $str;
}

sub build_mlist2_latencystr($) {
	my ($lat) = @_;

	my $str = '?' x $DAYS;
	for my $day (0 .. $DAYS - 1) {
		substr($str, $DAYS - 1 - $day, 1) = 
			(defined $lat->[$day]) ?
			 ($lat->[$day] <    20*60 ? '0' :
			  ($lat->[$day] <   1*3600 ? '1' :
			   ($lat->[$day] <   2*3600 ? '2' :
			    ($lat->[$day] <   3*3600 ? '3' :
			     ($lat->[$day] <   4*3600 ? '4' :
			      ($lat->[$day] <   5*3600 ? '5' :
			       ($lat->[$day] <   6*3600 ? '6' :
			        ($lat->[$day] <   7*3600 ? '7' :
			         ($lat->[$day] <   8*3600 ? '8' :
			          ($lat->[$day] <   9*3600 ? '9' :
			           ($lat->[$day] <  12*3600 ? 'A' :
			            ($lat->[$day] <  18*3600 ? 'B' :
			             ($lat->[$day] <  24*3600 ? 'C' :
			              ($lat->[$day] <  30*3600 ? 'D' :
			               ($lat->[$day] <  36*3600 ? 'E' :
			                ($lat->[$day] <  42*3600 ? 'F' :
			                 ($lat->[$day] <  48*3600 ? 'G' :
			                  'H'
			)))))))))))))))))
			: '?';
	};
	return $str;
}

sub build_mlist2_reliabilitystr($) {
	my ($rel) = @_;

	my $str = '?' x $DAYS;
	for my $day (0 .. $DAYS - 1) {
		substr($str, $DAYS - 1 - $day, 1) =
			(defined $rel->[$day]) ?
				(($rel->[$day] == 1) ?
				'+' :
				(int ($rel->[$day]*10)))
			: '?';
	};
	return $str;
}

sub build_mlist2_capsstr($) {
	my ($caps) = @_;

	my %caps;
	$caps{'middle'} = ($caps =~ m/\bmiddle\b/i);
	$caps{'post'} = ($caps =~ m/\bpost\b/i) || ($caps =~ m/\banon-post-to\b/i);
	$caps{'mix'} = ($caps =~ m/\bmix\b/i);
	$caps{'remix'} = ($caps =~ m/\bremix\b/i);
	$caps{'remix2'} = ($caps =~ m/\bremix2\b/i);
	$caps{'hybrid'} = ($caps =~ m/\bhybrid\b/i);
	$caps{'repgp2'} = ($caps =~ m/\brepgp2\b/i);
	$caps{'repgp'} = ($caps =~ m/\brepgp\b/i);
	$caps{'pgponly'} = ($caps =~ m/\bpgponly\b/i);
	$caps{'ext'} = ($caps =~ m/\bext\b/i);
	$caps{'max'} = ($caps =~ m/\bmax\b/i);
	$caps{'test'} = ($caps =~ m/\btest\b/i);
	$caps{'latent'} = ($caps =~ m/\blatent\b/i);
	$caps{'ek'} = ($caps =~ m/\bek\b/i);
	$caps{'ekx'} = ($caps =~ m/\bekx\b/i);
	$caps{'esub'} = ($caps =~ m/\besub\b/i);
	$caps{'inflt'} = ($caps =~ m/\binflt\d+\b/i);
	$caps{'rhop'} = ($caps =~ m/\brhop\d+\b/i);
	($caps{'klen'}) = ($caps =~ m/\bklen(\d+)\b/i);

	my $str =
		($caps{'middle'}    ? 'D' : ' ') .
		($caps{'post'}      ? 'P' : ' ') .
		($caps{'remix2'}    ? '2' : ($caps{'remix'} ? 'R' : ($caps{'mix'} ? 'M' : ' ' ))) .
		($caps{'hybrid'}    ? 'H' : ' ') .
		($caps{'repgp2'}    ? '2' : ($caps{'repgp'} ? 'G' : ' ' )) .
		($caps{'pgponly'}   ? 'O' : ' ') .
		($caps{'ext'}       ? 'X' : ' ') .
		($caps{'max'}       ? 'A' : ' ') .
		($caps{'test'}      ? 'T' : ' ') .
		($caps{'latent'}    ? 'L' : ' ') .
		($caps{'ekx'}       ? 'E' : ($caps{'ek'} ? 'e' : ' ' )) .
		($caps{'esub'}      ? 'U' : ' ') .
		($caps{'inflt'}     ? 'I' : ' ') .
		($caps{'rhop'}      ? 'N' : ' ') .
		(defined $caps{'klen'} ?
		 ($caps{'klen'} >= 900 ? '9' : (
		  $caps{'klen'} >= 800 ? '8' : (
		   $caps{'klen'} >= 700 ? '7' : (
		    $caps{'klen'} >= 600 ? '6' : (
		     $caps{'klen'} >= 500 ? '5' : (
		      $caps{'klen'} >= 400 ? '4' : (
		       $caps{'klen'} >= 300 ? '3' : (
		        $caps{'klen'} >= 200 ? '2' : (
		         $caps{'klen'} >= 100 ? '1' : '0'
		 )))))))))
		 : ' ');
	return $str;
}


sub calculate($$) {
	my ($addr, $type) = @_;
	my $now = time();

	my @keys = Echolot::Globals::get()->{'storage'}->get_keys($addr, $type) or 
		carp ("No keys asoziated with $addr, $type"),
		return 0;
	
	my @out;
	my @done;
	
	for my $key (@keys) {
		push @out,  grep {$_      > $now - $DAYS * $SECS_PER_DAY} Echolot::Globals::get()->{'storage'}->get_pings($addr, $type, $key, 'out');
		push @done, grep {$_->[0] > $now - $DAYS * $SECS_PER_DAY} Echolot::Globals::get()->{'storage'}->get_pings($addr, $type, $key, 'done');
	};

	my $latency = 0;
	my $received = 0;
	my $sent = 0;
	my @latency;
	my @received;
	my @sent;
	for my $done (@done) {
		$latency += $done->[1];   $latency [int(($now - $done->[0]) / $SECS_PER_DAY)] += $done->[1];
		$sent ++;                 $sent    [int(($now - $done->[0]) / $SECS_PER_DAY)] ++;
		$received ++;             $received[int(($now - $done->[0]) / $SECS_PER_DAY)] ++;
	};
	$latency /= (scalar @done) if (scalar @done);
	for ( 0 .. $DAYS - 1 ) {
		$latency[$_] /= $received[$_] if ($received[$_]);
	};

	for my $out (@out) { 
		my $p = 0;
		$sent ++;        $sent    [int(($now - $out) / $SECS_PER_DAY)] ++;
		$received += $p; $received[int(($now - $out) / $SECS_PER_DAY)] += $p;
	};
	$received /= $sent if ($sent);
	for ( 0 .. $DAYS - 1 ) {
		$received[$_] /= $sent[$_] if ($sent[$_]);
	};


	my $variance = 0;
	$variance += ($latency - $_->[1]) ** 2 for (@done);
	$variance /= (scalar @done) if (scalar @done);

	my $deviation = sqrt($variance);

	return {
		avr_latency     => $latency,
		avr_reliability => $received,
		latency_day     => \@latency,
		reliability_day => \@received
	};
};



sub build_mlist1($) {
	my ($rems) = @_;

	my $filename = Echolot::Config::get()->{'resultdir'}.'/mlist.txt';
	open(F, '>'.$filename) or
		cluck("Cannot open $filename: $!\n"),
		return 0;
	printf F "Last update: %s\n", makeDate();
	printf F "mixmaster           history  latency  uptime\n";
	printf F "--------------------------------------------\n";

	for my $remailer (@$rems) {
		printf F "%-14s %-12s %8s %6.2f%%\n",
			$remailer->{'nick'},
			build_mlist1_latencystr($remailer->{'stats'}->{'latency_day'}),
			makeMinHr($remailer->{'stats'}->{'avr_latency'}, 1),
			$remailer->{'stats'}->{'avr_reliability'} * 100;
	};
	close (F);
};

sub build_mlist2($) {
	my ($rems) = @_;

	my $filename = Echolot::Config::get()->{'resultdir'}.'/mlist2.txt';
	open(F, '>'.$filename) or
		#cluck("Cannot open $filename: $!\n"),
		#return 0;
	printf F "Stats-Version: 2.0\n";
	printf F "Generated: %s\n", makeDate();
	printf F "Mixmaster    Latent-Hist   Latent  Uptime-Hist   Uptime  Options\n";
	printf F "------------------------------------------------------------------------\n";

	for my $remailer (@$rems) {
		printf F "%-12s %-12s %6s   %-12s  %5.1f%%  %s\n",
			$remailer->{'nick'},
			build_mlist2_latencystr($remailer->{'stats'}->{'latency_day'}),
			makeMinHr($remailer->{'stats'}->{'avr_latency'}, 0),
			build_mlist2_reliabilitystr($remailer->{'stats'}->{'reliability_day'}),
			$remailer->{'stats'}->{'avr_reliability'} * 100,
			build_mlist2_capsstr($remailer->{'caps'});
	};
	close (F);
};


sub build_mlists() {
	my %rems;
	for my $addr (Echolot::Globals::get()->{'storage'}->get_remailers()) {
		next unless Echolot::Globals::get()->{'storage'}->has_type($addr, 'mix');

		$rems{$addr} = {
			'stats' => calculate($addr,'mix'),
			'nick'  => Echolot::Globals::get()->{'storage'}->get_nick($addr),
			'caps'  => Echolot::Globals::get()->{'storage'}->get_capabilities($addr)
			};
	};

	my @rems = map { $rems{$_} }
		sort {
			- $rems{$a}->{'stats'}->{'avr_latency'} <=> $rems{$b}->{'stats'}->{'avr_latency'} ||
			$rems{$a}->{'nick'} cmp $rems{$b}->{'nick'}
			} keys %rems;

	build_mlist1(\@rems);
	build_mlist2(\@rems);
};

sub build() {
	build_mlists();
};

1;
# vim: set ts=4 shiftwidth=4:
