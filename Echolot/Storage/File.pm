package Echolot::Storage::File;

# (c) 2002 Peter Palfrader <peter@palfrader.org>
# $Id: File.pm,v 1.3 2002/06/10 06:25:04 weasel Exp $
#

=pod

=head1 Name

Echolot::Storage::File - Storage backend for echolot

=head1 DESCRIPTION

This package provides several functions for data storage for echolot.

=over

=cut

use strict;
use warnings;
use XML::Parser;
use XML::Dumper;
use IO::Handle;
use English;
use Carp qw{cluck confess};
use Fcntl ':flock'; # import LOCK_* constants
use Fcntl ':seek'; # import LOCK_* constants
use Echolot::Tools;

=item B<new> (I<%args>)

Creates a new storage backend object.
args keys:

=over

=item I<datadir>

The basedir where this module may store it's configuration and pinging
data.

=back

=cut

my $CONSTANTS = {
	'metadatafile' => 'metadata'
};

$ENV{'PATH'} = '/bin:/usr/bin';
delete @ENV{'IFS', 'CDPATH', 'ENV', 'BASH_ENV'};

my $METADATA_VERSION = 1;

my $INTERNAL_COUNT = 1;

sub new {
	my ($class, %params) = @_;
	my $self = {};
	bless $self, $class;

	defined($params{'datadir'}) or
		confess ('No datadir option passed to new');
	$self->{'datadir'} = $params{'datadir'};
	$self->{'DELAY_COMMIT'} = 0;

	$self->delay_commit();
	$self->metadata_open() or
		cluck ('Opening Metadata  failed. Exiting'),
		exit 1;
	$self->metadata_read() or
		cluck ('Reading Metadata from Storage failed. Exiting'),
		exit 1;
	$self->pingdata_open() or
		cluck ('Opening Ping files failed. Exiting'),
		exit 1;
	$self->enable_commit();
	
	return $self;
};

sub commit($) {
	my ($self) = @_;

	if ($self->{'DELAY_COMMIT'}) {
		$self->{'COMMIT_PENDING'} = 1;
		return;
	};
	$self->metadata_write();
	$self->{'COMMIT_PENDING'} = 0;
};

sub delay_commit($) {
	my ($self) = @_;

	$self->{'DELAY_COMMIT'}++;
};
sub enable_commit($) {
	my ($self) = @_;

	$self->{'DELAY_COMMIT'}--;
	$self->commit() if ($self->{'COMMIT_PENDING'} && ! $self->{'DELAY_COMMIT'});
};

sub finish($) {
	my ($self) = @_;

	$self->pingdata_close();
	$self->metadata_write();
	$self->metadata_close();
};


sub metadata_open($) {
	my ($self) = @_;

	$self->{'METADATA_FH'} = new IO::Handle;
	my $filename = $self->{'datadir'} .'/'. $CONSTANTS->{'metadatafile'};

	if ( -e $filename ) {
		open($self->{'METADATA_FH'}, '+<' . $filename) or 
			cluck("Cannot open $filename for reading: $!"),
			return 0;
	} else {
		open($self->{'METADATA_FH'}, '+>' . $filename) or 
			cluck("Cannot open $filename for reading: $!"),
			return 0;
	};
	flock($self->{'METADATA_FH'}, LOCK_SH) or
		cluck("Cannot get shared lock on $filename: $!"),
		return 0;
};

sub metadata_close($) {
	my ($self) = @_;

	flock($self->{'METADATA_FH'}, LOCK_UN) or
		cluck("Error when releasing lock on metadata file: $!"),
		return -1;
	close($self->{'METADATA_FH'}) or
		cluck("Error when closing metadata file: $!"),
		return 0;
};


sub metadata_read($) {
	my ($self) = @_;

	$self->{'METADATA'} = ();
	seek($self->{'METADATA_FH'}, 0, SEEK_SET) or
		cluck("Cannot seek to start of metadata file: $!"),
		return 0;
	eval {
		my $parser = new XML::Parser(Style => 'Tree');
		my $tree = $parser->parse( $self->{'METADATA_FH'} );
		my $dump = new XML::Dumper;
		$self->{'METADATA'} = $dump->xml2pl($tree);
	};
	$EVAL_ERROR and
		cluck("Error when reading from metadata file: $EVAL_ERROR"),
		return 0;

	defined($self->{'METADATA'}->{'version'}) or
		cluck("Stored data lacks version header"),
		return 0;
	($self->{'METADATA'}->{'version'} == ($METADATA_VERSION)) or
		cluck("Metadata version mismatch ($self->{'METADATA'}->{'version'} vs. $METADATA_VERSION)"),
		return 0;


	defined($self->{'METADATA'}->{'secret'}) or
		$self->{'METADATA'}->{'secret'} = Echolot::Tools::make_random ( 16, armor => 1 ),
		$self->commit();

	return 1;
};

sub metadata_write($) {
	my ($self) = @_;

	# FIXME XML::Dumper bug workaround
	# There is a bug in pl2xml that changes data passed (cf. Debian Bug #148969 and #148970
	# at http://bugs.debian.org/148969 and http://bugs.debian.org/148970
	require Data::Dumper;
	my $storedata;
	eval ( Data::Dumper->Dump( [ $self->{'METADATA'} ], [ 'storedata' ] ));

	my $dump = new XML::Dumper;
	my $data = $dump->pl2xml($storedata);
	my $fh = $self->{'METADATA_FH'};

	seek($fh, 0, SEEK_SET) or
		cluck("Cannot seek to start of metadata file: $!"),
		return 0;
	truncate($fh, 0) or
		cluck("Cannot truncate metadata file to zero length: $!"),
		return 0;
	print($fh "<!-- vim:set syntax=xml: -->\n") or
		cluck("Error when writing to metadata file: $!"),
		return 0;
	print($fh $data) or
		cluck("Error when writing to metadata file: $!"),
		return 0;


	return 1;
};


sub pingdata_open($) {
	my ($self) = @_;

	for my $remailer_name ( keys %{$self->{'METADATA'}->{'remailers'}} ) {
		for my $key ( keys %{$self->{'METADATA'}->{'remailers'}->{$remailer_name}->{'keys'}} ) {
			my $basename = $self->{'METADATA'}->{'remailers'}->{$remailer_name}->{'stats'}->{$key};
			defined($basename) or
				$basename = $self->{'METADATA'}->{'remailers'}->{$remailer_name}->{'stats'}->{$key} = $remailer_name.'.'.$key.'.'.time.'.'.$PROCESS_ID.'_'.$INTERNAL_COUNT++,
				$self->commit();

			my $filename = $self->{'datadir'} .'/'. $basename;
		
			for my $type ('out', 'done') {
				my $fh = new IO::Handle;
				if ( -e $filename.'.'.$type ) {
					open($fh, '+<' . $filename.'.'.$type) or 
						cluck("Cannot open $filename.$type for reading: $!"),
						return 0;
					$self->{'PING_FHS'}->{$remailer_name}->{$key}->{$type} = $fh;
				} else {
					open($fh, '+>' . $filename.'.'.$type) or 
						cluck("Cannot open $filename.$type for reading: $!"),
						return 0;
					$self->{'PING_FHS'}->{$remailer_name}->{$key}->{$type} = $fh;
				};
				flock($fh, LOCK_EX) or
					cluck("Cannot get exclusive lock on $remailer_name $type pings: $!"),
					return 0;
			};
		};
	};
	return 1;
};

sub get_pings($$$$) {
	my ($self, $remailer_name, $key, $type) = @_;

	defined ($self->{'METADATA'}->{'remailers'}->{$remailer_name}) or
		cluck ("$remailer_name does not exist in Metadata"),
		return 0;
	
	my @pings;
	my $fh = $self->{'PING_FHS'}->{$remailer_name}->{$key}->{$type};

	defined ($fh) or
		cluck ("$remailer_name; key=$key has no assigned filehandle for $type pings"),
		return 0;

	seek($fh, 0, SEEK_SET) or
		cluck("Cannot seek to start of $remailer_name $type pings: $!"),
		return 0;

	if ($type eq 'out') {
		@pings = map {chomp; $_; } <$fh>;
	} elsif ($type eq 'done') {
		@pings = map {chomp; my @arr = split (/\s+/, $_, 2); \@arr; } <$fh>;
	} else {
		confess("What the hell am I doing here? $remailer_name; $key; $type"),
		return 0;
	};
	return \@pings;
};

sub pingdata_close() {
	my ($self) = @_;

	for my $remailer_name ( keys %{$self->{'PING_FHS'}} ) {
		for my $key ( keys %{$self->{'PING_FHS'}->{$remailer_name}} ) {
			for my $type ('out', 'done') {

				my $fh = $self->{'PING_FHS'}->{$remailer_name}->{$key}->{$type};
				flock($fh, LOCK_UN) or
					cluck("Error when releasing lock on $remailer_name $type pings: $!"),
					return 0;
				close ($self->{'PING_FHS'}->{$remailer_name}->{$key}->{$type}) or
						cluck("Error when closing $remailer_name $type pings: $!"),
						return 0;
			};
		};
	};
	return 1;
};





sub register_pingout($$$$) {
	my ($self, $remailer_name, $key, $sent_time) = @_;
	
	defined ($self->{'METADATA'}->{'remailers'}->{$remailer_name}) or
		cluck ("$remailer_name does not exist in Metadata"),
		return 0;

	my $fh = $self->{'PING_FHS'}->{$remailer_name}->{$key}->{'out'};
	defined ($fh) or
		cluck ("$remailer_name; key=$key has no assigned filehandle for outgoing pings"),
		return 0;
	seek($fh, 0, SEEK_END) or
		cluck("Cannot seek to end of $remailer_name out pings: $!"),
		return 0;
	print($fh $sent_time."\n") or
		cluck("Error when writing to $remailer_name out pings: $!"),
		return 0;

	return 1;
};

sub register_pingdone($$$$$) {
	my ($self, $remailer_name, $key, $sent_time, $latency) = @_;
	
	defined ($self->{'METADATA'}->{'remailers'}->{$remailer_name}) or
		cluck ("$remailer_name does not exist in Metadata"),
		return 0;

	my $outpings = $self->get_pings($remailer_name, $key, 'out');
	my $origlen = scalar (@$outpings);
	@$outpings = grep { $_ != $sent_time } @$outpings;
	($origlen == scalar (@$outpings)) and
		warn("No ping outstanding for $remailer_name, $key, $sent_time\n"),
		return 1;
	
	# write ping to done
	my $fh = $self->{'PING_FHS'}->{$remailer_name}->{$key}->{'done'};
	defined ($fh) or
		cluck ("$remailer_name; key=$key has no assigned filehandle for done pings"),
		return 0;
	seek($fh, 0, SEEK_END) or
		cluck("Cannot seek to end of $remailer_name out pings: $!"),
		return 0;
	print($fh $sent_time." ".$latency."\n") or
		cluck("Error when writing to $remailer_name out pings: $!"),
		return 0;
	
	# rewrite outstanding pings
	$fh = $self->{'PING_FHS'}->{$remailer_name}->{$key}->{'out'};
	defined ($fh) or
		cluck ("$remailer_name; key=$key has no assigned filehandle for out pings"),
		return 0;
	seek($fh, 0, SEEK_SET) or
		cluck("Cannot seek to start of outgoing pings file for remailer $remailer_name; key=$key: $!"),
		return 0;
	truncate($fh, 0) or
		cluck("Cannot truncate outgoing pings file for remailer $remailer_name; key=$key file to zero length: $!"),
		return 0;
	print($fh (join "\n", @$outpings),"\n") or
		cluck("Error when writing to outgoing pings file for remailer $remailer_name; key=$key file: $!"),
		return 0;
	
	return 1;
};

sub add_prospective_address($$$$) {
	my ($self, $addr, $reason, $additional) = @_;

	return 1 if defined $self->{'METADATA'}->{'addresses'}->{$addr};
	push @{ $self->{'METADATA'}->{'prospective_addresses'}{$addr} }, time().'; '. $reason. '; '. $additional;
	$self->commit();
};

sub get_addresses($) {
	my ($self) = @_;

	my @addresses = keys %{$self->{'METADATA'}->{'addresses'}};
	my @return_data = map { my %tmp = %{$self->{'METADATA'}->{'addresses'}->{$_}}; $tmp{'address'} = $_; \%tmp; } @addresses;
	return @return_data;
};

sub get_address_by_id($$) {
	my ($self, $id) = @_;

	my @addresses = grep {$self->{'METADATA'}->{'addresses'}->{$_}->{'id'} == $id}
		keys %{$self->{'METADATA'}->{'addresses'}};
	return undef unless (scalar @addresses);
	if (scalar @addresses >= 2) {
		cluck("Searching for address by id '$id' gives more than one result");
	};
	my %return_data = %{$self->{'METADATA'}->{'addresses'}->{$addresses[0]}};
	$return_data{'address'} = $addresses[0];
	return \%return_data;
};

sub decrease_ttl($$) {
	my ($self, $address) = @_;
	
	defined ($self->{'METADATA'}->{'addresses'}->{$address}) or
		cluck ("$address does not exist in Metadata address list"),
		return 0;
	$self->{'METADATA'}->{'addresses'}->{$address}->{'ttl'} --;
	$self->{'METADATA'}->{'addresses'}->{$address}->{'status'} = 'disabled',
		warn("Remailer $address disablesd: ttl expired\n")
		if ($self->{'METADATA'}->{'addresses'}->{$address}->{'ttl'} <= 0);
		# FIXME have proper logging
	$self->commit();
	return 1;
};

sub restore_ttl($$) {
	my ($self, $address) = @_;
	
	defined ($self->{'METADATA'}->{'addresses'}->{$address}) or
		cluck ("$address does not exist in Metadata address list"),
		return 0;
	$self->{'METADATA'}->{'addresses'}->{$address}->{'ttl'} = Echolot::Config::get()->{'addresses_default_ttl'};
	$self->commit();
	return 1;
};

sub set_caps($$$$$$) {
	my ($self, $type, $caps, $nick, $address, $timestamp) = @_;
	
	if (! defined $self->{'METADATA'}->{'remailers'}->{$address}) {
		$self->{'METADATA'}->{'remailers'}->{$address} =
			{
				status => 'active',
				pingit => Echolot::Config::get()->{'ping_new'},
				showit => Echolot::Config::get()->{'show_new'},
				conf => {
					nick => $nick,
					type => $type,
					capabilities => $caps,
					last_update => $timestamp
				}
			};
	} else {
		my $conf = $self->{'METADATA'}->{'remailers'}->{$address}->{'conf'};
		if ($conf->{'last_update'} >= $timestamp) {
			warn ("Stored data is already newer for remailer $nick\n");
			return 1;
		};
		$conf->{'last_update'} = $timestamp;
		if ($conf->{'nick'} ne $nick) {
			warn ($conf->{'nick'}." was renamed to $nick\n");
			$conf->{'nick'} = $nick;
		};
		if ($conf->{'capabilities'} ne $caps) {
			warn ("$nick has a new caps string '$caps' old: '".$conf->{'capabilities'}."'\n");
			$conf->{'capabilities'} = $caps;
		};
		if ($conf->{'type'} ne $type) {
			warn ("$nick has a new type string '$type'\n");
			$conf->{'type'} = $type;
		};
	};
	$self->commit();
	
	return 1;
};

sub set_key($$$$$$$$$) {
	my ($self, $type, $nick, $address, $key, $keyid, $version, $caps, $summary, $timestamp) = @_;
	
	if (! defined $self->{'METADATA'}->{'remailers'}->{$address}) {
		$self->{'METADATA'}->{'remailers'}->{$address} =
			{
				status => 'active',
				pingit => Echolot::Config::get()->{'ping_new'},
				showit => Echolot::Config::get()->{'show_new'},
			};
	};

	if (! defined $self->{'METADATA'}->{'remailers'}->{$address}->{'keys'}) {
		$self->{'METADATA'}->{'remailers'}->{$address}->{'keys'} = {};
	};
	if (! defined $self->{'METADATA'}->{'remailers'}->{$address}->{'keys'}->{$type}) {
		$self->{'METADATA'}->{'remailers'}->{$address}->{'keys'}->{$type} = {};
	};

	if (! defined $self->{'METADATA'}->{'remailers'}->{$address}->{'keys'}->{$type}->{$keyid}) {
		$self->{'METADATA'}->{'remailers'}->{$address}->{'keys'}->{$type}->{$keyid} =
			{
				key => $key,
				summary => $summary,
				last_update => $timestamp
			};
	} else {
		my $keyref = $self->{'METADATA'}->{'remailers'}->{$address}->{'keys'}->{$type}->{$keyid};
		if ($keyref->{'last_update'} >= $timestamp) {
			warn ("Stored data is already newer for remailer $nick\n");
			return 1;
		};
		$keyref->{'last_update'} = $timestamp;
		if ($keyref->{'summary'} ne $summary) {
			warn ("$nick has a new key summary string '$summary' old: '".$keyref->{'summary'}."'\n");
			$keyref->{'summary'} = $summary;
		};
		if ($keyref->{'key'} ne $key) {
			warn ("$nick has a new key string '$key' old: '".$keyref->{'key'}."' - This probably should not happen\n");
			$keyref->{'key'} = $key;
		};
	};
	$self->commit();
	
	return 1;
};

sub get_secret($) {
	my ($self) = @_;

	return $self->{'METADATA'}->{'secret'};
};

=back

=cut

# vim: set ts=4 shiftwidth=4:
