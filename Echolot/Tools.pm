package Echolot::Tools;

# (c) 2002 Peter Palfrader <peter@palfrader.org>
# $Id: Tools.pm,v 1.2 2002/06/11 09:54:17 weasel Exp $
#

=pod

=head1 Name

Echolot::Tools - Tools for echolot

=head1 DESCRIPTION


=cut

use strict;
use warnings;
use Carp qw{cluck};
use Digest::MD5 qw{};
use Mail::Internet;

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
		cluck ("Sending messages without tokens?");
		$args{'From'} =
			Echolot::Config::get()->{'my_localpart'}.
			'@'.
			Echolot::Config::get()->{'my_domain'};
	};
	$args{'Subject'} = 'none' unless (defined $args{'Subject'});
	
	my $message = "To: $args{'To'}\n";
	$message .= "From: $args{'From'}\n";
	$message .= "Subject: $args{'Subject'}\n";
	$message .= "\n".$args{'Body'};
	
	my @lines = split (/\n/, $message);
	my $mail = new Mail::Internet ( \@lines );

	$mail->smtpsend( Host => Echolot::Config::get()->{'smarthost'} );
};

1;

# vim: set ts=4 shiftwidth=4:
