package Echolot::Storage::File;

# (c) 2002 Peter Palfrader <peter@palfrader.org>
# $Id: File.pm,v 1.16 2002/07/02 17:03:42 weasel Exp $
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
sub enable_commit($;$) {
	my ($self, $set_pending) = @_;

	$self->{'DELAY_COMMIT'}--;
	$self->commit() if (($self->{'COMMIT_PENDING'} || (defined $set_pending && $set_pending)) && ! $self->{'DELAY_COMMIT'});
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
	flock($self->{'METADATA_FH'}, LOCK_EX) or
		cluck("Cannot get exclusive lock on $filename: $!"),
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
	$fh->flush();

	return 1;
};





sub pingdata_open_one($$$$) {
	my ($self, $remailer_addr, $type, $key) = @_;
	
	defined ($self->{'METADATA'}->{'remailers'}->{$remailer_addr}) or
		cluck ("$remailer_addr does not exist in Metadata"),
		return 0;
	defined ($self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'keys'}) or
		cluck ("$remailer_addr has no keys in Metadata"),
		return 0;
	defined ($self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'keys'}->{$type}) or
		cluck ("$remailer_addr type $type does not exist in Metadata"),
		return 0;
	defined ($self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'keys'}->{$type}->{$key}) or
		cluck ("$remailer_addr type $type key $key does not exist in Metadata"),
		return 0;
	

	my $basename = $self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'keys'}->{$type}->{$key}->{'stats'};
	defined($basename) or
		$basename = $self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'keys'}->{$type}->{$key}->{'stats'} = $remailer_addr.'.'.$type.'.'.$key.'.'.time.'.'.$PROCESS_ID.'_'.Echolot::Globals::get()->{'internalcounter'}++,
		$self->commit();

	my $filename = $self->{'datadir'} .'/'. $basename;

	for my $direction ('out', 'done') {
		my $fh = new IO::Handle;
		if ( -e $filename.'.'.$direction ) {
			open($fh, '+<' . $filename.'.'.$direction) or 
				cluck("Cannot open $filename.$direction for reading: $!"),
				return 0;
			$self->{'PING_FHS'}->{$remailer_addr}->{$type}->{$key}->{$direction} = $fh;
		} else {
			open($fh, '+>' . $filename.'.'.$direction) or 
				cluck("Cannot open $filename.$direction for reading: $!"),
				return 0;
			$self->{'PING_FHS'}->{$remailer_addr}->{$type}->{$key}->{$direction} = $fh;
		};
		flock($fh, LOCK_EX) or
			cluck("Cannot get exclusive lock on $remailer_addr $type $key $direction pings: $!"),
			return 0;
	};

	return 1;
};

sub pingdata_open($) {
	my ($self) = @_;

	for my $remailer_addr ( keys %{$self->{'METADATA'}->{'remailers'}} ) {
		for my $type ( keys %{$self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'keys'}} ) {
			for my $key ( keys %{$self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'keys'}->{$type}} ) {
				$self->pingdata_open_one($remailer_addr, $type, $key);
			};
		};
	};
	return 1;
};

sub get_ping_fh($$$$$) {
	my ($self, $remailer_addr, $type, $key, $direction) = @_;

	defined ($self->{'METADATA'}->{'remailers'}->{$remailer_addr}) or
		cluck ("$remailer_addr does not exist in Metadata"),
		return 0;
	
	my @pings;
	my $fh = $self->{'PING_FHS'}->{$remailer_addr}->{$type}->{$key}->{$direction};

	defined ($fh) or
		$self->pingdata_open_one($remailer_addr, $type, $key),
		$fh = $self->{'PING_FHS'}->{$remailer_addr}->{$type}->{$key}->{$direction};
		defined ($fh) or
			cluck ("$remailer_addr; type=$type; key=$key has no assigned filehandle for $direction pings"),
			return 0;

	return $fh;
};

sub pingdata_close_one($$$$;$) {
	my ($self, $remailer_addr, $type, $key, $delete) = @_;

	for my $direction ( keys %{$self->{'PING_FHS'}->{$remailer_addr}->{$type}->{$key}} ) {
		my $fh = $self->{'PING_FHS'}->{$remailer_addr}->{$type}->{$key}->{$direction};

		flock($fh, LOCK_UN) or
			cluck("Error when releasing lock on $remailer_addr type $type key $key direction $direction pings: $!"),
			return 0;
		close ($fh) or
				cluck("Error when closing $remailer_addr type $type key $key direction $direction pings: $!"),
				return 0;

		if ((defined $delete) && ($delete eq 'delete')) {
			my $basename = $self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'keys'}->{$type}->{$key}->{'stats'};
			my $filename = $self->{'datadir'} .'/'. $basename;
			unlink ($filename.'.'.$direction) or
				carp ("Cannot unlink $filename.'.'.$direction: $!");
		};
	};

	delete $self->{'PING_FHS'}->{$remailer_addr}->{$type}->{$key};

	delete $self->{'PING_FHS'}->{$remailer_addr}->{$type}
		unless (scalar keys %{$self->{'PING_FHS'}->{$remailer_addr}->{$type}});
	delete $self->{'PING_FHS'}->{$remailer_addr}
		unless (scalar keys %{$self->{'PING_FHS'}->{$remailer_addr}});


	return 1;
};

sub pingdata_close($) {
	my ($self) = @_;

	for my $remailer_addr ( keys %{$self->{'PING_FHS'}} ) {
		for my $type ( keys %{$self->{'PING_FHS'}->{$remailer_addr}} ) {
			for my $key ( keys %{$self->{'PING_FHS'}->{$remailer_addr}->{$type}} ) {
				$self->pingdata_close_one($remailer_addr, $type, $key) or
					cluck("Error when calling pingdata_close_one with $remailer_addr type $type key $key"),
					return 0;
			};
		};
	};
	return 1;
};

sub get_pings($$$$$) {
	my ($self, $remailer_addr, $type, $key, $direction) = @_;

	my @pings;

	my $fh = $self->get_ping_fh($remailer_addr, $type, $key, $direction) or
		cluck ("$remailer_addr; type=$type; key=$key has no assigned filehandle for $direction pings"),
		return 0;

	seek($fh, 0, SEEK_SET) or
		cluck("Cannot seek to start of $remailer_addr type $type key $key direction $direction pings: $!"),
		return 0;

	if ($direction eq 'out') {
		@pings = map {chomp; $_; } <$fh>;
	} elsif ($direction eq 'done') {
		@pings = map {chomp; my @arr = split (/\s+/, $_, 2); \@arr; } <$fh>;
	} else {
		confess("What the hell am I doing here? $remailer_addr; $type; $key; $direction"),
		return 0;
	};
	return @pings;
};






sub register_pingout($$$$) {
	my ($self, $remailer_addr, $type, $key, $sent_time) = @_;
	
	my $fh = $self->get_ping_fh($remailer_addr, $type, $key, 'out') or
		cluck ("$remailer_addr; type=$type; key=$key has no assigned filehandle for out pings"),
		return 0;

	seek($fh, 0, SEEK_END) or
		cluck("Cannot seek to end of $remailer_addr; type=$type; key=$key; out pings: $!"),
		return 0;
	print($fh $sent_time."\n") or
		cluck("Error when writing to $remailer_addr; type=$type; key=$key; out pings: $!"),
		return 0;
	$fh->flush();
	print "registering pingout at $sent_time for $remailer_addr ($type; $key)\n"
		if Echolot::Config::get()->{'verbose'};

	return 1;
};

sub register_pingdone($$$$$) {
	my ($self, $remailer_addr, $type, $key, $sent_time, $latency) = @_;
	
	defined ($self->{'METADATA'}->{'remailers'}->{$remailer_addr}) or
		cluck ("$remailer_addr does not exist in Metadata"),
		return 0;

	my @outpings = $self->get_pings($remailer_addr, $type, $key, 'out');
	my $origlen = scalar (@outpings);
	@outpings = grep { $_ != $sent_time } @outpings;
	($origlen == scalar (@outpings)) and
		warn("No ping outstanding for $remailer_addr, $key, $sent_time\n"),
		return 1;
	
	# write ping to done
	my $fh = $self->get_ping_fh($remailer_addr, $type, $key, 'done') or
		cluck ("$remailer_addr; type=$type; key=$key has no assigned filehandle for done pings"),
		return 0;
	seek($fh, 0, SEEK_END) or
		cluck("Cannot seek to end of $remailer_addr out pings: $!"),
		return 0;
	print($fh $sent_time." ".$latency."\n") or
		cluck("Error when writing to $remailer_addr out pings: $!"),
		return 0;
	$fh->flush();
	
	# rewrite outstanding pings
	$fh = $self->get_ping_fh($remailer_addr, $type, $key, 'out') or
		cluck ("$remailer_addr; type=$type; key=$key has no assigned filehandle for out pings"),
		return 0;
	seek($fh, 0, SEEK_SET) or
		cluck("Cannot seek to start of outgoing pings file for remailer $remailer_addr; key=$key: $!"),
		return 0;
	truncate($fh, 0) or
		cluck("Cannot truncate outgoing pings file for remailer $remailer_addr; key=$key file to zero length: $!"),
		return 0;
	print($fh (join "\n", @outpings), (scalar @outpings ? "\n" : '') ) or
		cluck("Error when writing to outgoing pings file for remailer $remailer_addr; key=$key file: $!"),
		return 0;
	$fh->flush();
	print "registering pingdone from $sent_time with latency $latency for $remailer_addr ($type; $key)\n"
		if Echolot::Config::get()->{'verbose'};
	
	return 1;
};





sub add_prospective_address($$$$) {
	my ($self, $addr, $reason, $additional) = @_;

	return 1 if defined $self->{'METADATA'}->{'addresses'}->{$addr};
	push @{ $self->{'METADATA'}->{'prospective_addresses'}{$addr} }, time().'; '. $reason. '; '. $additional;
	$self->commit();
};

sub commit_prospective_address($) {
	my ($self) = @_;
	
	$self->delay_commit();
	for my $addr (keys %{$self->{'METADATA'}->{'prospective_addresses'}}) {
		if (defined $self->{'METADATA'}->{'addresses'}->{$addr}) {
			delete $self->{'METADATA'}->{'prospective_addresses'}->{$addr};
			next;
		};

		# expire old prospective addresses
		while (@{ $self->{'METADATA'}->{'prospective_addresses'}->{$addr} }) {
			my ($time, $reason, $additional) = split(/;\s*/, $self->{'METADATA'}->{'prospective_addresses'}->{$addr}->[0] );
			if ($time < time() - Echolot::Config::get()->{'prospective_addresses_ttl'} ) {
				shift @{ $self->{'METADATA'}->{'prospective_addresses'}->{$addr} };
			} else {
				last;
			};
		};

		unless (scalar @{ $self->{'METADATA'}->{'prospective_addresses'}->{$addr} }) {
			delete $self->{'METADATA'}->{'prospective_addresses'}->{$addr};
			next;
		};
		
		my %reasons;
		for my $line ( @{ $self->{'METADATA'}->{'prospective_addresses'}->{$addr} } ) {
			my ($time, $reason, $additional) = split(/;\s*/, $line);
			push @{ $reasons{$reason} }, $additional;
		};

		# got prospective by reply to own remailer-conf or remailer-key request
		if ( defined $reasons{'self-capsstring-conf'} || defined $reasons{'self-capsstring-key'} ) {
			$self->add_address($addr);
			delete $self->{'METADATA'}->{'prospective_addresses'}->{$addr};
			next;
		}

		# was listed in reliable's remailer-conf reply; @adds holds suggestors
		my @adds;
		push @adds, @{ $reasons{'reliable-caps-reply-type1'} } if defined $reasons{'reliable-caps-reply-type1'};
		push @adds, @{ $reasons{'reliable-caps-reply-type2'} } if defined $reasons{'reliable-caps-reply-type2'};
		if (scalar @adds) {
			my %unique;
			@adds = grep { ! $unique{$_}++; } @adds;
			if (scalar @adds >= Echolot::Config::get()->{'reliable_auto_add_min'} ) {
				$self->add_address($addr);
				delete $self->{'METADATA'}->{'prospective_addresses'}->{$addr};
				next;
			};
		};
	};

	$self->enable_commit(1);
};

sub get_addresses($) {
	my ($self) = @_;

	my @addresses = keys %{$self->{'METADATA'}->{'addresses'}};
	my @return_data = map {
		my %tmp;
		$tmp{'status'} = $self->{'METADATA'}->{'addresses'}->{$_}->{'status'};
		$tmp{'id'} = $self->{'METADATA'}->{'addresses'}->{$_}->{'id'};
		$tmp{'address'} = $_;
		\%tmp;
		} @addresses;
	return @return_data;
};

sub add_address($$) {
	my ($self, $addr) = @_;
	
	my @all_addresses = $self->get_addresses();
	my $maxid = 0;
	for my $addr (@all_addresses) {
		if ($addr->{'id'} > $maxid) {
			$maxid = $addr->{'id'};
		};
	};
	
	my $remailer = {
		id => $maxid + 1,
		status => 'active',
		ttl => Echolot::Config::get()->{'addresses_default_ttl'},
		fetch  => Echolot::Config::get()->{'fetch_new'},
		pingit => Echolot::Config::get()->{'ping_new'},
		showit => Echolot::Config::get()->{'show_new'},
	};
	
	# FIXME logging and such
	print "Adding address $addr\n"
		if Echolot::Config::get()->{'verbose'};

	$self->{'METADATA'}->{'addresses'}->{$addr} = $remailer;
	$self->commit();

	return 1;
};

sub set_stuff($@) {
	my ($self, @args) = @_;

	my ($addr, $setting) = @args;
	my $args = join(', ', @args);

	defined ($addr) or
		cluck ("Could not get address for '$args'"),
		return 0;
	defined ($setting) or
		cluck ("Could not get setting for '$args'"),
		return 0;
	
	defined ($self->{'METADATA'}->{'addresses'}->{$addr}) or
		cluck ("Address $addr does not exist"),
		return 0;
	

	if ($setting =~ /^(pingit|fetch|showit)=(on|off)$/) {
		my $option = $1;
		my $value = $2;
		print "Setting $option to $value for $addr\n"
			if Echolot::Config::get()->{'verbose'};
		$self->{'METADATA'}->{'addresses'}->{$addr}->{$option} = ($value eq 'on');
	} else {
		cluck ("Don't know what to do with '$setting' for $addr"),
		return 0;
	}

	$self->commit();
	return 1;
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
	$self->{'METADATA'}->{'addresses'}->{$address}->{'status'} = 'ttl timeout',
		warn("Remailer $address disabled: ttl expired\n")
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
	$self->{'METADATA'}->{'addresses'}->{$address}->{'status'} = 'active' if
		($self->{'METADATA'}->{'addresses'}->{$address}->{'status'} eq 'ttl timeout');
	$self->commit();
	return 1;
};

sub set_caps($$$$$$) {
	my ($self, $type, $caps, $nick, $address, $timestamp) = @_;
	if (! defined $self->{'METADATA'}->{'remailers'}->{$address}) {
		$self->{'METADATA'}->{'remailers'}->{$address} =
			{
				status => 'active'
			};
	} else {
		$self->{'METADATA'}->{'remailers'}->{$address}->{'status'} = 'active'
			if ($self->{'METADATA'}->{'remailers'}->{$address}->{'status'} eq 'expired');
	};

	if (! defined $self->{'METADATA'}->{'remailers'}->{$address}->{'conf'}) {
		$self->{'METADATA'}->{'remailers'}->{$address}->{'conf'} =
			{
					nick => $nick,
					type => $type,
					capabilities => $caps,
					last_update => $timestamp
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
				status => 'active'
			};
	} else {
		$self->{'METADATA'}->{'remailers'}->{$address}->{'status'} = 'active'
			if ($self->{'METADATA'}->{'remailers'}->{$address}->{'status'} eq 'expired');
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
				nick => $nick,
				last_update => $timestamp
			};
	} else {
		my $keyref = $self->{'METADATA'}->{'remailers'}->{$address}->{'keys'}->{$type}->{$keyid};
		if ($keyref->{'last_update'} >= $timestamp) {
			warn ("Stored data is already newer for remailer $nick\n");
			return 1;
		};
		$keyref->{'last_update'} = $timestamp;
		if ($keyref->{'nick'} ne $nick) {
			warn ("$nick has a new key nick string '$nick' old: '".$keyref->{'nick'}."'\n");
			$keyref->{'nick'} = $nick;
		};
		if ($keyref->{'summary'} ne $summary) {
			warn ("$nick has a new key summary string '$summary' old: '".$keyref->{'summary'}."'\n");
			$keyref->{'summary'} = $summary;
		};
		if ($keyref->{'key'} ne $key) {
			#warn ("$nick has a new key string '$key' old: '".$keyref->{'key'}."' - This probably should not happen\n");
			warn ("$nick has a new key string for same keyid $keyid\n");
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

sub get_remailers($) {
	my ($self) = @_;

	my @remailers = keys %{$self->{'METADATA'}->{'remailers'}};
	my @return_data = map {
		carp ("remailer $_ is defined but not in addresses ")
			unless defined $self->{'METADATA'}->{'addresses'}->{$_};
		my %tmp;
		$tmp{'status'} = $self->{'METADATA'}->{'remailers'}->{$_}->{'status'};
		$tmp{'pingit'} = $self->{'METADATA'}->{'addresses'}->{$_}->{'pingit'};
		$tmp{'showit'} = $self->{'METADATA'}->{'addresses'}->{$_}->{'showit'};
		$tmp{'address'} = $_;
		\%tmp;
		} @remailers;
	return @return_data;
};

sub get_types($$) {
	my ($self, $remailer) = @_;

	defined ($self->{'METADATA'}->{'remailers'}->{$remailer}) or
		cluck ("$remailer does not exist in Metadata remailer list"),
		return 0;

	return () unless defined $self->{'METADATA'}->{'remailers'}->{$remailer}->{'keys'};
	my @types = keys %{$self->{'METADATA'}->{'remailers'}->{$remailer}->{'keys'}};
	return @types;
};

sub has_type($$$) {
	my ($self, $remailer, $type) = @_;

	defined ($self->{'METADATA'}->{'remailers'}->{$remailer}) or
		cluck ("$remailer does not exist in Metadata remailer list"),
		return 0;

	return 0 unless defined $self->{'METADATA'}->{'remailers'}->{$remailer}->{'keys'};
	return 0 unless defined $self->{'METADATA'}->{'remailers'}->{$remailer}->{'keys'}->{$type};
	return 0 unless scalar keys %{$self->{'METADATA'}->{'remailers'}->{$remailer}->{'keys'}->{$type}};
	return 1;
};

sub get_keys($$) {
	my ($self, $remailer, $type) = @_;

	defined ($self->{'METADATA'}->{'remailers'}->{$remailer}) or
		cluck ("$remailer does not exist in Metadata remailer list"),
		return 0;

	defined ($self->{'METADATA'}->{'remailers'}->{$remailer}->{'keys'}->{$type}) or
		cluck ("$remailer does not have type '$type' in Metadata remailer list"),
		return 0;

	my @keys = keys %{$self->{'METADATA'}->{'remailers'}->{$remailer}->{'keys'}->{$type}};
	return @keys;
};

sub get_key($$$$) {
	my ($self, $remailer, $type, $key) = @_;

	defined ($self->{'METADATA'}->{'remailers'}->{$remailer}) or
		cluck ("$remailer does not exist in Metadata remailer list"),
		return 0;

	defined ($self->{'METADATA'}->{'remailers'}->{$remailer}->{'keys'}->{$type}) or
		cluck ("$remailer does not have type '$type' in Metadata remailer list"),
		return 0;

	defined ($self->{'METADATA'}->{'remailers'}->{$remailer}->{'keys'}->{$type}->{$key}) or
		cluck ("$remailer does not have key '$key' in type '$type' in Metadata remailer list"),
		return 0;

	my %result = (
		summary => $self->{'METADATA'}->{'remailers'}->{$remailer}->{'keys'}->{$type}->{$key}->{'summary'},
		key => $self->{'METADATA'}->{'remailers'}->{$remailer}->{'keys'}->{$type}->{$key}->{'key'},
		nick => $self->{'METADATA'}->{'remailers'}->{$remailer}->{'keys'}->{$type}->{$key}->{'nick'},
		last_update => $self->{'METADATA'}->{'remailers'}->{$remailer}->{'keys'}->{$type}->{$key}->{'last_update'}
	);

	return %result;
};

sub get_capabilities($$) {
	my ($self, $remailer) = @_;
	
	return undef unless defined $self->{'METADATA'}->{'remailers'}->{$remailer}->{'conf'};
	return $self->{'METADATA'}->{'remailers'}->{$remailer}->{'conf'}->{'capabilities'};
};

sub get_nick($$) {
	my ($self, $remailer) = @_;
	
	return undef unless defined $self->{'METADATA'}->{'remailers'}->{$remailer}->{'conf'};
	return $self->{'METADATA'}->{'remailers'}->{$remailer}->{'conf'}->{'nick'};
};


sub expire($) {
	my ($self) = @_;

	my $now = time();
	my $expire_keys  = $now - Echolot::Config::get()->{'expire_keys'};
	my $expire_conf = $now - Echolot::Config::get()->{'expire_confs'};
	my $expire_pings = $now - Echolot::Config::get()->{'expire_pings'};

	for my $remailer_addr ( keys %{$self->{'METADATA'}->{'remailers'}} ) {
		next unless ($self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'status'} eq 'active');

		for my $type ( keys %{$self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'keys'}} ) {
			for my $key ( keys %{$self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'keys'}->{$type}} ) {
				if ($self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'keys'}->{$type}->{$key}->{'last_update'} < $expire_keys) {
					# FIXME logging and such
					print "Expiring $remailer_addr, key, $type, $key\n"
						if Echolot::Config::get()->{'verbose'};
					$self->pingdata_close_one($remailer_addr, $type, $key, 'delete');
					delete $self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'keys'}->{$type}->{$key};
				};
			};
			delete $self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'keys'}->{$type}
				unless (scalar keys %{$self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'keys'}->{$type}});
		};
		delete $self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'keys'}
			unless (scalar keys %{$self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'keys'}});

		delete $self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'conf'}
			if (defined $self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'conf'} &&
			   ($self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'conf'}->{'last_update'} < $expire_conf));

		$self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'status'} = 'expired'
			unless ( defined ($self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'conf'}) ||
			         defined ($self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'keys'}));


		for my $type ( keys %{$self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'keys'}} ) {
			for my $key ( keys %{$self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'keys'}->{$type}} ) {
				my @out  = grep {$_      > $expire_pings} Echolot::Globals::get()->{'storage'}->get_pings($remailer_addr, $type, $key, 'out');
				my @done = grep {$_->[0] > $expire_pings} Echolot::Globals::get()->{'storage'}->get_pings($remailer_addr, $type, $key, 'done');


				# write ping to done
				my $fh = $self->get_ping_fh($remailer_addr, $type, $key, 'done') or
					cluck ("$remailer_addr; type=$type; key=$key has no assigned filehandle for done pings"),
					return 0;
				seek($fh, 0, SEEK_SET) or
					cluck("Cannot seek to start of $remailer_addr out pings: $!"),
					return 0;
				truncate($fh, 0) or
					cluck("Cannot truncate done pings file for remailer $remailer_addr; key=$key file to zero length: $!"),
					return 0;
				for my $done (@done) {
					print($fh $done->[0]." ".$done->[1]."\n") or
						cluck("Error when writing to $remailer_addr out pings: $!"),
						return 0;
				};
				$fh->flush();

				# rewrite outstanding pings
				$fh = $self->get_ping_fh($remailer_addr, $type, $key, 'out') or
					cluck ("$remailer_addr; type=$type; key=$key has no assigned filehandle for out pings"),
					return 0;
				seek($fh, 0, SEEK_SET) or
					cluck("Cannot seek to start of outgoing pings file for remailer $remailer_addr; key=$key: $!"),
					return 0;
				truncate($fh, 0) or
					cluck("Cannot truncate outgoing pings file for remailer $remailer_addr; key=$key file to zero length: $!"),
					return 0;
				print($fh (join "\n", @out), (scalar @out ? "\n" : '') ) or
					cluck("Error when writing to outgoing pings file for remailer $remailer_addr; key=$key file: $!"),
					return 0;
				$fh->flush();
			};
		};
	};



};


# sub convert($) {
# 	my ($self) = @_;
# 
# 	for my $remailer_addr ( keys %{$self->{'METADATA'}->{'remailers'}} ) {
# 		for my $type ( keys %{$self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'keys'}} ) {
# 			for my $key ( keys %{$self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'keys'}->{$type}} ) {
# 				if (defined $self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'stats'}->{$type}->{$key}) {
# 					$self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'keys'}->{$type}->{$key}->{'stats'} = 
# 						$self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'stats'}->{$type}->{$key};
# 				};
# 			};
# 		};
# 		delete $self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'stats'};
# 	};
# 
# 	$self->commit();
# };
#
# sub convert($) {
# 	my ($self) = @_;
# 
# 	for my $remailer_addr ( keys %{$self->{'METADATA'}->{'addresses'}} ) {
# 		$self->{'METADATA'}->{'addresses'}->{$remailer_addr}->{'fetch'} = 1;
# 		$self->{'METADATA'}->{'addresses'}->{$remailer_addr}->{'pingit'} = 1;
# 		$self->{'METADATA'}->{'addresses'}->{$remailer_addr}->{'showit'} = 0;
# 		delete $self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'pingit'};
# 		delete $self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'showit'};
# 	};
# 
# 	$self->commit();
# };

=back

=cut

# vim: set ts=4 shiftwidth=4:
