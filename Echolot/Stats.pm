package Echolot::Stats;

# (c) 2002 Peter Palfrader <peter@palfrader.org>
# $Id: Stats.pm,v 1.38 2003/01/14 05:25:35 weasel Exp $
#

=pod

=head1 Name

Echolot::Stats - produce Stats, keyrings et al

=head1 DESCRIPTION

This package provides functions for generating remailer stats,
and keyrings.

=cut

use strict;
use constant DAYS => 12;
use constant SECS_PER_DAY => 24 * 60 * 60;
use English;
use Echolot::Log;

use Statistics::Distrib::Normal qw{};

my $NORMAL = new Statistics::Distrib::Normal;
$NORMAL->mu(0);
$NORMAL->sigma(1);

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

	my $str = '?' x DAYS;
	for my $day (0 .. DAYS - 1) {
		substr($str, DAYS - 1 - $day, 1) = 
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

	my $str = '?' x DAYS;
	for my $day (0 .. DAYS - 1) {
		substr($str, DAYS - 1 - $day, 1) = 
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

	my $str = '?' x DAYS;
	for my $day (0 .. DAYS - 1) {
		substr($str, DAYS - 1 - $day, 1) =
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


sub calculate($$) {
	my ($addr, $types) = @_;
	my $now = time();

	my @out;
	my @done;
	
	for my $type (@$types) {
		next unless Echolot::Globals::get()->{'storage'}->has_type($addr, $type);
		my @keys = Echolot::Globals::get()->{'storage'}->get_keys($addr, $type);
		for my $key (@keys) {
			push @out,  grep {$_      > $now - DAYS * SECS_PER_DAY} Echolot::Globals::get()->{'storage'}->get_pings($addr, $type, $key, 'out');
			push @done, grep {$_->[0] > $now - DAYS * SECS_PER_DAY} Echolot::Globals::get()->{'storage'}->get_pings($addr, $type, $key, 'done');
		};
	};

	my $latency = 0;
	my $received = 0;
	my $sent = 0;
	my @latency;
	my @received;
	my @sent;
	for my $done (@done) {
		$latency += $done->[1];   $latency [int(($now - $done->[0]) / SECS_PER_DAY)] += $done->[1];
		$sent ++;                 $sent    [int(($now - $done->[0]) / SECS_PER_DAY)] ++;
		$received ++;             $received[int(($now - $done->[0]) / SECS_PER_DAY)] ++;
	};
	$latency /= (scalar @done) if (scalar @done);
	$latency = undef unless (scalar @done);
	for ( 0 .. DAYS - 1 ) {
		$latency[$_] /= $received[$_] if ($received[$_]);
	};

	my $variance = 0;
	$variance += ($latency - $_->[1]) ** 2 for (@done);
	$variance /= (scalar @done) if (scalar @done);

	my $deviation = sqrt($variance);

	if (scalar @out) {
		my @p = 
			($deviation != 0) ?
				$NORMAL->utp( map { ($now - $_ - $latency) / $deviation } @out ) :
				map { 0 } @out;
		for (my $i=0; $i < scalar @out; $i++) {
			$sent ++;            $sent    [int(($now - $out[$i]) / SECS_PER_DAY)] ++;
			$received += $p[$i]; $received[int(($now - $out[$i]) / SECS_PER_DAY)] += $p[$i];
		};
	};
	$received /= $sent if ($sent);
	for ( 0 .. DAYS - 1 ) {
		$received[$_] /= $sent[$_] if ($sent[$_]);
	};



	return {
		avr_latency     => $latency,
		avr_reliability => $received,
		latency_day     => \@latency,
		reliability_day => \@received
	};
};

sub read_file($;$) {
	my ($name, $fail_ok) = @_;

	unless (open (F, $name)) {
		Echolot::Log::warn("Could not open '$name': $!.") unless ($fail_ok);
		return undef;
	};
	local $/ = undef;
	my $result = <F>;
	close (F);

	return $result;
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
	for my $remailer (Echolot::Globals::get()->{'storage'}->get_remailers()) {
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
			'showit'   => $remailer->{'showit'}
			};
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

sub build_lists() {

	my $clist;
	my $pubclist;
	my $rems;
	my $pubrems;

	my %stats;
	my %addresses;

	my $broken1 = read_file( Echolot::Config::get()->{'broken1'}, 1);
	my $broken2 = read_file( Echolot::Config::get()->{'broken2'}, 1);
	my $sameop = read_file( Echolot::Config::get()->{'sameop'}, 1);

	$rems = build_rems(['mix']);
	@$pubrems = grep { $_->{'showit'} } @$rems;
	build_mlist1( $rems, $broken1, $broken2, $sameop, Echolot::Config::get()->{'private_resultdir'}.'/'.'mlist', 'mlist');
	build_list2( $rems, 2, $broken1, $broken2, $sameop, Echolot::Config::get()->{'private_resultdir'}.'/'.'mlist2', 'mlist2');
	build_mlist1( $pubrems, $broken1, $broken2, $sameop, Echolot::Config::get()->{'resultdir'}.'/'.'mlist', 'mlist');
	build_list2( $pubrems, 2, $broken1, $broken2, $sameop, Echolot::Config::get()->{'resultdir'}.'/'.'mlist2', 'mlist2');
	$stats{'mix_total'} = scalar @$pubrems;
	$stats{'mix_98'} = scalar grep { $_->{'stats'}->{'avr_reliability'} >= 0.98 } @$pubrems;
	$addresses{$_->{'address'}}=1 for @$pubrems;
	if (Echolot::Config::get()->{'combined_list'}) {
		$clist->{'mix'} = $rems;
		$pubclist->{'mix'} = $pubrems; $pubrems = undef;
	};

	$rems = build_rems(['cpunk-rsa', 'cpunk-dsa', 'cpunk-clear']);
	@$pubrems = grep { $_->{'showit'} } @$rems;
	build_rlist1( $rems, $broken1, $broken2, $sameop, Echolot::Config::get()->{'private_resultdir'}.'/'.'rlist', 'rlist');
	build_list2( $rems, 1, $broken1, $broken2, $sameop,  Echolot::Config::get()->{'private_resultdir'}.'/'.'rlist2', 'rlist2');
	build_rlist1( $pubrems, $broken1, $broken2, $sameop, Echolot::Config::get()->{'resultdir'}.'/'.'rlist', 'rlist');
	build_list2( $pubrems, 1, $broken1, $broken2, $sameop, Echolot::Config::get()->{'resultdir'}.'/'.'rlist2', 'rlist2');
	$stats{'cpunk_total'} = scalar @$pubrems;
	$stats{'cpunk_98'} = scalar grep { $_->{'stats'}->{'avr_reliability'} >= 0.98 } @$pubrems;
	$addresses{$_->{'address'}}=1 for @$pubrems;
	if (Echolot::Config::get()->{'combined_list'} && ! Echolot::Config::get()->{'separate_rlists'}) {
		$clist->{'cpunk'} = $rems;
		$pubclist->{'cpunk'} = $pubrems; $pubrems = undef;
	};

	if (Echolot::Config::get()->{'separate_rlists'}) {
		$rems = build_rems(['cpunk-rsa']);
		@$pubrems = grep { $_->{'showit'} } @$rems;
		build_rlist1( $rems, $broken1, $broken2, $sameop, Echolot::Config::get()->{'private_resultdir'}.'/'.'rlist-rsa', 'rlist-rsa');
		build_list2( $rems, 1, $broken1, $broken2, $sameop, Echolot::Config::get()->{'private_resultdir'}.'/'.'rlist2-rsa', 'rlist2-rsa');
		build_rlist1( $pubrems, $broken1, $broken2, $sameop, Echolot::Config::get()->{'resultdir'}.'/'.'rlist-rsa', 'rlist-rsa');
		build_list2( $pubrems, 1, $broken1, $broken2, $sameop, Echolot::Config::get()->{'resultdir'}.'/'.'rlist2-rsa', 'rlist2-rsa');
		if (Echolot::Config::get()->{'combined_list'}) {
			$clist->{'cpunk-rsa'} = $rems;
			$pubclist->{'cpunk-rsa'} = $pubrems; $pubrems = undef;
		};

		$rems = build_rems(['cpunk-dsa']);
		@$pubrems = grep { $_->{'showit'} } @$rems;
		build_rlist1( $rems, $broken1, $broken2, $sameop, Echolot::Config::get()->{'private_resultdir'}.'/'.'rlist-dsa', 'rlist-dsa');
		build_list2( $rems, 1, $broken1, $broken2, $sameop, Echolot::Config::get()->{'private_resultdir'}.'/'.'rlist2-dsa', 'rlist2-dsa');
		build_rlist1( $pubrems, $broken1, $broken2, $sameop, Echolot::Config::get()->{'resultdir'}.'/'.'rlist-dsa', 'rlist-dsa');
		build_list2( $pubrems, 1, $broken1, $broken2, $sameop, Echolot::Config::get()->{'resultdir'}.'/'.'rlist2-dsa', 'rlist2-dsa');
		if (Echolot::Config::get()->{'combined_list'}) {
			$clist->{'cpunk-dsa'} = $rems;
			$pubclist->{'cpunk-dsa'} = $pubrems; $pubrems = undef;
		};

		$rems = build_rems(['cpunk-clear']);
		@$pubrems = grep { $_->{'showit'} } @$rems;
		build_rlist1( $rems, $broken1, $broken2, $sameop, Echolot::Config::get()->{'private_resultdir'}.'/'.'rlist-clear', 'rlist-clear');
		build_list2( $rems, 1, $broken1, $broken2, $sameop, Echolot::Config::get()->{'private_resultdir'}.'/'.'rlist2-clear', 'rlist2-clear');
		build_rlist1( $pubrems, $broken1, $broken2, $sameop, Echolot::Config::get()->{'resultdir'}.'/'.'rlist-clear', 'rlist-clear');
		build_list2( $pubrems, 1, $broken1, $broken2, $sameop, Echolot::Config::get()->{'resultdir'}.'/'.'rlist2-clear', 'rlist2-clear');
		if (Echolot::Config::get()->{'combined_list'}) {
			$clist->{'cpunk-clear'} = $rems;
			$pubclist->{'cpunk-clear'} = $pubrems; $pubrems = undef;
		};
	};
	if (Echolot::Config::get()->{'combined_list'}) {
		build_clist( $clist, $broken1, $broken2, $sameop, Echolot::Config::get()->{'private_resultdir'}.'/'.'clist', 'clist');
		build_clist( $pubclist, $broken1, $broken2, $sameop, Echolot::Config::get()->{'resultdir'}.'/'.'clist', 'clist');
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
	for my $remailer (Echolot::Globals::get()->{'storage'}->get_remailers()) {
		my $addr = $remailer->{'address'};
		next unless Echolot::Globals::get()->{'storage'}->has_type($addr, 'mix');

		my %key;
		for my $keyid (Echolot::Globals::get()->{'storage'}->get_keys($addr, 'mix')) {
			my %new_key = Echolot::Globals::get()->{'storage'}->get_key($addr, 'mix', $keyid);

			if (!defined $key{'last_update'} || $key{'last_update'} < $new_key{'last_update'} ) {
				%key = %new_key;
			};
		};

		$key{'showit'} = $remailer->{'showit'};
		if ( defined Echolot::Globals::get()->{'storage'}->get_nick($addr) ) {
			$data->{$key{'summary'}} = \%key;
			$data->{$key{'summary'}} = \%key;
		};
	};

	for my $indx (sort {$a cmp $b} keys %$data) {
		my $key = $data->{$indx};
		if ($key->{'showit'}) {
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
	
	for my $remailer (Echolot::Globals::get()->{'storage'}->get_remailers()) {
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
			my ( $stdin_fh, $stdout_fh, $stderr_fh, $status_fh )
				= ( IO::Handle->new(),
				IO::Handle->new(),
				IO::Handle->new(),
				IO::Handle->new(),
				);
			my $handles = GnuPG::Handles->new (
				stdin      => $stdin_fh,
				stdout     => $stdout_fh,
				stderr     => $stderr_fh,
				status     => $status_fh
				);
			my $pid = $GnuPG->wrap_call(
				commands     => [ '--import' ],
				command_args => [qw{--no-options --no-secmem-warning --no-default-keyring --fast-list-mode --keyring}, $keyring, '--', '-' ],
				handles      => $handles );
			print $stdin_fh $key{'key'};
			close($stdin_fh);

			my $stdout = join '', <$stdout_fh>; close($stdout_fh);
			my $stderr = join '', <$stderr_fh>; close($stderr_fh);
			my $status = join '', <$status_fh>; close($status_fh);

			waitpid $pid, 0;

			($stdout eq '') or
				Echolot::Log::info("GnuPG returned something in stdout '$stdout' while adding key for '$addr': So what?");
			unless ($status =~ /^^\[GNUPG:\] IMPORTED /m) {
				if ($status =~ /^^\[GNUPG:\] IMPORT_RES /m) {
					Echolot::Log::info("GnuPG status '$status' indicates more than one  key for '$addr' imported. Ignoring.");
				} else {
					Echolot::Log::info("GnuPG status '$status' didn't indicate key for '$addr' was imported correctly. Ignoring.");
				};
			};
			$keyids->{$final_keyid} = $remailer->{'showit'};
		};
	};
	
	return 1;
};

sub build_pgpring_export($$$$) {
	my ($GnuPG, $keyring, $file, $keyids) = @_;

	my ( $stdin_fh, $stdout_fh, $stderr_fh, $status_fh )
		= ( IO::Handle->new(),
		IO::Handle->new(),
		IO::Handle->new(),
		IO::Handle->new(),
		);
	my $handles = GnuPG::Handles->new (
		stdin      => $stdin_fh,
		stdout     => $stdout_fh,
		stderr     => $stderr_fh,
		status     => $status_fh
		);
	my $pid = $GnuPG->wrap_call(
		commands     => [ '--export' ],
		command_args => [qw{--no-options --no-secmem-warning --no-default-keyring --keyring}, $keyring, @$keyids ],
		handles      => $handles );
	close($stdin_fh);

	my $stdout = join '', <$stdout_fh>; close($stdout_fh);
	my $stderr = join '', <$stderr_fh>; close($stderr_fh);
	my $status = join '', <$status_fh>; close($status_fh);

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
	build_lists();
};
sub build_keys() {
	build_mixring();
	build_pgpring();
};

1;
# vim: set ts=4 shiftwidth=4:
