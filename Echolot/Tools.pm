package Echolot::Tools;

# (c) 2002 Peter Palfrader <peter@palfrader.org>
# $Id: Tools.pm,v 1.8 2002/08/14 22:54:20 weasel Exp $
#

=pod

=head1 Name

Echolot::Tools - Tools for echolot

=head1 DESCRIPTION


=cut

use strict;
use Carp qw{cluck};
use HTML::Template;
use Digest::MD5 qw{};

sub hash($) {
	my ($data) = @_;
	($data) = $data =~ m/(.*)/s;	# untaint
	my $hash = Digest::MD5::md5_hex($data);
	return $hash;
};

sub make_random($;%) {
	my ($length, %args) = @_;

	my $random;

	open (FH, Echolot::Config::get()->{'dev_random'}) or
		cluck("Cannot open ".Echolot::Config::get()->{'dev_random'}." for reading: $!"),
		return 0;
	read(FH, $random, $length) or
		cluck("Cannot read from ".Echolot::Config::get()->{'dev_random'}.": $!"),
		return 0;
	close (FH) or
		cluck("Cannot close ".Echolot::Config::get()->{'dev_random'}.": $!"),
		return 0;

	$random = unpack('H*', $random)
		if ($args{'armor'} == 1);

	return $random;
};

sub make_mac($) {
	my ($token) = @_;

	my $mac = hash($token . Echolot::Globals::get()->{'storage'}->get_secret() );
	return $mac;
};

sub makeShortNumHash($) {
	my ($text) = @_;

	my $hash = Echolot::Tools::make_mac($text);
	$hash = substr($hash, 0, 4);
	my $sum = hex($hash);
	return $sum;
};

sub verify_mac($$) {
	my ($token, $mac) = @_;
	
	return (hash($token . Echolot::Globals::get()->{'storage'}->get_secret() )  eq  $mac);
};

sub make_address($) {
	my ($subsystem) = @_;
	
	my $token = $subsystem.'='.time();
	my $hash = hash($token . Echolot::Globals::get()->{'storage'}->get_secret() );
	my $cut_hash = substr($hash, 0, Echolot::Config::get()->{'hash_len'});
	my $complete_token = $token.'='.$cut_hash;
	my $address = Echolot::Config::get()->{'my_localpart'}.
		Echolot::Config::get()->{'recipient_delimiter'}.
		$complete_token.
		'@'.
		Echolot::Config::get()->{'my_domain'};
	
	return $address;
};

sub verify_address_tokens($) {
	my ($address) = @_;

	my $delimiter = quotemeta( Echolot::Config::get()->{'recipient_delimiter'});
	my ($type, $timestamp, $received_hash) = $address =~ /$delimiter (.*) = (\d+) = ([0-9a-f]+) @/x or
		cluck("Could not parse to header '$address'"),
		return undef;

	my $token = $type.'='.$timestamp;
	my $hash = Echolot::Tools::hash($token . Echolot::Globals::get()->{'storage'}->get_secret() );
	my $cut_hash = substr($hash, 0, Echolot::Config::get()->{'hash_len'});

	($cut_hash eq $received_hash) or
		cluck("Hash mismatch in '$address'"),
		return undef;

	return 
		{ timestamp => $timestamp,
		  token => $type };
};

sub send_message(%) {
	my (%args) = @_;

	defined($args{'To'}) or
		cluck ('No recipient address given'),
		return 0;
	$args{'Subject'} = '' unless (defined $args{'Subject'});
	$args{'Body'} = '' unless (defined $args{'Body'});
	if (defined $args{'Token'}) {
		$args{'From'} = make_address( $args{'Token'} );
	} else {
		$args{'From'} =
			Echolot::Config::get()->{'my_localpart'}.
			'@'.
			Echolot::Config::get()->{'my_domain'};
	};
	$args{'Subject'} = 'none' unless (defined $args{'Subject'});
	
	my @lines = map { $_."\n" } split (/\r?\n/, $args{'Body'});

	open(SENDMAIL, '|'.Echolot::Config::get()->{'sendmail'}.' -f '.$args{'From'}.' -t')
		or cluck("Cannot run sendmail: $!"),
		return 0;
	printf SENDMAIL "From: %s\n", $args{'From'};
	printf SENDMAIL "To: %s\n", $args{'To'};
	printf SENDMAIL "Subject: %s\n", $args{'Subject'};
	printf SENDMAIL "\n";
	for my $line (@lines) {
		print SENDMAIL $line;
	};
	close SENDMAIL;

	return 1;
};

sub make_monthname($) {
	my ($month) = @_;
	my @MON  = qw{Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec};
	return $MON[$month];
};

sub make_dayname($) {
	my ($day) = @_;
	my @WDAY = qw{Sun Mon Tue Wed Thu Fri Sat};
	return $WDAY[$day];
};

sub date822($) {
	my ($date) = @_;

	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday) = gmtime($date);
	# 14 Aug 2002 17:11:12 +0100
	return sprintf("%s, %02d %s %d %02d:%02d:%02d +0000",
		make_dayname($wday),
		$mday,
		make_monthname($mon),
		$year + 1900,
		$hour,
		$min,
		$sec);
};

sub write_meta_information($%) {
	my ($file, %data) = @_;

	return 1 unless Echolot::Config::get()->{'write_meta_files'};

	$file .= Echolot::Config::get()->{'meta_extension'};
	open (F, ">$file") or
		cluck ("Cannot open $file: $!"),
		return 0;
	if (defined $data{'Expires'}) {
		my $date = date822($data{'Expires'});
		print F "Expires: $date\n";
	};
	close(F);
	return 1;
};

sub write_HTML_file($$;$%) {
	my ($file, $template_file, $expire, %templateparams) = @_;

	my $template =  HTML::Template->new(
		filename => $template_file,
		strict => 0,
		die_on_bad_params => 0,
		global_vars => 1 );
	$template->param ( %templateparams );
	$template->param ( CURRENT_TIMESTAMP => scalar gmtime() );
	$template->param ( SITE_NAME => Echolot::Config::get()->{'sitename'} );
	$template->param ( seperate_rlist => Echolot::Config::get()->{'seperate_rlists'} );
	$template->param ( combined_list => Echolot::Config::get()->{'combined_list'} );
	$template->param ( thesaurus => Echolot::Config::get()->{'thesaurus'} );
	$template->param ( version => Echolot::Globals::get()->{'version'} );
	$template->param ( expires => date822( time + $expire ));

	open(F, '>'.$file) or
		cluck("Cannot open $file: $!\n"),
		return 0;
	print F $template->output() or
		cluck("Cannot print to $file: $!\n"),
		return 0;
	close (F) or
		cluck("Cannot close $file: $!\n"),
		return 0;

	if (defined $expire) {
		write_meta_information($file,
			Expires => time + $expire) or
			cluck ("Error while writing meta information for $file"),
			return 0;
	};

	return 1;
};
1;

# vim: set ts=4 shiftwidth=4:
