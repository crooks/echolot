package Echolot::Storage::File;

# (c) 2002 Peter Palfrader <peter@palfrader.org>
# $Id: File.pm,v 1.44 2003/01/14 05:25:35 weasel Exp $
#

=pod

=head1 Name

Echolot::Storage::File - Storage backend for echolot

=head1 DESCRIPTION

This package provides several functions for data storage for echolot.

=over

=cut

use strict;
use Data::Dumper;
use IO::Handle;
use English;
use Fcntl ':flock'; # import LOCK_* constants
#use Fcntl ':seek'; # import SEEK_* constants
use POSIX; # import SEEK_* constants (older perls don't have SEEK_ in Fcntl)
use Echolot::Tools;
use Echolot::Log;

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

delete @ENV{'IFS', 'CDPATH', 'ENV', 'BASH_ENV'};

my $METADATA_VERSION = 1;

sub new {
	my ($class, %params) = @_;
	my $self = {};
	bless $self, $class;

	$self->{'METADATA_FILE_IS_NEW'} = 0;

	defined($params{'datadir'}) or
		confess ('No datadir option passed to new');
	$self->{'datadir'} = $params{'datadir'};
	$self->{'DELAY_COMMIT'} = 0;

	$self->delay_commit();
	$self->metadata_open() or
		confess ('Opening Metadata  failed. Exiting');
	$self->metadata_read() or
		confess ('Reading Metadata from Storage failed. Exiting');
	$self->pingdata_open() or
		confess ('Opening Ping files failed. Exiting');
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
			Echolot::Log::warn("Cannot open $filename for reading: $!."),
			return 0;
	} else {
		$self->{'METADATA_FILE_IS_NEW'} = 1;
		open($self->{'METADATA_FH'}, '+>' . $filename) or 
			Echolot::Log::warn("Cannot open $filename for reading: $!."),
			return 0;
	};
	flock($self->{'METADATA_FH'}, LOCK_EX) or
		Echolot::Log::warn("Cannot get exclusive lock on $filename: $!."),
		return 0;
	return 1;
};

sub metadata_close($) {
	my ($self) = @_;

	flock($self->{'METADATA_FH'}, LOCK_UN) or
		Echolot::Log::warn("Error when releasing lock on metadata file: $!."),
		return -1;
	close($self->{'METADATA_FH'}) or
		Echolot::Log::warn("Error when closing metadata file: $!."),
		return 0;
	return 1;
};


sub metadata_read($) {
	my ($self) = @_;

	if ($self->{'METADATA_FILE_IS_NEW'}) { 
		$self->{'METADATA'}->{'version'} = $METADATA_VERSION;
		$self->{'METADATA'}->{'addresses'} = {};
		$self->{'METADATA'}->{'remailers'} = {};

		$self->{'METADATA_FILE_IS_NEW'} = 0;
		$self->commit();
	} else {
		$self->{'METADATA'} = ();
		seek($self->{'METADATA_FH'}, 0, SEEK_SET) or
			Echolot::Log::warn("Cannot seek to start of metadata file: $!."),
			return 0;
		{
			local $/ = undef;
			my $fh = $self->{'METADATA_FH'};
			my $metadata_code = <$fh>;
			($metadata_code) = $metadata_code =~ /^(.*)$/s;
			my $METADATA;
			eval ($metadata_code);
			$self->{'METADATA'} = $METADATA;
		};
		$EVAL_ERROR and
			confess("Error when reading from metadata file: $EVAL_ERROR"),
			return 0;

		defined($self->{'METADATA'}->{'version'}) or
			confess("Stored data lacks version header"),
			return 0;
		($self->{'METADATA'}->{'version'} == ($METADATA_VERSION)) or
			Echolot::Log::warn("Metadata version mismatch ($self->{'METADATA'}->{'version'} vs. $METADATA_VERSION)."),
			return 0;
	};

	defined($self->{'METADATA'}->{'secret'}) or
		$self->{'METADATA'}->{'secret'} = Echolot::Tools::make_random ( 16, armor => 1 ),
		$self->commit();

	return 1;
};

sub metadata_write($) {
	my ($self) = @_;

	my $data = Data::Dumper->Dump( [ $self->{'METADATA'} ], [ 'METADATA' ] );
	my $fh = $self->{'METADATA_FH'};

	seek($fh, 0, SEEK_SET) or
		Echolot::Log::warn("Cannot seek to start of metadata file: $!."),
		return 0;
	truncate($fh, 0) or
		Echolot::Log::warn("Cannot truncate metadata file to zero length: $!."),
		return 0;
	print($fh "# vim:set syntax=perl:\n") or
		Echolot::Log::warn("Error when writing to metadata file: $!."),
		return 0;
	print($fh $data) or
		Echolot::Log::warn("Error when writing to metadata file: $!."),
		return 0;
	$fh->flush();

	return 1;
};

sub metadata_backup($) {
	my ($self) = @_;

	my $filename = $self->{'datadir'} .'/'. $CONSTANTS->{'metadatafile'};
	for (my $i=Echolot::Config::get()->{'metadata_backup_count'} - 1; $i>=0; $i--) {
		rename ($filename.'.'.($i)      , $filename.'.'.($i+1));
		rename ($filename.'.'.($i).'.gz', $filename.'.'.($i+1).'.gz');
	};
	$filename .= '.1';


	my $data = Data::Dumper->Dump( [ $self->{'METADATA'} ], [ 'METADATA' ] );
	my $fh = new IO::Handle;
	open ($fh, '>'.$filename) or
		Echolot::Log::warn("Cannot open $filename for writing: $!."),
		return 0;
	print($fh "# vim:set syntax=perl:\n") or
		Echolot::Log::warn("Error when writing to metadata file: $!."),
		return 0;
	print($fh $data) or
		Echolot::Log::warn("Error when writing to metadata file: $!."),
		return 0;
	$fh->flush();
	close($fh) or
		Echolot::Log::warn("Error when closing metadata file: $!."),
		return 0;
	
	if (Echolot::Config::get()->{'gzip'}) {
		system(Echolot::Config::get()->{'gzip'}, $filename) and
			Echolot::Log::warn("Gziping $filename failed."),
			return 0;
	};

	return 1;
};




sub pingdata_open_one($$$$) {
	my ($self, $remailer_addr, $type, $key) = @_;
	
	defined ($self->{'METADATA'}->{'remailers'}->{$remailer_addr}) or
		Echolot::Log::cluck ("$remailer_addr does not exist in Metadata."),
		return 0;
	defined ($self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'keys'}) or
		Echolot::Log::cluck ("$remailer_addr has no keys in Metadata."),
		return 0;
	defined ($self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'keys'}->{$type}) or
		Echolot::Log::cluck ("$remailer_addr type $type does not exist in Metadata."),
		return 0;
	defined ($self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'keys'}->{$type}->{$key}) or
		Echolot::Log::cluck ("$remailer_addr type $type key $key does not exist in Metadata."),
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
				Echolot::Log::warn("Cannot open $filename.$direction for reading: $!."),
				return 0;
			$self->{'PING_FHS'}->{$remailer_addr}->{$type}->{$key}->{$direction} = $fh;
		} else {
			open($fh, '+>' . $filename.'.'.$direction) or 
				Echolot::Log::warn("Cannot open $filename.$direction for reading: $!."),
				return 0;
			$self->{'PING_FHS'}->{$remailer_addr}->{$type}->{$key}->{$direction} = $fh;
		};
		flock($fh, LOCK_EX) or
			Echolot::Log::warn("Cannot get exclusive lock on $remailer_addr $type $key $direction pings: $!."),
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
		Echolot::Log::cluck("$remailer_addr does not exist in Metadata."),
		return 0;
	
	my @pings;
	my $fh = $self->{'PING_FHS'}->{$remailer_addr}->{$type}->{$key}->{$direction};

	defined ($fh) or
		$self->pingdata_open_one($remailer_addr, $type, $key),
		$fh = $self->{'PING_FHS'}->{$remailer_addr}->{$type}->{$key}->{$direction};
		defined ($fh) or
			Echolot::Log::warn ("$remailer_addr; type=$type; key=$key has no assigned filehandle for $direction pings."),
			return 0;

	return $fh;
};

sub pingdata_close_one($$$$;$) {
	my ($self, $remailer_addr, $type, $key, $delete) = @_;

	for my $direction ( keys %{$self->{'PING_FHS'}->{$remailer_addr}->{$type}->{$key}} ) {
		my $fh = $self->{'PING_FHS'}->{$remailer_addr}->{$type}->{$key}->{$direction};

		flock($fh, LOCK_UN) or
			Echolot::Log::warn("Error when releasing lock on $remailer_addr type $type key $key direction $direction pings: $!."),
			return 0;
		close ($fh) or
				Echolot::Log::warn("Error when closing $remailer_addr type $type key $key direction $direction pings: $!."),
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
					Echolot::Log::debug("Error when calling pingdata_close_one with $remailer_addr type $type key $key."),
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
		Echolot::Log::warn ("$remailer_addr; type=$type; key=$key has no assigned filehandle for $direction pings."),
		return 0;

	seek($fh, 0, SEEK_SET) or
		Echolot::Log::warn("Cannot seek to start of $remailer_addr type $type key $key direction $direction pings: $!."),
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
		Echolot::Log::cluck ("$remailer_addr; type=$type; key=$key has no assigned filehandle for out pings."),
		return 0;

	seek($fh, 0, SEEK_END) or
		Echolot::Log::warn("Cannot seek to end of $remailer_addr; type=$type; key=$key; out pings: $!."),
		return 0;
	print($fh $sent_time."\n") or
		Echolot::Log::warn("Error when writing to $remailer_addr; type=$type; key=$key; out pings: $!."),
		return 0;
	$fh->flush();
	Echolot::Log::info("registering pingout for $remailer_addr ($type; $key).");

	return 1;
};

sub register_pingdone($$$$$) {
	my ($self, $remailer_addr, $type, $key, $sent_time, $latency) = @_;
	
	defined ($self->{'METADATA'}->{'remailers'}->{$remailer_addr}) or
		Echolot::Log::cluck ("$remailer_addr does not exist in Metadata."),
		return 0;

	my @outpings = $self->get_pings($remailer_addr, $type, $key, 'out');
	my $origlen = scalar (@outpings);
	@outpings = grep { $_ != $sent_time } @outpings;
	($origlen == scalar (@outpings)) and
		Echolot::Log::info("No ping outstanding for $remailer_addr, $key, ".(scalar localtime $sent_time)."."),
		return 1;
	
	# write ping to done
	my $fh = $self->get_ping_fh($remailer_addr, $type, $key, 'done') or
		Echolot::Log::cluck ("$remailer_addr; type=$type; key=$key has no assigned filehandle for done pings."),
		return 0;
	seek($fh, 0, SEEK_END) or
		Echolot::Log::warn("Cannot seek to end of $remailer_addr out pings: $!."),
		return 0;
	print($fh $sent_time." ".$latency."\n") or
		Echolot::Log::warn("Error when writing to $remailer_addr out pings: $!."),
		return 0;
	$fh->flush();
	
	# rewrite outstanding pings
	$fh = $self->get_ping_fh($remailer_addr, $type, $key, 'out') or
		Echolot::Log::cluck ("$remailer_addr; type=$type; key=$key has no assigned filehandle for out pings."),
		return 0;
	seek($fh, 0, SEEK_SET) or
		Echolot::Log::warn("Cannot seek to start of outgoing pings file for remailer $remailer_addr; key=$key: $!."),
		return 0;
	truncate($fh, 0) or
		Echolot::Log::warn("Cannot truncate outgoing pings file for remailer $remailer_addr; key=$key file to zero length: $!."),
		return 0;
	print($fh (join "\n", @outpings), (scalar @outpings ? "\n" : '') ) or
		Echolot::Log::warn("Error when writing to outgoing pings file for remailer $remailer_addr; key=$key file: $!."),
		return 0;
	$fh->flush();
	Echolot::Log::info("registering pingdone from ".(scalar localtime $sent_time)." with latency $latency for $remailer_addr ($type; $key).");
	
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

sub get_address($$) {
	my ($self, $addr) = @_;

	defined ($self->{'METADATA'}->{'addresses'}->{$addr}) or
		Echolot::Log::cluck ("$addr does not exist in Metadata."),
		return undef;
	
	my $result = {
		status  => $self->{'METADATA'}->{'addresses'}->{$addr}->{'status'},
		id      => $self->{'METADATA'}->{'addresses'}->{$addr}->{'id'},
		address => $_,
		fetch   => $self->{'METADATA'}->{'addresses'}->{$addr}->{'fetch'},
		showit  => $self->{'METADATA'}->{'addresses'}->{$addr}->{'showit'},
		resurrection_ttl => $self->{'METADATA'}->{'addresses'}->{$addr}->{'resurrection_ttl'},
	};

	return $result;
};

sub get_addresses($) {
	my ($self) = @_;

	my @addresses = keys %{$self->{'METADATA'}->{'addresses'}};
	my @return_data = map { $self->get_address($_); } @addresses;
	return @return_data;
};

sub add_address($$) {
	my ($self, $addr) = @_;
	
	my @all_addresses = $self->get_addresses();
	my $maxid = $self->{'METADATA'}->{'addresses_maxid'};
	unless (defined $maxid) {
		$maxid = 0;
		for my $addr (@all_addresses) {
			if ($addr->{'id'} > $maxid) {
				$maxid = $addr->{'id'};
			};
		};
	};



	# FIXME logging and such
	Echolot::Log::info("Adding address $addr.");
	
	my $remailer = {
		id => $maxid + 1,
		status => 'active',
		ttl => Echolot::Config::get()->{'addresses_default_ttl'},
		fetch  => Echolot::Config::get()->{'fetch_new'},
		pingit => Echolot::Config::get()->{'ping_new'},
		showit => Echolot::Config::get()->{'show_new'},
	};
	$self->{'METADATA'}->{'addresses'}->{$addr} = $remailer;
	$self->{'METADATA'}->{'addresses_maxid'} = $maxid+1;
	$self->commit();

	return 1;
};

sub set_stuff($@) {
	my ($self, @args) = @_;

	my ($addr, $setting) = @args;
	my $args = join(', ', @args);

	defined ($addr) or
		Echolot::Log::cluck ("Could not get address for '$args'."),
		return 0;
	defined ($setting) or
		Echolot::Log::cluck ("Could not get setting for '$args'."),
		return 0;
	
	defined ($self->{'METADATA'}->{'addresses'}->{$addr}) or
		Echolot::Log::warn ("Address $addr does not exist."),
		return 0;
	

	if ($setting =~ /^(pingit|fetch|showit)=(on|off)$/) {
		my $option = $1;
		my $value = $2;
		Echolot::Log::info("Setting $option to $value for $addr");
		$self->{'METADATA'}->{'addresses'}->{$addr}->{$option} = ($value eq 'on');
	} else {
		Echolot::Log::warn ("Don't know what to do with '$setting' for $addr."),
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
		Echolot::Log::cluck("Searching for address by id '$id' gives more than one result.");
	};
	my %return_data = %{$self->{'METADATA'}->{'addresses'}->{$addresses[0]}};
	$return_data{'address'} = $addresses[0];
	return \%return_data;
};

sub decrease_ttl($$) {
	my ($self, $address) = @_;
	
	defined ($self->{'METADATA'}->{'addresses'}->{$address}) or
		Echolot::Log::cluck ("$address does not exist in Metadata address list."),
		return 0;
	$self->{'METADATA'}->{'addresses'}->{$address}->{'ttl'} --;
	$self->{'METADATA'}->{'addresses'}->{$address}->{'status'} = 'ttl timeout',
		Echolot::Log::info("Remailer $address disabled: ttl expired."),
		$self->{'METADATA'}->{'addresses'}->{$address}->{'resurrection_ttl'} = Echolot::Config::get()->{'check_resurrection_ttl'}
		if ($self->{'METADATA'}->{'addresses'}->{$address}->{'ttl'} <= 0);
		# FIXME have proper logging
	$self->commit();
	return 1;
};

sub decrease_resurrection_ttl($$) {
	my ($self, $address) = @_;
	
	defined ($self->{'METADATA'}->{'addresses'}->{$address}) or
		Echolot::Log::cluck ("$address does not exist in Metadata address list."),
		return 0;
	($self->{'METADATA'}->{'addresses'}->{$address}->{'status'} eq 'ttl timeout') or
		Echolot::Log::cluck ("$address is not in ttl timeout status."),
		return 0;
	$self->{'METADATA'}->{'addresses'}->{$address}->{'resurrection_ttl'} --;
	$self->{'METADATA'}->{'addresses'}->{$address}->{'status'} = 'dead',
		Echolot::Log::info("Remailer $address is dead."),
		if ($self->{'METADATA'}->{'addresses'}->{$address}->{'resurrection_ttl'} <= 0);
		# FIXME have proper logging
	$self->commit();
	return 1;
};

sub restore_ttl($$) {
	my ($self, $address) = @_;
	
	defined ($self->{'METADATA'}->{'addresses'}->{$address}) or
		Echolot::Log::cluck ("$address does not exist in Metadata address list."),
		return 0;
	defined ($self->{'METADATA'}->{'addresses'}->{$address}->{'status'}) or
		Echolot::Log::cluck ("$address does exist in Metadata address list but does not have status defined."),
		return 0;
	Echolot::Log::info("Remailer $address is alive and active again.")
		unless ($self->{'METADATA'}->{'addresses'}->{$address}->{'status'} eq 'active');
	$self->{'METADATA'}->{'addresses'}->{$address}->{'ttl'} = Echolot::Config::get()->{'addresses_default_ttl'};
	delete $self->{'METADATA'}->{'addresses'}->{$address}->{'resurrection_ttl'};
	$self->{'METADATA'}->{'addresses'}->{$address}->{'status'} = 'active' if
		($self->{'METADATA'}->{'addresses'}->{$address}->{'status'} eq 'ttl timeout' ||
		 $self->{'METADATA'}->{'addresses'}->{$address}->{'status'} eq 'dead');
	$self->commit();
	return 1;
};

sub not_a_remailer($$) {
	my ($self, $id) = @_;
	
	my $remailer = $self->get_address_by_id($id);
	defined $remailer or
		Echolot::Log::cluck("No remailer found for id '$id'."),
		return 0;
	my $address = $remailer->{'address'};
	defined ($self->{'METADATA'}->{'addresses'}->{$address}) or
		Echolot::Log::cluck ("$address does not exist in Metadata address list."),
		return 0;
	$self->{'METADATA'}->{'addresses'}->{$address}->{'status'}  = 'disabled by user reply: is not a remailer';

	Echolot::Log::info("Setting $id, $address to disabled by user reply.");

	$self->commit();
	return 1;
};

sub set_caps($$$$$$;$) {
	my ($self, $type, $caps, $nick, $address, $timestamp, $dont_expire) = @_;
	if (! defined $self->{'METADATA'}->{'remailers'}->{$address} ||
	    ! defined $self->{'METADATA'}->{'remailers'}->{$address}->{'status'} ) {
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
			Echolot::Log::info("Stored data is already newer for remailer $nick.");
			return 1;
		};
		$conf->{'last_update'} = $timestamp;
		if ($conf->{'nick'} ne $nick) {
			Echolot::Log::info($conf->{'nick'}." was renamed to $nick.");
			$conf->{'nick'} = $nick;
		};
		if ($conf->{'capabilities'} ne $caps) {
			Echolot::Log::info("$nick has a new caps string '$caps' old: '".$conf->{'capabilities'}."'.");
			$conf->{'capabilities'} = $caps;
		};
		if ($conf->{'type'} ne $type) {
			Echolot::Log::info("$nick has a new type string '$type'.");
			$conf->{'type'} = $type;
		};
	};

	if (defined $dont_expire) {
		$self->{'METADATA'}->{'remailers'}->{$address}->{'conf'}->{'dont_expire'} = $dont_expire;
	};
	
	$self->commit();
	
	return 1;
};

sub set_key($$$$$$$$$) {
	my ($self, $type, $nick, $address, $key, $keyid, $version, $caps, $summary, $timestamp) = @_;

	(defined $address) or
		Echolot::Log::cluck ("$address not defined in set_key.");
	
	if (! defined $self->{'METADATA'}->{'remailers'}->{$address}) {
		$self->{'METADATA'}->{'remailers'}->{$address} =
			{
				status => 'active'
			};
	} else {
		$self->{'METADATA'}->{'remailers'}->{$address}->{'status'} = 'active'
			if (!defined ($self->{'METADATA'}->{'remailers'}->{$address}->{'status'}) ||
			   ($self->{'METADATA'}->{'remailers'}->{$address}->{'status'} eq 'expired'));
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
			Echolot::Log::info("Stored data is already newer for remailer $nick.");
			return 1;
		};
		$keyref->{'last_update'} = $timestamp;
		if ($keyref->{'nick'} ne $nick) {
			Echolot::Log::info("$nick has a new key nick string '$nick' old: '".$keyref->{'nick'}."'.");
			$keyref->{'nick'} = $nick;
		};
		if ($keyref->{'summary'} ne $summary) {
			Echolot::Log::info("$nick has a new key summary string '$summary' old: '".$keyref->{'summary'}."'.");
			$keyref->{'summary'} = $summary;
		};
		if ($keyref->{'key'} ne $key) {
			#Echolot::Log::info("$nick has a new key string '$key' old: '".$keyref->{'key'}."' - This probably should not happen.");
			Echolot::Log::info("$nick has a new key string for same keyid $keyid.");
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
		Echolot::Log::cluck ("$remailer does not exist in Metadata remailer list."),
		return 0;

	return () unless defined $self->{'METADATA'}->{'remailers'}->{$remailer}->{'keys'};
	my @types = keys %{$self->{'METADATA'}->{'remailers'}->{$remailer}->{'keys'}};
	return @types;
};

sub has_type($$$) {
	my ($self, $remailer, $type) = @_;

	defined ($self->{'METADATA'}->{'remailers'}->{$remailer}) or
		Echolot::Log::cluck ("$remailer does not exist in Metadata remailer list."),
		return 0;

	return 0 unless defined $self->{'METADATA'}->{'remailers'}->{$remailer}->{'keys'};
	return 0 unless defined $self->{'METADATA'}->{'remailers'}->{$remailer}->{'keys'}->{$type};
	return 0 unless scalar keys %{$self->{'METADATA'}->{'remailers'}->{$remailer}->{'keys'}->{$type}};
	return 1;
};

sub get_keys($$) {
	my ($self, $remailer, $type) = @_;

	defined ($self->{'METADATA'}->{'remailers'}->{$remailer}) or
		Echolot::Log::cluck ("$remailer does not exist in Metadata remailer list."),
		return 0;

	defined ($self->{'METADATA'}->{'remailers'}->{$remailer}->{'keys'}->{$type}) or
		Echolot::Log::cluck ("$remailer does not have type '$type' in Metadata remailer list."),
		return 0;

	my @keys = keys %{$self->{'METADATA'}->{'remailers'}->{$remailer}->{'keys'}->{$type}};
	return @keys;
};

sub get_key($$$$) {
	my ($self, $remailer, $type, $key) = @_;

	defined ($self->{'METADATA'}->{'remailers'}->{$remailer}) or
		Echolot::Log::cluck ("$remailer does not exist in Metadata remailer list."),
		return 0;

	defined ($self->{'METADATA'}->{'remailers'}->{$remailer}->{'keys'}->{$type}) or
		Echolot::Log::cluck ("$remailer does not have type '$type' in Metadata remailer list."),
		return 0;

	defined ($self->{'METADATA'}->{'remailers'}->{$remailer}->{'keys'}->{$type}->{$key}) or
		Echolot::Log::cluck ("$remailer does not have key '$key' in type '$type' in Metadata remailer list."),
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
		for my $type ( keys %{$self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'keys'}} ) {
			for my $key ( keys %{$self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'keys'}->{$type}} ) {
				if ($self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'keys'}->{$type}->{$key}->{'last_update'} < $expire_keys) {
					# FIXME logging and such
					Echolot::Log::info("Expiring $remailer_addr, key, $type, $key.");
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
			   ($self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'conf'}->{'last_update'} < $expire_conf) &&
			   ! ($self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'conf'}->{'dont_expire'}));

		delete $self->{'METADATA'}->{'remailers'}->{$remailer_addr},
			next
			unless ( defined ($self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'conf'}) ||
			         defined ($self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'keys'}));


		for my $type ( keys %{$self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'keys'}} ) {
			for my $key ( keys %{$self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'keys'}->{$type}} ) {
				my @out  = grep {$_      > $expire_pings} Echolot::Globals::get()->{'storage'}->get_pings($remailer_addr, $type, $key, 'out');
				my @done = grep {$_->[0] > $expire_pings} Echolot::Globals::get()->{'storage'}->get_pings($remailer_addr, $type, $key, 'done');


				# write ping to done
				my $fh = $self->get_ping_fh($remailer_addr, $type, $key, 'done') or
					Echolot::Log::cluck ("$remailer_addr; type=$type; key=$key has no assigned filehandle for done pings."),
					return 0;
				seek($fh, 0, SEEK_SET) or
					Echolot::Log::warn("Cannot seek to start of $remailer_addr out pings: $!."),
					return 0;
				truncate($fh, 0) or
					Echolot::Log::warn("Cannot truncate done pings file for remailer $remailer_addr; key=$key file to zero length: $!."),
					return 0;
				for my $done (@done) {
					print($fh $done->[0]." ".$done->[1]."\n") or
						Echolot::Log::warn("Error when writing to $remailer_addr out pings: $!."),
						return 0;
				};
				$fh->flush();

				# rewrite outstanding pings
				$fh = $self->get_ping_fh($remailer_addr, $type, $key, 'out') or
					Echolot::Log::cluck ("$remailer_addr; type=$type; key=$key has no assigned filehandle for out pings."),
					return 0;
				seek($fh, 0, SEEK_SET) or
					Echolot::Log::warn("Cannot seek to start of outgoing pings file for remailer $remailer_addr; key=$key: $!."),
					return 0;
				truncate($fh, 0) or
					Echolot::Log::warn("Cannot truncate outgoing pings file for remailer $remailer_addr; key=$key file to zero length: $!."),
					return 0;
				print($fh (join "\n", @out), (scalar @out ? "\n" : '') ) or
					Echolot::Log::warn("Error when writing to outgoing pings file for remailer $remailer_addr; key=$key file: $!."),
					return 0;
				$fh->flush();
			};
		};
	};

	$self->commit();
	
	return 1;
};

sub delete_remailer($$) {
	my ($self, $address) = @_;

	Echolot::Log::info("Deleting remailer $address.");

	if (defined $self->{'METADATA'}->{'addresses'}->{$address}) {
		delete $self->{'METADATA'}->{'addresses'}->{$address}
	} else {
		Echolot::Log::cluck("Remailer $address does not exist in addresses.")
	};

	if (defined $self->{'METADATA'}->{'remailers'}->{$address}) {

		for my $type ( keys %{$self->{'METADATA'}->{'remailers'}->{$address}->{'keys'}} ) {
			for my $key ( keys %{$self->{'METADATA'}->{'remailers'}->{$address}->{'keys'}->{$type}} ) {
				$self->pingdata_close_one($address, $type, $key, 'delete');
			};
		};

		delete $self->{'METADATA'}->{'remailers'}->{$address}
	};

	$self->commit();
	
	return 1;
};

sub delete_remailercaps($$) {
	my ($self, $address) = @_;

	Echolot::Log::info("Deleting conf for remailer $address.");

	if (defined $self->{'METADATA'}->{'remailers'}->{$address}) {
		delete $self->{'METADATA'}->{'remailers'}->{$address}->{'conf'}
			if defined $self->{'METADATA'}->{'remailers'}->{$address}->{'conf'};
	} else {
		Echolot::Log::cluck("Remailer $address does not exist in remailers.")
	};
	$self->commit();
	
	return 1;
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
