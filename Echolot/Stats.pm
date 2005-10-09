package Echolot::Stats;

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

Echolot::Stats - produce Stats, keyrings et al

=head1 DESCRIPTION

This package provides functions for generating remailer stats,
and keyrings.

=cut

use strict;
use English;
use Echolot::Log;

my $STATS_DAYS;
my $SECONDS_PER_DAY;
my $WEIGHT;

my %LAST_BROKENCHAIN_RUN;
my %BROKEN_CHAINS;

sub make_date() {
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday) = gmtime();
	sprintf("%s %02d %s %4d %02d:%02d:%02d GMT",
		Echolot::Tools::make_dayname($wday),
		$mday,
		Echolot::Tools::make_monthname($mon),
		$year + 1900,
		$hour,
		$min,
		$sec);
};

sub make_min_hr($$) {
	my ($sec, $includesec) = @_;
	my ($s, $m, $h);

	if (defined $sec) {
		$s = $sec % 60;
		$m = $sec / 60 % 60;
		$h = int ($sec / 60 / 60);
	};
	if ((! defined $sec) || ($sec < 0) || ($h > 99)) {
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
															  
sub build_list1_latencystr($) {
	my ($lat) = @_;

	my $str = '?' x $STATS_DAYS;
	for my $day (0 .. $STATS_DAYS - 1) {
		substr($str, $STATS_DAYS - 1 - $day, 1) = 
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

sub build_list2_latencystr($) {
	my ($lat) = @_;

	my $str = '?' x $STATS_DAYS;
	for my $day (0 .. $STATS_DAYS - 1) {
		substr($str, $STATS_DAYS - 1 - $day, 1) = 
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

sub build_list2_reliabilitystr($) {
	my ($rel) = @_;

	my $str = '?' x $STATS_DAYS;
	for my $day (0 .. $STATS_DAYS - 1) {
		substr($str, $STATS_DAYS - 1 - $day, 1) =
			(defined $rel->[$day]) ?
				(($rel->[$day] >= 0.9999) ?
				#(($rel->[$day] == 1) ?
				'+' :
				(int ($rel->[$day]*10)))
			: '?';
	};
	return $str;
}

sub build_list2_capsstr($) {
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

sub median($) {
	my ($arr) = @_;

	my $cnt = scalar @$arr;
	if ($cnt == 0) {
		return undef;
	} elsif ($cnt % 2 == 0) {
		return (($arr->[ int(($cnt - 1 ) / 2) ] + $arr->[ int($cnt / 2) ] ) / 2);
	} else {
		return $arr->[ int(($cnt - 1 ) / 2) ];
	};
};

# how many % (0-1) values of @$lats are greater than $lat.
# $@lats needs to be sorted
sub percentile($$) {
	my ($lat, $lats) = @_;

	my $num = scalar @$lats;
	my $i;
	for ($i=0; $i < $num; $i++) {
		last if $lat < $lats->[$i];
	}
	return ($num - $i) / $num;
}

sub calculate($$) {
	my ($addr, $types) = @_;
	my $now = time();

	my $SKEW_ABS = 15*60;
	my $SKEW_PERCENT = 0.80;

	my @out;
	my @done;
	
	for my $type (@$types) {
		next unless Echolot::Globals::get()->{'storage'}->has_type($addr, $type);
		my @keys = Echolot::Globals::get()->{'storage'}->get_keys($addr, $type);
		for my $key (@keys) {
			push @out,  grep {$_      > $now - $STATS_DAYS * $SECONDS_PER_DAY} Echolot::Globals::get()->{'storage'}->get_pings($addr, $type, $key, 'out');
			push @done, grep {$_->[0] > $now - $STATS_DAYS * $SECONDS_PER_DAY} Echolot::Globals::get()->{'storage'}->get_pings($addr, $type, $key, 'done');
		};
	};

	my @latency_total = map { $_->[1] } @done;
	my @latency_day;
	my $sent_total;
	my $received_total = 0;
	my @sent_day;
	my @received_day;
	for my $done (@done) {
		push @{ $latency_day [int(($now - $done->[0]) / $SECONDS_PER_DAY)] }, $done->[1];
		my $day = int(($now - $done->[0]) / $SECONDS_PER_DAY);
		my $weight = $WEIGHT->[$day];
		$sent_total     += $weight; $sent_day    [$day] ++;
		$received_total += $weight; $received_day[$day] ++;
	};

	@latency_total = sort { $a <=> $b } @latency_total;
	my $latency_median = median (\@latency_total);
	my @latency_median_day;
	for ( 0 .. $STATS_DAYS - 1 ) {
		@{$latency_day[$_]} = defined $latency_day[$_] ? (sort { $a <=> $b } @{$latency_day[$_]}) : ();
		$latency_median_day[$_] = median ( $latency_day[$_] );
	}

	if (scalar @out) {
		my @p = ( scalar @latency_total ) ?
				map { #printf(STDERR "($now - $_ - $SKEW_ABS)/$SKEW_PERCENT   ".
				      #"%s in (%s): %s\n", ($now - $_ - $SKEW_ABS)/$SKEW_PERCENT, join(',', @latency_total), 
				      #percentile( ($now - $_ - $SKEW_ABS)/$SKEW_PERCENT , \@latency_total ));
				      percentile( ($now - $_ - $SKEW_ABS)/$SKEW_PERCENT , \@latency_total ) } @out :
				map { 0 } @out;
		for (my $i=0; $i < scalar @out; $i++) {
			my $day = int(($now - $out[$i]) / $SECONDS_PER_DAY);
			my $weight = $WEIGHT->[$day];
			$sent_total     += $weight;          $sent_day    [$day] ++;
			$received_total += $weight * $p[$i]; $received_day[$day] += $p[$i];
		};
	};
	#printf STDERR "$received_total / %s\n", (defined $sent_total ? $sent_total : 'n/a');
	$received_total /= $sent_total if ($sent_total);
	for ( 0 .. $STATS_DAYS - 1 ) {
		$received_day[$_] /= $sent_day[$_] if ($sent_day[$_]);
	};



	return {
		avr_latency     => $latency_median,
		avr_reliability => $received_total,
		latency_day     => \@latency_median_day,
		reliability_day => \@received_day
	};
};

sub write_file($$$$) {
	my ($filebasename, $html_template, $expires, $output) = @_;

	my $filename = $filebasename.'.txt';
	open(F, '>'.$filename) or
		Echolot::Log::warn("Cannot open $filename: $!."),
		return 0;
	print F $output;
	close (F);
	if (defined $expires) {
		Echolot::Tools::write_meta_information($filename,
			Expires => time + $expires) or
			Echolot::Log::debug ("Error while writing meta information for $filename."),
			return 0;
	};
	return 1 unless defined $html_template;
	
	if (defined $output) {
		$output =~ s/&/&amp;/g;
		$output =~ s/"/&quot;/g;
		$output =~ s/</&lt;/g;
		$output =~ s/>/&gt;/g;
	};
	Echolot::Tools::write_HTML_file($filebasename, $html_template, $expires, list => $output);

	return 1;
};

sub build_mlist1($$$$$;$) {
	my ($rems, $broken1, $broken2, $sameop, $filebasename, $html_template) = @_;

	my $output = '';
	$output .= sprintf "\nGroups of remailers sharing a machine or operator:\n$sameop\n" if (defined $sameop);
	$output .= sprintf "\nBroken type-I remailer chains:\n$broken1\n" if (defined $broken1);
	$output .= sprintf "\nBroken type-II remailer chains:\n$broken2\n" if (defined $broken2);

	$output .= sprintf "Last update: %s\n", make_date();
	$output .= sprintf "mixmaster           history  latency  uptime\n";
	$output .= sprintf "--------------------------------------------\n";

	for my $remailer (@$rems) {
		$output .= sprintf "%-14s %-12s %8s %6.2f%%\n",
			substr($remailer->{'nick'},0,14),
			build_list1_latencystr($remailer->{'stats'}->{'latency_day'}),
			make_min_hr($remailer->{'stats'}->{'avr_latency'}, 1),
			$remailer->{'stats'}->{'avr_reliability'} * 100;
	};

	write_file($filebasename, $html_template, Echolot::Config::get()->{'buildstats'}, $output) or
		Echolot::Log::debug("writefile failed."),
		return 0;
	return 1;
};

sub build_rlist1($$$$$;$) {
	my ($rems, $broken1, $broken2, $sameop, $filebasename, $html_template) = @_;

	my $output = '';
	for my $remailer (sort {$a->{'caps'} cmp $b->{'caps'}} @$rems) {
		$output .= $remailer->{'caps'}."\n"
	}

	$output .= sprintf "\nGroups of remailers sharing a machine or operator:\n$sameop\n" if (defined $sameop);
	$output .= sprintf "\nBroken type-I remailer chains:\n$broken1\n" if (defined $broken1);
	$output .= sprintf "\nBroken type-II remailer chains:\n$broken2\n" if (defined $broken2);

	$output .= sprintf "\n";
	$output .= sprintf "Last update: %s\n", make_date();
	$output .= sprintf "remailer  email address                        history  latency  uptime\n";
	$output .= sprintf "-----------------------------------------------------------------------\n";

	for my $remailer (@$rems) {
		$output .= sprintf "%-8s %-32s %-12s %8s %6.2f%%\n",
			substr($remailer->{'nick'},0,8),
			substr($remailer->{'address'},0,32),
			build_list1_latencystr($remailer->{'stats'}->{'latency_day'}),
			make_min_hr($remailer->{'stats'}->{'avr_latency'}, 1),
			$remailer->{'stats'}->{'avr_reliability'} * 100;
	};


	write_file($filebasename, $html_template, Echolot::Config::get()->{'buildstats'}, $output) or
		Echolot::Log::debug("writefile failed."),
		return 0;
	return 1;
};


sub build_list2($$$$$$;$) {
	my ($rems, $type, $broken1, $broken2, $sameop, $filebasename, $html_template) = @_;

	my $output = '';

	$output .= sprintf "Stats-Version: 2.0\n";
	$output .= sprintf "Generated: %s\n", make_date();
	$output .= sprintf "%-12s Latent-Hist   Latent  Uptime-Hist   Uptime  Options\n", ($type == 1 ? 'Cypherpunk' : $type == 2 ? 'Mixmaster' : "Type $type");
	$output .= sprintf "------------------------------------------------------------------------\n";

	for my $remailer (@$rems) {
		$output .= sprintf "%-12s %-12s %6s   %-12s  %5.1f%%  %s\n",
			substr($remailer->{'nick'},0,12),
			build_list2_latencystr($remailer->{'stats'}->{'latency_day'}),
			make_min_hr($remailer->{'stats'}->{'avr_latency'}, 0),
			build_list2_reliabilitystr($remailer->{'stats'}->{'reliability_day'}),
			$remailer->{'stats'}->{'avr_reliability'} * 100,
			build_list2_capsstr($remailer->{'caps'});
	};

	$output .= sprintf "\nGroups of remailers sharing a machine or operator:\n$sameop\n" if (defined $sameop);
	$output .= sprintf "\nBroken type-I remailer chains:\n$broken1\n" if (defined $broken1);
	$output .= sprintf "\nBroken type-II remailer chains:\n$broken2\n" if (defined $broken2);

	$output .= sprintf "\n\n\nRemailer-Capabilities:\n\n";
	for my $remailer (sort {$a->{'caps'} cmp $b->{'caps'}} @$rems) {
		$output .= $remailer->{'caps'}."\n" if defined $remailer->{'caps'};
	}

	write_file($filebasename, $html_template, Echolot::Config::get()->{'buildstats'}, $output) or
		Echolot::Log::debug("writefile failed."),
		return 0;
	return 1;
};

sub build_clist($$$$$;$) {
	my ($remhash, $broken1, $broken2, $sameop, $filebasename, $html_template) = @_;

	my $output = '';

	$output .= sprintf "Stats-Version: 2.0.1\n";
	$output .= sprintf "Generated: %s\n", make_date();
	$output .= sprintf "Mixmaster    Latent-Hist   Latent  Uptime-Hist   Uptime  Options         Type\n";
	$output .= sprintf "------------------------------------------------------------------------------------\n";

	my $all;
	for my $type (keys %$remhash) {
		for my $remailer (@{$remhash->{$type}}) {
			$all->{ $remailer->{'nick'} }->{$type} = $remailer
		};
	};

	for my $nick (sort {$a cmp $b} keys %$all) {
		for my $type (sort {$a cmp $b} keys %{$all->{$nick}}) {
			$output .= sprintf "%-12s %-12s %6s   %-12s  %5.1f%%  %s %s\n",
				$nick,
				build_list2_latencystr($all->{$nick}->{$type}->{'stats'}->{'latency_day'}),
				make_min_hr($all->{$nick}->{$type}->{'stats'}->{'avr_latency'}, 0),
				build_list2_reliabilitystr($all->{$nick}->{$type}->{'stats'}->{'reliability_day'}),
				$all->{$nick}->{$type}->{'stats'}->{'avr_reliability'} * 100,
				build_list2_capsstr($all->{$nick}->{$type}->{'caps'}),
				$type;
		};
	};

	$output .= sprintf "\nGroups of remailers sharing a machine or operator:\n$sameop\n" if (defined $sameop);
	$output .= sprintf "\nBroken type-I remailer chains:\n$broken1\n" if (defined $broken1);
	$output .= sprintf "\nBroken type-II remailer chains:\n$broken2\n" if (defined $broken2);

	$output .= sprintf "\n\n\nRemailer-Capabilities:\n\n";
	for my $nick (sort {$a cmp $b} keys %$all) {
		for my $type (keys %{$all->{$nick}}) {
			$output .= $all->{$nick}->{$type}->{'caps'}."\n", last if defined $all->{$nick}->{$type}->{'caps'};
		};
	}

	write_file($filebasename, $html_template, Echolot::Config::get()->{'buildstats'}, $output) or
		Echolot::Log::debug("writefile failed."),
		return 0;
	return 1;
};


sub build_rems($) {
	my ($types) = @_;

	my %rems;
	for my $remailer (Echolot::Globals::get()->{'storage'}->get_addresses()) {
		my $addr = $remailer->{'address'};
		my $has_type = 0;
		for my $type (@$types) {
			$has_type = 1, last if (Echolot::Globals::get()->{'storage'}->has_type($addr, $type));
		};
		next unless $has_type;

		my $rem = {
			'stats'    => calculate($addr,$types),
			'nick'     => Echolot::Globals::get()->{'storage'}->get_nick($addr),
			'caps'     => Echolot::Globals::get()->{'storage'}->get_capabilities($addr),
			'address'  => $addr,
			};
		$rem->{'list-it'} = $remailer->{'showit'} && defined $rem->{'caps'} && ($rem->{'caps'} !~ m/\btesting\b/i);
		$rem->{'latency'} = $rem->{'stats'}->{'avr_latency'}; # for sorting purposes only
		$rem->{'latency'} = 9999 unless defined $rem->{'latency'};

		$rems{$addr} = $rem if (defined $rem->{'stats'} && defined $rem->{'nick'} && defined $rem->{'address'} && defined $rem->{'caps'} );
	};

	my $sort_by_latency = Echolot::Config::get()->{'stats_sort_by_latency'};
	my @rems =
		sort {
			- ($a->{'stats'}->{'avr_reliability'} <=> $b->{'stats'}->{'avr_reliability'}) ||
			(($a->{'latency'} <=> $b->{'latency'}) * $sort_by_latency) ||
			($a->{'nick'} cmp $b->{'nick'})
			} map { $rems{$_} } keys %rems;
	
	return \@rems;
};

sub compress_broken_chain($@) {
	my ($num, @list) = @_;

	my %unique = ();
	@list = sort { $a cmp $b} grep { ! $unique{$_}++; } @list;

	my %bad_left;
	my %bad_right;
	for my $chain (@list) {
		chomp $chain;
		my ($left, $right) = $chain =~ m/\((\S+) \s (\S+)\)/x or
			Echolot::Log::warn("Could not parse bad chain '$chain'."),
			next;
		$bad_right{$right}++;
		$bad_right{$right} += $num if ($left  eq '*');
		$bad_left {$left }++;
		$bad_left {$left } += $num if ($right eq '*');
	};


	my $threshold = $num * Echolot::Config::get()->{'chainping_allbad_factor'};
	my @result = ();
	for my $key (keys %bad_right) {
		delete $bad_right{$key}, next if $bad_right{$key} < $threshold;
		push @result, "(* $key)";
	};
	for my $key (keys %bad_left) {
		delete $bad_left{$key}, next if $bad_left{$key} < $threshold;
		push @result, "($key *)";
	};

	for my $chain (@list) {
		chomp $chain;
		my ($left, $right) = $chain =~ m/\((\S+) \s (\S+)\)/x or
			# Echolot::Log::warn("Could not parse bad chain '$chain'."),    -- don't warn again
			push(@result, $chain),
			next;
		next if defined $bad_right{$right};
		next if defined $bad_left {$left };
		push(@result, $chain),
	};

	%unique = ();
	@result = sort { $a cmp $b} grep { ! $unique{$_}++; } @result;

	return @result;
};

sub find_broken_chains($$$) {
	my ($chaintype, $rems, $hard) = @_;

	if (!defined $LAST_BROKENCHAIN_RUN{$chaintype} ||
	    $LAST_BROKENCHAIN_RUN{$chaintype} < time() - Echolot::Config::get()->{'chainping_update'} ||
	    ! defined $BROKEN_CHAINS{$chaintype} ) {
		Echolot::Log::debug ("Broken Chains $chaintype need generating."),
		$LAST_BROKENCHAIN_RUN{$chaintype} = time();

		my $pings = Echolot::Globals::get()->{'storage'}->get_chainpings($chaintype);
		my @intensive_care = ();
		my %remailers = map { $_->{'address'} => $_ } @$rems;

		my $stats;
		my %received;
		my @broken_chains;
		for my $status (qw{done out}) {
			my $status_done = $status eq 'done';
			my $status_out = $status eq 'out';
			for my $ping (@{$pings->{$status}}) {
				my $addr1 = $ping->{'addr1'};
				my $addr2 = $ping->{'addr2'};
				my $sent  = $ping->{'sent'};
				next if $sent < (time() - Echolot::Config::get()->{'chainping_period'});
				next unless defined $remailers{$addr1};
				next unless defined $remailers{$addr2};

				if ($status_done) {
					$received{$addr1.':'.$addr2.':'.$sent} = 1;
				};
				if ($status_out && !defined $received{$addr1.':'.$addr2.':'.$sent}) {
					my $lat1 = $remailers{$addr1}->{'stats'}->{'avr_latency'};
					my $lat2 = $remailers{$addr2}->{'stats'}->{'avr_latency'};
					$lat1 = 0 unless defined $lat1;
					$lat2 = 0 unless defined $lat2;
					my $theoretical_lat = $lat1 + $lat2;
					$theoretical_lat = 0 unless defined $theoretical_lat;
					my $latency = time() - $ping->{'sent'};
					# print ("lat helps $latency < ".int($theoretical_lat * Echolot::Config::get()->{'chainping_grace'})."  $addr1 $addr2\n"),
					next if ($latency < $theoretical_lat * Echolot::Config::get()->{'chainping_grace'});
				};

				# print "Having $addr1 $addr2 $status at $sent\n";
				$stats->{$addr1}->{$addr2}->{$status}++;
			};
		};
		# require Data::Dumper;
		# print Data::Dumper->Dump([$stats]);
		for my $addr1 (keys %$stats) {
			for my $addr2 (keys %{$stats->{$addr1}}) {
				my $theoretical_rel = $remailers{$addr1}->{'stats'}->{'avr_reliability'} *
						      $remailers{$addr2}->{'stats'}->{'avr_reliability'};
				my $out = $stats->{$addr1}->{$addr2}->{'out'};
				my $done = $stats->{$addr1}->{$addr2}->{'done'};
				$done = 0 unless defined $done;
				($out < Echolot::Config::get()->{'chainping_minsample'} && $done == 0) and
					push (@intensive_care, { addr1 => $addr1, addr2 => $addr2, reason => "only $out sample".($out>1?'s':'').", none returned so far" }),
					next;
				($out > 0) or
					Echolot::Log::debug("Should not devide through zero ($done/$out) for $addr1, $addr2."),
					next;
				my $real_rel = $done / $out;
				# print "$addr1 $addr2 $done / $out == $real_rel ($theoretical_rel)\n";
				next if ($real_rel > $theoretical_rel * Echolot::Config::get()->{'chainping_fudge'});
				my $nick1 = $remailers{$addr1}->{'nick'};
				my $nick2 = $remailers{$addr2}->{'nick'};
				push @broken_chains,
					{ public => $remailers{$addr1}->{'list-it'} && $remailers{$addr2}->{'list-it'},
					  chain => "($nick1 $nick2)" };
				push @intensive_care, { addr1 => $addr1, addr2 => $addr2, reason => "bad: $done/$out" };
			};
		};
		$BROKEN_CHAINS{$chaintype} = \@broken_chains;
		Echolot::Chain::set_intensive_care($chaintype, \@intensive_care);
	} else {
		Echolot::Log::debug ("Broken Chains $chaintype are up to date."),
	};

	my @hard = defined $hard ? (split /\n/, $hard) : ();
	my @pub = @hard;
	my @priv = @hard;
	push @pub,  map { $_->{'chain'} } grep { $_->{'public'} } @{ $BROKEN_CHAINS{$chaintype} };
	push @priv, map { $_->{'chain'} }                         @{ $BROKEN_CHAINS{$chaintype} };

	my $pub = join "\n", compress_broken_chain(scalar @$rems, @pub);
	my $priv = join "\n", compress_broken_chain(scalar @$rems, @priv);

	return ($pub, $priv);
};

sub build_lists() {

	my $clist;
	my $pubclist;
	my $rems;
	my $pubrems;

	my %stats;
	my %addresses;

	my $hardbroken1 = Echolot::Tools::read_file( Echolot::Config::get()->{'broken1'}, 1);
	my $hardbroken2 = Echolot::Tools::read_file( Echolot::Config::get()->{'broken2'}, 1);
	my $sameop = Echolot::Tools::read_file( Echolot::Config::get()->{'sameop'}, 1);
	my $pubbroken1;
	my $pubbroken2;
	my $privbroken1;
	my $privbroken2;

	my $mixrems = build_rems(['mix']);
	my $cpunkrems = build_rems(['cpunk-rsa', 'cpunk-dsa', 'cpunk-clear']);

	if (Echolot::Config::get()->{'do_chainpings'}) {
		($pubbroken1, $privbroken1) = find_broken_chains('cpunk', $cpunkrems, $hardbroken1);
		($pubbroken2, $privbroken2) = find_broken_chains('mix'  , $mixrems  , $hardbroken2);
	} else {
		$pubbroken1 = $privbroken1 = $hardbroken1;
		$pubbroken2 = $privbroken2 = $hardbroken2;
	};

	unless (Echolot::Config::get()->{'show_chainpings'}) {
		$pubbroken1 = $hardbroken1;
		$pubbroken2 = $hardbroken2;
	};

	$rems = $mixrems;
	$mixrems = undef;
	@$pubrems = grep { $_->{'list-it'} } @$rems;
	build_mlist1( $rems, $privbroken1, $privbroken2, $sameop, Echolot::Config::get()->{'private_resultdir'}.'/'.'mlist', 'mlist');
	build_list2( $rems, 2, $privbroken1, $privbroken2, $sameop, Echolot::Config::get()->{'private_resultdir'}.'/'.'mlist2', 'mlist2');
	build_mlist1( $pubrems, $pubbroken1, $pubbroken2, $sameop, Echolot::Config::get()->{'resultdir'}.'/'.'mlist', 'mlist');
	build_list2( $pubrems, 2, $pubbroken1, $pubbroken2, $sameop, Echolot::Config::get()->{'resultdir'}.'/'.'mlist2', 'mlist2');
	$stats{'mix_total'} = scalar @$pubrems;
	$stats{'mix_98'} = scalar grep { $_->{'stats'}->{'avr_reliability'} >= 0.98 } @$pubrems;
	$addresses{$_->{'address'}}=1 for @$pubrems;
	if (Echolot::Config::get()->{'combined_list'}) {
		$clist->{'mix'} = $rems;
		$pubclist->{'mix'} = $pubrems; $pubrems = undef;
	};

	$rems = $cpunkrems;
	$cpunkrems = undef;
	@$pubrems = grep { $_->{'list-it'} } @$rems;
	build_rlist1( $rems, $privbroken1, $privbroken2, $sameop, Echolot::Config::get()->{'private_resultdir'}.'/'.'rlist', 'rlist');
	build_list2( $rems, 1, $privbroken1, $privbroken2, $sameop,  Echolot::Config::get()->{'private_resultdir'}.'/'.'rlist2', 'rlist2');
	build_rlist1( $pubrems, $pubbroken1, $pubbroken2, $sameop, Echolot::Config::get()->{'resultdir'}.'/'.'rlist', 'rlist');
	build_list2( $pubrems, 1, $pubbroken1, $pubbroken2, $sameop, Echolot::Config::get()->{'resultdir'}.'/'.'rlist2', 'rlist2');
	$stats{'cpunk_total'} = scalar @$pubrems;
	$stats{'cpunk_98'} = scalar grep { $_->{'stats'}->{'avr_reliability'} >= 0.98 } @$pubrems;
	$addresses{$_->{'address'}}=1 for @$pubrems;
	if (Echolot::Config::get()->{'combined_list'} && ! Echolot::Config::get()->{'separate_rlists'}) {
		$clist->{'cpunk'} = $rems;
		$pubclist->{'cpunk'} = $pubrems; $pubrems = undef;
	};

	if (Echolot::Config::get()->{'separate_rlists'}) {
		$rems = build_rems(['cpunk-rsa']);
		@$pubrems = grep { $_->{'list-it'} } @$rems;
		build_rlist1( $rems, $privbroken1, $privbroken2, $sameop, Echolot::Config::get()->{'private_resultdir'}.'/'.'rlist-rsa', 'rlist-rsa');
		build_list2( $rems, 1, $privbroken1, $privbroken2, $sameop, Echolot::Config::get()->{'private_resultdir'}.'/'.'rlist2-rsa', 'rlist2-rsa');
		build_rlist1( $pubrems, $pubbroken1, $pubbroken2, $sameop, Echolot::Config::get()->{'resultdir'}.'/'.'rlist-rsa', 'rlist-rsa');
		build_list2( $pubrems, 1, $pubbroken1, $pubbroken2, $sameop, Echolot::Config::get()->{'resultdir'}.'/'.'rlist2-rsa', 'rlist2-rsa');
		if (Echolot::Config::get()->{'combined_list'}) {
			$clist->{'cpunk-rsa'} = $rems;
			$pubclist->{'cpunk-rsa'} = $pubrems; $pubrems = undef;
		};

		$rems = build_rems(['cpunk-dsa']);
		@$pubrems = grep { $_->{'list-it'} } @$rems;
		build_rlist1( $rems, $privbroken1, $privbroken2, $sameop, Echolot::Config::get()->{'private_resultdir'}.'/'.'rlist-dsa', 'rlist-dsa');
		build_list2( $rems, 1, $privbroken1, $privbroken2, $sameop, Echolot::Config::get()->{'private_resultdir'}.'/'.'rlist2-dsa', 'rlist2-dsa');
		build_rlist1( $pubrems, $pubbroken1, $pubbroken2, $sameop, Echolot::Config::get()->{'resultdir'}.'/'.'rlist-dsa', 'rlist-dsa');
		build_list2( $pubrems, 1, $pubbroken1, $pubbroken2, $sameop, Echolot::Config::get()->{'resultdir'}.'/'.'rlist2-dsa', 'rlist2-dsa');
		if (Echolot::Config::get()->{'combined_list'}) {
			$clist->{'cpunk-dsa'} = $rems;
			$pubclist->{'cpunk-dsa'} = $pubrems; $pubrems = undef;
		};

		$rems = build_rems(['cpunk-clear']);
		@$pubrems = grep { $_->{'list-it'} } @$rems;
		build_rlist1( $rems, $privbroken1, $privbroken2, $sameop, Echolot::Config::get()->{'private_resultdir'}.'/'.'rlist-clear', 'rlist-clear');
		build_list2( $rems, 1, $privbroken1, $privbroken2, $sameop, Echolot::Config::get()->{'private_resultdir'}.'/'.'rlist2-clear', 'rlist2-clear');
		build_rlist1( $pubrems, $pubbroken1, $pubbroken2, $sameop, Echolot::Config::get()->{'resultdir'}.'/'.'rlist-clear', 'rlist-clear');
		build_list2( $pubrems, 1, $pubbroken1, $pubbroken2, $sameop, Echolot::Config::get()->{'resultdir'}.'/'.'rlist2-clear', 'rlist2-clear');
		if (Echolot::Config::get()->{'combined_list'}) {
			$clist->{'cpunk-clear'} = $rems;
			$pubclist->{'cpunk-clear'} = $pubrems; $pubrems = undef;
		};
	};
	if (Echolot::Config::get()->{'combined_list'}) {
		build_clist( $clist, $privbroken1, $privbroken2, $sameop, Echolot::Config::get()->{'private_resultdir'}.'/'.'clist', 'clist');
		build_clist( $pubclist, $pubbroken1, $pubbroken2, $sameop, Echolot::Config::get()->{'resultdir'}.'/'.'clist', 'clist');
	};

	$stats{'unique_addresses'} = scalar keys %addresses;
	Echolot::Tools::write_HTML_file(
		Echolot::Config::get()->{'resultdir'}.'/'.Echolot::Config::get()->{'indexfilebasename'},
		'indexfile',
		Echolot::Config::get()->{'buildstats'},
		%stats );
	
	my $file = Echolot::Config::get()->{'echolot_css'},
	my $css;
	{
		local $/ = undef;
		open(F, $file) or
			Echolot::Log::warn("Could not open $file: $!."),
			return 0;
		$css = <F>;
		close (F) or
			Echolot::Log::warn("Cannot close $file: $!."),
			return 0;
	}
	$file = Echolot::Config::get()->{'resultdir'}.'/echolot.css';
	open(F, '>'.$file) or
		Echolot::Log::warn("Cannot open $file: $!."),
		return 0;
	print F $css or
		Echolot::Log::warn("Cannot print to $file: $!."),
		return 0;
	close (F) or
		Echolot::Log::warn("Cannot close $file: $!."),
		return 0;

};


sub build_mixring() {
	my @filenames;

	my $filename = Echolot::Config::get()->{'resultdir'}.'/pubring.mix';
	push @filenames, $filename;
	open(F, '>'.$filename) or
		Echolot::Log::warn("Cannot open $filename: $!."),
		return 0;
	$filename = Echolot::Config::get()->{'resultdir'}.'/type2.list';
	push @filenames, $filename;
	open(T2L, '>'.$filename) or
		Echolot::Log::warn("Cannot open $filename: $!."),
		return 0;
	$filename = Echolot::Config::get()->{'private_resultdir'}.'/pubring.mix';
	push @filenames, $filename;
	open(F_PRIV, '>'.$filename) or
		Echolot::Log::warn("Cannot open $filename: $!."),
		return 0;
	$filename = Echolot::Config::get()->{'private_resultdir'}.'/type2.list';
	push @filenames, $filename;
	open(T2L_PRIV, '>'.$filename) or
		Echolot::Log::warn("Cannot open $filename: $!."),
		return 0;

	my $data;
	for my $remailer (Echolot::Globals::get()->{'storage'}->get_addresses()) {
		my $addr = $remailer->{'address'};
		next unless Echolot::Globals::get()->{'storage'}->has_type($addr, 'mix');

		my %key;
		for my $keyid (Echolot::Globals::get()->{'storage'}->get_keys($addr, 'mix')) {
			my %new_key = Echolot::Globals::get()->{'storage'}->get_key($addr, 'mix', $keyid);

			if (!defined $key{'last_update'} || $key{'last_update'} < $new_key{'last_update'} ) {
				%key = %new_key;
			};
		};

		my $caps = Echolot::Globals::get()->{'storage'}->get_capabilities($addr);
		$key{'list-it'} = $remailer->{'showit'} && defined $caps && ($caps !~ m/\btesting\b/i);
		if ( defined Echolot::Globals::get()->{'storage'}->get_nick($addr) ) {
			$data->{$key{'summary'}} = \%key;
			$data->{$key{'summary'}} = \%key;
		};
	};

	for my $indx (sort {$a cmp $b} keys %$data) {
		my $key = $data->{$indx};
		if ($key->{'list-it'}) {
			print F $key->{'summary'}."\n\n";
			print F $key->{'key'},"\n\n";
			print T2L $key->{'summary'},"\n";
		};
		print F_PRIV $key->{'summary'}."\n\n";
		print F_PRIV $key->{'key'},"\n\n";
		print T2L_PRIV $key->{'summary'},"\n";
	};

	close(F);
	close(T2L);
	close(F_PRIV);
	close(T2L_PRIV);

	for my $filename (@filenames) {
		Echolot::Tools::write_meta_information($filename,
			Expires => time + Echolot::Config::get()->{'buildkeys'}) or
			Echolot::Log::debug ("Error while writing meta information for $filename."),
			return 0;
	};
};



sub build_pgpring_type($$$$) {
	my ($type, $GnuPG, $keyring, $keyids) = @_;
	
	for my $remailer (Echolot::Globals::get()->{'storage'}->get_addresses()) {
		my $addr = $remailer->{'address'};
		next unless Echolot::Globals::get()->{'storage'}->has_type($addr, $type);

		my %key;
		my $final_keyid;
		for my $keyid (Echolot::Globals::get()->{'storage'}->get_keys($addr, $type)) {
			my %new_key = Echolot::Globals::get()->{'storage'}->get_key($addr, $type, $keyid);

			if (!defined $key{'last_update'} || $key{'last_update'} < $new_key{'last_update'} ) {
				%key = %new_key;
				$final_keyid = $keyid;
			};
		};

		# only if we have a conf
		if ( defined Echolot::Globals::get()->{'storage'}->get_nick($addr) ) {
			my ( $stdin_fh, $stdout_fh, $stderr_fh, $status_fh, $handles ) = Echolot::Tools::make_gpg_fds();
			my $pid = $GnuPG->wrap_call(
				commands     => [ '--import' ],
				command_args => [qw{--no-options --no-secmem-warning --no-default-keyring --fast-list-mode --keyring}, $keyring, '--', '-' ],
				handles      => $handles );
			my ($stdout, $stderr, $status) = Echolot::Tools::readwrite_gpg($key{'key'}, $stdin_fh, $stdout_fh, $stderr_fh, $status_fh);
			waitpid $pid, 0;

			($stdout eq '') or
				Echolot::Log::info("GnuPG returned something in stdout '$stdout' while adding key for '$addr': So what?");
			# See DETAIL.gz in GnuPG's doc directory for syntax of GnuPG status
			my ($count, $count_imported) = $status =~ /^\[GNUPG:\] IMPORT_RES (\d+) \d+ (\d+)/m;
			if ($count_imported > 1) {
				Echolot::Log::info("GnuPG status '$status' indicates more than one key for '$addr' imported. Ignoring.");
			} elsif ($count_imported < 1) {
				Echolot::Log::info("GnuPG status '$status' didn't indicate key for '$addr' was imported correctly. Ignoring.");
			};
			my $caps = Echolot::Globals::get()->{'storage'}->get_capabilities($addr);
			$keyids->{$final_keyid} = $remailer->{'showit'} && defined $caps && ($caps !~ m/\btesting\b/i);
		};
	};
	
	return 1;
};

sub build_pgpring_export($$$$) {
	my ($GnuPG, $keyring, $file, $keyids) = @_;

	my ( $stdin_fh, $stdout_fh, $stderr_fh, $status_fh, $handles ) = Echolot::Tools::make_gpg_fds();
	my $pid = $GnuPG->wrap_call(
		commands     => [ '--export' ],
		command_args => [qw{--no-options --no-secmem-warning --no-default-keyring --keyring}, $keyring, @$keyids ],
		handles      => $handles );
	my ($stdout, $stderr, $status) = Echolot::Tools::readwrite_gpg('', $stdin_fh, $stdout_fh, $stderr_fh, $status_fh);
	waitpid $pid, 0;

	open (F, ">$file") or
		Echolot::Log::warn ("Cannot open '$file': $!."),
		return 0;
	print F $stdout;
	close F;

	Echolot::Tools::write_meta_information($file,
		Expires => time + Echolot::Config::get()->{'buildkeys'}) or
		Echolot::Log::debug ("Error while writing meta information for $file."),
		return 0;

	return 1;
};

sub build_pgpring() {
	my $GnuPG = new GnuPG::Interface;
	$GnuPG->call( Echolot::Config::get()->{'gnupg'} ) if (Echolot::Config::get()->{'gnupg'});
	$GnuPG->options->hash_init( 
		armor   => 1,
		homedir => Echolot::Config::get()->{'gnupghome'} );
	$GnuPG->options->meta_interactive( 0 );

    my $keyring = Echolot::Config::get()->{'tmpdir'}.'/'.
	        Echolot::Globals::get()->{'hostname'}.".".time.'.'.$PROCESS_ID.'_'.Echolot::Globals::get()->{'internalcounter'}++.'.keyring';
	

	my $keyids = {};
	build_pgpring_type('cpunk-rsa', $GnuPG, $keyring, $keyids) or
		Echolot::Log::debug("build_pgpring_type failed."),
		return undef;

	build_pgpring_export($GnuPG, $keyring, Echolot::Config::get()->{'resultdir'}.'/pgp-rsa.asc', [ grep {$keyids->{$_}} keys %$keyids ]) or
		Echolot::Log::debug("build_pgpring_export failed."),
		return undef;
	
	build_pgpring_export($GnuPG, $keyring, Echolot::Config::get()->{'private_resultdir'}.'/pgp-rsa.asc', [ keys %$keyids ]) or
		Echolot::Log::debug("build_pgpring_export failed."),
		return undef;
	
	build_pgpring_type('cpunk-dsa', $GnuPG, $keyring, $keyids) or
		Echolot::Log::debug("build_pgpring_type failed."),
		return undef;

	build_pgpring_export($GnuPG, $keyring, Echolot::Config::get()->{'resultdir'}.'/pgp-all.asc', [ grep {$keyids->{$_}} keys %$keyids ]) or
		Echolot::Log::debug("build_pgpring_export failed."),
		return undef;
	
	build_pgpring_export($GnuPG, $keyring, Echolot::Config::get()->{'private_resultdir'}.'/pgp-all.asc', [ keys %$keyids ]) or
		Echolot::Log::debug("build_pgpring_export failed."),
		return undef;
	

	unlink ($keyring) or
		Echolot::Log::warn("Cannot unlink tmp keyring '$keyring'."),
		return undef;
	unlink ($keyring.'~'); # gnupg does those evil backups
};

sub build_stats() {
	$STATS_DAYS = Echolot::Config::get()->{'stats_days'};
	$SECONDS_PER_DAY = Echolot::Config::get()->{'seconds_per_day'};
	$WEIGHT = Echolot::Config::get()->{'pings_weight'};
	build_lists();
};
sub build_keys() {
	build_mixring();
	build_pgpring();
};

1;
# vim: set ts=4 shiftwidth=4:
