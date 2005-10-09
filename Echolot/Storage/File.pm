package Echolot::Storage::File;

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

Echolot::Storage::File - Storage backend for echolot

=head1 DESCRIPTION

This package provides several functions for data storage for echolot.

=over

=cut

use strict;
use Data::Dumper;
use IO::Handle;
use English;
use Carp;
use Fcntl ':flock'; # import LOCK_* constants
#use Fcntl ':seek'; # import SEEK_* constants
use POSIX; # import SEEK_* constants (older perls don't have SEEK_ in Fcntl)
use Echolot::Tools;
use Echolot::Log;



my $CONSTANTS = {
	'metadatafile' => 'metadata'
};

delete @ENV{'IFS', 'CDPATH', 'ENV', 'BASH_ENV'};

my $METADATA_VERSION = 1;


=item B<new> (I<%args>)

Creates a new storage backend object.
args keys:

=over

=item I<datadir>

The basedir where this module may store it's configuration and pinging
data.

=back

=cut
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
	$self->chainpingdata_open() or
		confess ('Opening Ping files failed. Exiting');
	$self->enable_commit();
	
	return $self;
};

=item $storage->B<commit>( )

Write metadata unless B<delay_commt> is set.

=cut
sub commit($) {
	my ($self) = @_;

	if ($self->{'DELAY_COMMIT'}) {
		$self->{'COMMIT_PENDING'} = 1;
		return;
	};
	$self->metadata_write();
	$self->{'COMMIT_PENDING'} = 0;
};

=item $storage->B<delay_commit>( )

Increase B<delay_commit> by one.

=cut
sub delay_commit($) {
	my ($self) = @_;

	$self->{'DELAY_COMMIT'}++;
};

=item $storage->B<enable_commit>( I<$set_> )

Decrease B<delay_commit> by one and call C<commit> if B<delay_commit> is zero
and I<$set_pending> is true.

=cut
sub enable_commit($;$) {
	my ($self, $set_pending) = @_;

	$self->{'DELAY_COMMIT'}--;
	$self->commit() if (($self->{'COMMIT_PENDING'} || (defined $set_pending && $set_pending)) && ! $self->{'DELAY_COMMIT'});
};

=item $storage->B<finish>( )

Shut down cleanly.

=cut
sub finish($) {
	my ($self) = @_;

	$self->pingdata_close();
	$self->chainpingdata_close();
	$self->metadata_write();
	$self->metadata_close();
};




=item $storage->B<metadata_open>( )

Open metadata.

Returns 1 on success, undef on errors.

=cut
sub metadata_open($) {
	my ($self) = @_;

	$self->{'METADATA_FH'} = new IO::Handle;
	my $filename = $self->{'datadir'} .'/'. $CONSTANTS->{'metadatafile'};

	if ( -e $filename ) {
		open($self->{'METADATA_FH'}, '+<' . $filename) or 
			Echolot::Log::warn("Cannot open $filename for reading: $!."),
			return undef;
	} else {
		$self->{'METADATA_FILE_IS_NEW'} = 1;
		open($self->{'METADATA_FH'}, '+>' . $filename) or 
			Echolot::Log::warn("Cannot open $filename for reading: $!."),
			return undef;
	};
	flock($self->{'METADATA_FH'}, LOCK_EX) or
		Echolot::Log::warn("Cannot get exclusive lock on $filename: $!."),
		return undef;
	return 1;
};

=item $storage->B<metadata_close>( )

Close metadata.

Returns 1 on success, undef on errors.

=cut
sub metadata_close($) {
	my ($self) = @_;

	flock($self->{'METADATA_FH'}, LOCK_UN) or
		Echolot::Log::warn("Error when releasing lock on metadata file: $!."),
		return undef;
	close($self->{'METADATA_FH'}) or
		Echolot::Log::warn("Error when closing metadata file: $!."),
		return undef;
	return 1;
};


=item $storage->B<metadata_read>( )

Write metadata.

Returns 1 on success, undef on errors.

=cut
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
			return undef;

		defined($self->{'METADATA'}->{'version'}) or
			confess("Stored data lacks version header"),
			return undef;
		($self->{'METADATA'}->{'version'} == ($METADATA_VERSION)) or
			Echolot::Log::warn("Metadata version mismatch ($self->{'METADATA'}->{'version'} vs. $METADATA_VERSION)."),
			return undef;
	};

	defined($self->{'METADATA'}->{'secret'}) or
		$self->{'METADATA'}->{'secret'} = Echolot::Tools::make_random ( 16, armor => 1 ),
		$self->commit();

	return 1;
};

=item $storage->B<metadata_write>( )

Write metadata.

Returns 1 on success, undef on errors.

=cut
sub metadata_write($) {
	my ($self) = @_;

	my $data = Data::Dumper->Dump( [ $self->{'METADATA'} ], [ 'METADATA' ] );
	my $fh = $self->{'METADATA_FH'};

	seek($fh, 0, SEEK_SET) or
		Echolot::Log::warn("Cannot seek to start of metadata file: $!."),
		return undef;
	truncate($fh, 0) or
		Echolot::Log::warn("Cannot truncate metadata file to zero length: $!."),
		return undef;
	print($fh "# vim:set syntax=perl:\n") or
		Echolot::Log::warn("Error when writing to metadata file: $!."),
		return undef;
	print($fh $data) or
		Echolot::Log::warn("Error when writing to metadata file: $!."),
		return undef;
	$fh->flush();

	return 1;
};

=item $storage->B<metadata_backup>( )

Rotate metadata files and create a backup.

Returns 1 on success, undef on errors.

=cut
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
		return undef;
	print($fh "# vim:set syntax=perl:\n") or
		Echolot::Log::warn("Error when writing to metadata file: $!."),
		return undef;
	print($fh $data) or
		Echolot::Log::warn("Error when writing to metadata file: $!."),
		return undef;
	$fh->flush();
	close($fh) or
		Echolot::Log::warn("Error when closing metadata file: $!."),
		return undef;
	
	if (Echolot::Config::get()->{'gzip'}) {
		system(Echolot::Config::get()->{'gzip'}, $filename) and
			Echolot::Log::warn("Gziping $filename failed."),
			return undef;
	};

	return 1;
};




=item $storage->B<pingdata_open_one>( I<$remailer_addr>, I<$type>, I<$key> )

Open the pingdata file for the I<$remailer_addr>, I<$type>, and I<$key>.

Returns 1 on success, undef on errors.

=cut
sub pingdata_open_one($$$$) {
	my ($self, $remailer_addr, $type, $key) = @_;
	
	defined ($self->{'METADATA'}->{'remailers'}->{$remailer_addr}) or
		Echolot::Log::cluck ("$remailer_addr does not exist in Metadata."),
		return undef;
	defined ($self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'keys'}) or
		Echolot::Log::cluck ("$remailer_addr has no keys in Metadata."),
		return undef;
	defined ($self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'keys'}->{$type}) or
		Echolot::Log::cluck ("$remailer_addr type $type does not exist in Metadata."),
		return undef;
	defined ($self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'keys'}->{$type}->{$key}) or
		Echolot::Log::cluck ("$remailer_addr type $type key $key does not exist in Metadata."),
		return undef;
	

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
				return undef;
			$self->{'PING_FHS'}->{$remailer_addr}->{$type}->{$key}->{$direction} = $fh;
		} else {
			open($fh, '+>' . $filename.'.'.$direction) or 
				Echolot::Log::warn("Cannot open $filename.$direction for reading: $!."),
				return undef;
			$self->{'PING_FHS'}->{$remailer_addr}->{$type}->{$key}->{$direction} = $fh;
		};
		flock($fh, LOCK_EX) or
			Echolot::Log::warn("Cannot get exclusive lock on $remailer_addr $type $key $direction pings: $!."),
			return undef;
	};

	return 1;
};

=item $storage->B<pingdata_open>( )

Open all pingdata files.

Returns 1.

=cut
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

=item $storage->B<get_ping_fh>( I<$remailer_addr>, I<$type>, I<$key>, I<$direction>, I<$oknodo> )

Return the FH for the pingdata file of I<$remailer_addr>, I<$type>, I<$key>, and I<$direction>.

If $<oknodo> is set, the absense of a defined filehandle does not cause it to
be opened/created.  Instead -1 is returned.

Returns undef on error;

=cut
sub get_ping_fh($$$$$;$) {
	my ($self, $remailer_addr, $type, $key, $direction, $oknodo) = @_;

	defined ($self->{'METADATA'}->{'addresses'}->{$remailer_addr}) or
		Echolot::Log::cluck("$remailer_addr does not exist in Metadata."),
		return undef;
	
	my $fh = $self->{'PING_FHS'}->{$remailer_addr}->{$type}->{$key}->{$direction};

	unless (defined $fh) {
		return -1 if (defined $oknodo && $oknodo);

		$self->pingdata_open_one($remailer_addr, $type, $key),
		$fh = $self->{'PING_FHS'}->{$remailer_addr}->{$type}->{$key}->{$direction};
		defined ($fh) or
			Echolot::Log::warn ("$remailer_addr; type=$type; key=$key has no assigned filehandle for $direction pings."),
			return undef;
	}

	return $fh;
};

=item $storage->B<pingdata_close_one>( I<$remailer_addr>, I<$type>, I<$key> )

Close the pingdata file for the I<$remailer_addr>, I<$type>, and I<$key>.

Returns 1 on success, undef on errors.

=cut
sub pingdata_close_one($$$$;$) {
	my ($self, $remailer_addr, $type, $key, $delete) = @_;

	for my $direction ( keys %{$self->{'PING_FHS'}->{$remailer_addr}->{$type}->{$key}} ) {
		my $fh = $self->{'PING_FHS'}->{$remailer_addr}->{$type}->{$key}->{$direction};

		flock($fh, LOCK_UN) or
			Echolot::Log::warn("Error when releasing lock on $remailer_addr type $type key $key direction $direction pings: $!."),
			return undef;
		close ($fh) or
			Echolot::Log::warn("Error when closing $remailer_addr type $type key $key direction $direction pings: $!."),
			return undef;

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

=item $storage->B<pingdata_close>( )

Close all pingdata files.

Returns 1 on success, undef on errors.

=cut
sub pingdata_close($) {
	my ($self) = @_;

	for my $remailer_addr ( keys %{$self->{'PING_FHS'}} ) {
		for my $type ( keys %{$self->{'PING_FHS'}->{$remailer_addr}} ) {
			for my $key ( keys %{$self->{'PING_FHS'}->{$remailer_addr}->{$type}} ) {
				$self->pingdata_close_one($remailer_addr, $type, $key) or
					Echolot::Log::debug("Error when calling pingdata_close_one with $remailer_addr type $type key $key."),
					return undef;
			};
		};
	};
	return 1;
};

=item $storage->B<get_pings>( I<$remailer_addr>, I<$type>, I<$key>, I<$direction> )

Return an array of ping data for I<$remailer_addr>, I<$type>, I<$key>, and I<$direction>.

If direction is B<out> then it's an array of scalar (the send timestamps).

If direction is B<done> then it's an array of array references each having two
items: the send time and the latency.

Returns undef on error;

=cut
sub get_pings($$$$$) {
	my ($self, $remailer_addr, $type, $key, $direction) = @_;

	my @pings;

	my $fh = $self->get_ping_fh($remailer_addr, $type, $key, $direction, 1);
	(defined $fh) or
		Echolot::Log::cluck ("$remailer_addr; type=$type; key=$key has no assigned filehandle for out pings.");
	($fh == -1) and
		Echolot::Log::info ("$remailer_addr; type=$type; key=$key has no assigned filehandle for $direction pings (key has expired, or not available yet)."),
		return ();

	seek($fh, 0, SEEK_SET) or
		Echolot::Log::warn("Cannot seek to start of $remailer_addr type $type key $key direction $direction pings: $! ($fh)."),
		return undef;

	if ($direction eq 'out') {
		@pings = map {chomp; $_; } <$fh>;
	} elsif ($direction eq 'done') {
		@pings = map {chomp; my @arr = split (/\s+/, $_, 2); \@arr; } <$fh>;
	} else {
		confess("What the hell am I doing here? $remailer_addr; $type; $key; $direction"),
		return undef;
	};
	return @pings;
};





=item $storage->B<register_pingout>( I<$remailer_addr>, I<$type>, I<$key>, I<$sent_time> )

Register a ping sent to I<$remailer_addr>, I<$type>, I<$key> and I$<sent_time>.

Returns 1 on success, undef on errors.

=cut
sub register_pingout($$$$$) {
	my ($self, $remailer_addr, $type, $key, $sent_time) = @_;
	
	my $fh = $self->get_ping_fh($remailer_addr, $type, $key, 'out') or
		Echolot::Log::cluck ("$remailer_addr; type=$type; key=$key has no assigned filehandle for out pings."),
		return undef;

	seek($fh, 0, SEEK_END) or
		Echolot::Log::warn("Cannot seek to end of $remailer_addr; type=$type; key=$key; out pings: $!."),
		return undef;
	print($fh $sent_time."\n") or
		Echolot::Log::warn("Error when writing to $remailer_addr; type=$type; key=$key; out pings: $!."),
		return undef;
	$fh->flush();
	Echolot::Log::debug("registering pingout for $remailer_addr ($type; $key).");

	return 1;
};

=item $storage->B<register_pingdone>( I<$remailer_addr>, I<$type>, I<$key>, I<$sent_time>, I<$latency> )

Register that the ping sent to I<$remailer_addr>, I<$type>, I<$key> at
I$<sent_time> has returned with latency I<$latency>.

Returns 1 on success, undef on errors.

=cut
sub register_pingdone($$$$$$) {
	my ($self, $remailer_addr, $type, $key, $sent_time, $latency) = @_;
	
	defined ($self->{'METADATA'}->{'addresses'}->{$remailer_addr}) or
		Echolot::Log::warn ("$remailer_addr does not exist in Metadata."),
		return undef;

	my @outpings = $self->get_pings($remailer_addr, $type, $key, 'out');
	my $origlen = scalar (@outpings);
	@outpings = grep { $_ != $sent_time } @outpings;
	($origlen == scalar (@outpings)) and
		Echolot::Log::info("No ping outstanding for $remailer_addr, $key, ".(scalar localtime $sent_time)."."),
		return 1;
	
	# write ping to done
	my $fh = $self->get_ping_fh($remailer_addr, $type, $key, 'done') or
		Echolot::Log::cluck ("$remailer_addr; type=$type; key=$key has no assigned filehandle for done pings."),
		return undef;
	seek($fh, 0, SEEK_END) or
		Echolot::Log::warn("Cannot seek to end of $remailer_addr done pings: $!."),
		return undef;
	print($fh $sent_time." ".$latency."\n") or
		Echolot::Log::warn("Error when writing to $remailer_addr done pings: $!."),
		return undef;
	$fh->flush();

	# rewrite outstanding pings
	$fh = $self->get_ping_fh($remailer_addr, $type, $key, 'out') or
		Echolot::Log::cluck ("$remailer_addr; type=$type; key=$key has no assigned filehandle for out pings."),
		return undef;
	seek($fh, 0, SEEK_SET) or
		Echolot::Log::warn("Cannot seek to start of outgoing pings file for remailer $remailer_addr; key=$key: $!."),
		return undef;
	truncate($fh, 0) or
		Echolot::Log::warn("Cannot truncate outgoing pings file for remailer $remailer_addr; key=$key file to zero length: $!."),
		return undef;
	print($fh (join "\n", @outpings), (scalar @outpings ? "\n" : '') ) or
		Echolot::Log::warn("Error when writing to outgoing pings file for remailer $remailer_addr; key=$key file: $!."),
		return undef;
	$fh->flush();
	Echolot::Log::debug("registering pingdone from ".(scalar localtime $sent_time)." with latency $latency for $remailer_addr ($type; $key).");

	return 1;
};






=item $storage->B<chainpingdata_open_one>( I<$chaintype> )

Open the pingdata file for I<$chaintype> type chain pings.

Returns 1 on success, undef on errors.

=cut
sub chainpingdata_open_one($$) {
	my ($self, $type) = @_;

	my $filename = $self->{'datadir'} .'/chainpings.'.$type;

	for my $direction ('out', 'done') {
		my $fh = new IO::Handle;
		if ( -e $filename.'.'.$direction ) {
			open($fh, '+<' . $filename.'.'.$direction) or 
				Echolot::Log::warn("Cannot open $filename.$direction for reading: $!."),
				return undef;
			$self->{'CHAINPING_FHS'}->{$type}->{$direction} = $fh;
		} else {
			open($fh, '+>' . $filename.'.'.$direction) or 
				Echolot::Log::warn("Cannot open $filename.$direction for reading: $!."),
				return undef;
			$self->{'CHAINPING_FHS'}->{$type}->{$direction} = $fh;
		};
		flock($fh, LOCK_EX) or
			Echolot::Log::warn("Cannot get exclusive lock on $filename.$direction pings: $!."),
			return undef;
	};

	return 1;
};

=item $storage->B<chainpingdata_open>( )

Open all chainpingdata files.

Returns 1.

=cut
sub chainpingdata_open($) {
	my ($self) = @_;

	for my $type ( keys %{Echolot::Config::get()->{'which_chainpings'}} ) {
		$self->chainpingdata_open_one($type);
	};

	return 1;
};


=item $storage->B<get_chainping_fh>( I<$type>, I<$direction> )

Return the FH for the chainpingdata file of I<$type>, and I<$direction>.

Returns undef on error;

=cut
sub get_chainping_fh($$$) {
	my ($self, $type, $direction) = @_;

	my $fh = $self->{'CHAINPING_FHS'}->{$type}->{$direction};

	defined ($fh) or
		$self->chainpingdata_open_one($type),
		$fh = $self->{'CHAINPING_FHS'}->{$type}->{$direction};
		defined ($fh) or
			Echolot::Log::warn ("chainping $type has no assigned filehandle for $direction chainpings."),
			return undef;

	return $fh;
};

=item $storage->B<chainpingdata_close_one>( I<$type> )

Close the chainpingdata file for I<$type>.

Returns 1 on success, undef on errors.

=cut
sub chainpingdata_close_one($) {
	my ($self, $type) = @_;

	for my $direction ( keys %{$self->{'CHAINPING_FHS'}->{$type}} ) {
		my $fh = $self->{'CHAINPING_FHS'}->{$type}->{$direction};

		flock($fh, LOCK_UN) or
			Echolot::Log::warn("Error when releasing lock on $type direction $direction chainpings: $!."),
			return undef;
		close ($fh) or
			Echolot::Log::warn("Error when closing $type direction $direction chainpings: $!."),
			return undef;
	};

	delete $self->{'CHAINPING_FHS'}->{$type};

	return 1;
};

=item $storage->B<chainpingdata_close>( )

Close all chainpingdata files.

Returns 1 on success, undef on errors.

=cut
sub chainpingdata_close($) {
	my ($self) = @_;

	for my $type ( keys %{$self->{'CHAINPING_FHS'}} ) {
		$self->chainpingdata_close_one($type) or
			Echolot::Log::debug("Error when calling chainpingdata_close_one with type $type."),
			return undef;
	};
	return 1;
};



=item $storage->B<get_chainpings>( I<$chaintype> )

Return chainping data for I<$chaintype>.

The result is a reference to a hash having two entries: out and done.

Each of them is a reference to an array of single pings.  Each ping is a hash
reference with the hash having the keys B<sent>, B<addr1>, B<type1>, B<key1>,
B<addr2>, B<type2>, B<key2>, and in case of received pings B<lat>.

Out currently includes all sent pings - also those that allready arrived.
This is different from the get_pings() function above.

Returns undef on error.

=cut
sub get_chainpings($$) {
	my ($self, $chaintype) = @_;

	my $fh = $self->get_chainping_fh($chaintype, 'out') or
		Echolot::Log::warn ("have no assigned filehandle for $chaintype out chainpings."),
		return undef;
	seek($fh, 0, SEEK_SET) or
		Echolot::Log::warn("Cannot seek to start of $chaintype out chainpings $!."),
		return undef;
	my @out =
		map {
			chomp;
			my @a = split;
			Echolot::Log::warn("'$_' has not 7 fields") if (scalar @a < 7);
			{	sent  => $a[0],
				addr1 => $a[1],
				type1 => $a[2],
				key1  => $a[3],
				addr2 => $a[4],
				type2 => $a[5],
				key2  => $a[6]
			}
		} <$fh>;
	my %sent = map {
		my $a = $_;
		my $key = join (' ', map ({ $a->{$_} } qw{sent addr1 type1 key1 addr2 type2 key2}));
		$key => 1
	} @out;

	$fh = $self->get_chainping_fh($chaintype, 'done') or
		Echolot::Log::warn ("assigned filehandle for $chaintype done chainpings."),
		return undef;
	seek($fh, 0, SEEK_SET) or
		Echolot::Log::warn("Cannot seek to start of $chaintype done chainpings $!."),
		return undef;
	my @done =
		grep {
			# Only list things that actually got sent - and only once
			my $a = $_;
			my $key = join (' ', map ({ $a->{$_} } qw{sent addr1 type1 key1 addr2 type2 key2}));
			my $exists = exists $sent{$key};
			delete $sent{$key};
			$exists
		}
		map {
			chomp;
			my @a = split;
			{	sent  => $a[0],
				addr1 => $a[1],
				type1 => $a[2],
				key1  => $a[3],
				addr2 => $a[4],
				type2 => $a[5],
				key2  => $a[6],
				lat   => $a[7]
			}
		} <$fh>;

	return {
		out => \@out,
		done => \@done
	};
};


=item $storage->B<register_chainpingout>( I<$chaintype>, I<$addr1>, I<$type1>, I<$key1>, I<$addr2>, I<$type2>, I<$key2>, I<$sent_time> >

Register a chain ping of type I<$chaintype> sent through I<$addr1> (I<$type1>, I<$key1>)
and I<$addr2> (I<$type2>, I<$key2>) at I$<sent_time>.

Returns 1 on success, undef on errors.

=cut
sub register_chainpingout($$$$$$$$$) {
	my ($self, $chaintype, $addr1, $type1, $key1, $addr2, $type2, $key2, $sent_time) = @_;
	
	my $fh = $self->get_chainping_fh($chaintype, 'out') or
		Echolot::Log::cluck ("chaintype $chaintype/out has no assigned filehandle."),
		return undef;

	seek($fh, 0, SEEK_END) or
		Echolot::Log::warn("Cannot seek to end of chaintype $chaintype out pings: $!."),
		return undef;
	print($fh join(' ', $sent_time, $addr1, $type1, $key1, $addr2, $type2, $key2)."\n") or
		Echolot::Log::warn("Error when writing to chaintype $chaintype out pings: $!."),
		return undef;
	$fh->flush();
	Echolot::Log::debug("registering chainping $chaintype out through $addr1 ($type1; $key1) to $addr2 ($type2; $key2).");

	return 1;
};

=item $storage->B<register_chainpingdone>( I<$chaintype>, I<$addr1>, I<$type1>, I<$key1>, I<$addr2>, I<$type2>, I<$key2>, I<$sent_time>, I<$latency> )

Register that the chain ping of type I<$chaintype> sent through I<$addr1> (I<$type1>, I<$key1>)
and I<$addr2> (I<$type2>, I<$key2>) at I$<sent_time>
has returned with latency I<$latency>.

Returns 1 on success, undef on errors.

=cut
sub register_chainpingdone($$$$$$$$$$) {
	my ($self, $chaintype, $addr1, $type1, $key1, $addr2, $type2, $key2, $sent_time, $latency) = @_;
	
	# write ping to done
	my $fh = $self->get_chainping_fh($chaintype, 'done') or
		Echolot::Log::cluck ("chaintype $chaintype/done has no assigned filehandle."),
		return undef;
	seek($fh, 0, SEEK_END) or
		Echolot::Log::warn("Cannot seek to end of $chaintype/done pings: $!."),
		return undef;
	print($fh join(' ', $sent_time, $addr1, $type1, $key1, $addr2, $type2, $key2, $latency)."\n") or
		Echolot::Log::warn("Error when writing to $chaintype/done pings: $!."),
		return undef;
	$fh->flush();
	Echolot::Log::debug("registering chainpingdone from ".(scalar localtime $sent_time)." with latency $latency chainping $chaintype out through $addr1 ($type1; $key1) to $addr2 ($type2; $key2).");

	return 1;
};

=item $storage->B<add_prospective_address>( I<$addr>, I<$reason>, I<$additional> )

Add I<$addr> to the list of prospective remailers with I<$reason> and
I<$additional> information.

Returns 1.

=cut
sub add_prospective_address($$$$) {
	my ($self, $addr, $reason, $additional) = @_;

	return 1 if defined $self->{'METADATA'}->{'addresses'}->{$addr};
	push @{ $self->{'METADATA'}->{'prospective_addresses'}{$addr} }, time().'; '. $reason. '; '. $additional;
	$self->commit();

	return 1;
};

=item $storage->B<commit_prospective_address>( )

Commit prospective remailers to the list of remailers we know.

Returns 1.

=cut
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
			Echolot::Log::notice("$addr is used because of direct conf or key reply");
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
				Echolot::Log::notice("$addr is recommended by ". join(', ', @adds) . ".");
				$self->add_address($addr);
				delete $self->{'METADATA'}->{'prospective_addresses'}->{$addr};
				next;
			};
		};
	};

	$self->enable_commit(1);

	return 1;
};

=item $storage->B<get_address>( I<$addr> )

Get a reference to a hash of information of the remailers with address
I<$addr>.

The hash has the following keys:

=over

=item status

=item id

=item address

=item fetch

=item showit

=item pingit

=item ttl

=item resurrection_ttl

=back

Returns undef on errors.

=cut
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
		pingit  => $self->{'METADATA'}->{'addresses'}->{$addr}->{'pingit'},
		ttl     => $self->{'METADATA'}->{'addresses'}->{$addr}->{'ttl'},
		resurrection_ttl => $self->{'METADATA'}->{'addresses'}->{$addr}->{'resurrection_ttl'},
	};

	return $result;
};

=item $storage->B<get_addresses>( )

Get an array of all remailers we know about.  Each element in this array is a
hash reference as returned by C<get_address>.

=cut
sub get_addresses($) {
	my ($self) = @_;

	my @addresses = keys %{$self->{'METADATA'}->{'addresses'}};
	my @return_data = map { $self->get_address($_); } @addresses;
	return @return_data;
};

=item $storage->B<add_address>( I<$addr> )

Adds a remailer with address I<$addr>. B<fetch>, B<pingit>, and B<shoit> are
set to the values configured for new remailers.

Assign the remailer status B<active> and a new unique ID.

See L<pingd.conf(5)> for more information on this.

Returns 1.

=cut
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



	Echolot::Log::notice("Adding address $addr.");
	
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

=item $storage->B<set_stuff>( I<@args> )

@args is supposed to have two elements: I<$address>, and I<$setting>.

Set verious options for the remailer with address $I<$address>.

I<$setting> has to be of the form C<key=value>.  Recognised keys are B<pingit>,
B<fetch>, and B<showit>.  Acceptable values are B<on> and B<off>.

See L<pingd(1)> for the meaning of these settings.

Returns 1, undef on error.

=cut
sub set_stuff($@) {
	my ($self, @args) = @_;

	my ($addr, $setting) = @args;
	my $args = join(', ', @args);

	defined ($addr) or
		Echolot::Log::cluck ("Could not get address for '$args'."),
		return undef;
	defined ($setting) or
		Echolot::Log::cluck ("Could not get setting for '$args'."),
		return undef;
	
	defined ($self->{'METADATA'}->{'addresses'}->{$addr}) or
		Echolot::Log::warn ("Address $addr does not exist."),
		return undef;
	

	if ($setting =~ /^(pingit|fetch|showit)=(on|off)$/) {
		my $option = $1;
		my $value = $2;
		Echolot::Log::info("Setting $option to $value for $addr");
		$self->{'METADATA'}->{'addresses'}->{$addr}->{$option} = ($value eq 'on');
	} else {
		Echolot::Log::warn ("Don't know what to do with '$setting' for $addr."),
		return undef;
	}

	$self->commit();
	return 1;
};


=item $storage->B<get_address_by_id>( I<$id> )

Return the address for the remailer with id I<$id>.

Return undef if there is no remailer with that id.

=cut
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

=item $storage->B<decrease_resurrection_ttl>( I<$address> )

Decrease the TTL (Time To Live) for remailer with address I<$address> by one.

If it hits zero the remailer's status is set to B<ttl timeout>.

Returns 1, undef on error.

=cut
sub decrease_ttl($$) {
	my ($self, $address) = @_;
	
	defined ($self->{'METADATA'}->{'addresses'}->{$address}) or
		Echolot::Log::cluck ("$address does not exist in Metadata address list."),
		return undef;
	$self->{'METADATA'}->{'addresses'}->{$address}->{'ttl'} --;
	$self->{'METADATA'}->{'addresses'}->{$address}->{'status'} = 'ttl timeout',
		Echolot::Log::info("Remailer $address disabled: ttl expired."),
		$self->{'METADATA'}->{'addresses'}->{$address}->{'resurrection_ttl'} = Echolot::Config::get()->{'check_resurrection_ttl'}
		if ($self->{'METADATA'}->{'addresses'}->{$address}->{'ttl'} <= 0);
	$self->commit();
	return 1;
};

=item $storage->B<decrease_resurrection_ttl>( I<$address> )

Decrease the resurrection TTL (Time To Live) for remailer with address
I<$address> by one.

If it hits zero the remailer's status is set to B<dead>.

Returns 1, undef on error.

=cut
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
	$self->commit();
	return 1;
};

=item $storage->B<restore_ttl>( I<$address> )

Restore the TTL (Time To Live) for remailer with address I<$address> to the
value configured with I<addresses_default_ttl>

See L<pingd.conf(5)> for more information on this settings.

Returns 1, undef on error.

=cut
sub restore_ttl($$) {
	my ($self, $address) = @_;
	
	defined ($self->{'METADATA'}->{'addresses'}->{$address}) or
		Echolot::Log::cluck ("$address does not exist in Metadata address list."),
		return undef;
	defined ($self->{'METADATA'}->{'addresses'}->{$address}->{'status'}) or
		Echolot::Log::cluck ("$address does exist in Metadata address list but does not have status defined."),
		return undef;
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


=item $storage->B<not_a_remaielr>( I<$id> )

Set the remailer whoise id is I<$id> to B<disabled by user reply: is not a
remailer>.

Returns 1, undef on error.

=cut
sub not_a_remailer($$) {
	my ($self, $id) = @_;
	
	my $remailer = $self->get_address_by_id($id);
	defined $remailer or
		Echolot::Log::cluck("No remailer found for id '$id'."),
		return undef;
	my $address = $remailer->{'address'};
	defined ($self->{'METADATA'}->{'addresses'}->{$address}) or
		Echolot::Log::cluck ("$address does not exist in Metadata address list."),
		return undef;
	$self->{'METADATA'}->{'addresses'}->{$address}->{'status'}  = 'disabled by user reply: is not a remailer';

	Echolot::Log::info("Setting $id, $address to disabled by user reply.");

	$self->commit();
	return 1;
};

=item $storage->B<set_caps>( I<$type>, I<$caps>, I<$nick>, I<$address>, I<$timestamp> [, I<$dont_expire> ])

Sets the capabilities for remailer with address I<$address> to the given
information (I<$nick>, I<$type>, I<$caps>, I<$timestamp>).

Type here means the software used (Mixmaster, Reliable) as given by the
remailer-conf reply or something like B<set manually>.

If there already is newer information about that key than I<$timestamp> the
update is disregarded.

If I<$dont_expire> is defined the setting is copied to the remailers metadata
as well.

Returns 1.

=cut
sub set_caps($$$$$$;$) {
	my ($self, $type, $caps, $nick, $address, $timestamp, $dont_expire) = @_;

	(defined $address) or
		Echolot::Log::cluck ("$address not defined in set_key.");

	if (! defined $self->{'metadata'}->{'remailers'}->{$address} ) {
		$self->{'metadata'}->{'remailers'}->{$address} = {};
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

=item $storage->B<set_key>( I<$type>, I<$nick>, I<$address>, I<$key>, I<$keyid>, I<$version>, I<$caps>, I<$summary>, I<$timestamp>)

Sets the I<$type> key I<$keyid> for remailer with address I<$address> to the
given information (I<$nick>, I<$key>, I<$caps>, I<$summary>, I<$timestamp>).

If there already is newer information about that key than I<$timestamp> the
update is disregarded.

Returns 1.

=cut
sub set_key($$$$$$$$$) {
	my ($self, $type, $nick, $address, $key, $keyid, $version, $caps, $summary, $timestamp) = @_;

	(defined $address) or
		Echolot::Log::cluck ("$address not defined in set_key.");

	if (! defined $self->{'metadata'}->{'remailers'}->{$address} ) {
		$self->{'metadata'}->{'remailers'}->{$address} = {};
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

=item $storage->B<get_secret>( )

Return our secret (Used in Message Authentication Codes).

=cut
sub get_secret($) {
	my ($self) = @_;

	return $self->{'METADATA'}->{'secret'};
};

=item $storage->B<get_types>( I<$remailer> )

Get an array of types supported by remailer with address I<$remailer>.

Returns undef on errors.

¿ It may be possible that a type is returned but then has no keys.  This may be
a bug, I'm not sure.

=cut
sub get_types($$) {
	my ($self, $remailer) = @_;

	defined ($self->{'METADATA'}->{'addresses'}->{$remailer}) or
		Echolot::Log::cluck ("$remailer does not exist in Metadata remailer list."),
		return undef;

	return () unless defined $self->{'METADATA'}->{'remailers'}->{$remailer};
	return () unless defined $self->{'METADATA'}->{'remailers'}->{$remailer}->{'keys'};
	my @types = keys %{$self->{'METADATA'}->{'remailers'}->{$remailer}->{'keys'}};
	return @types;
};


=item $storage->B<has_type>( I<$remailer>, I<$type> )

Checks if the remailer with address I<$remailer> has type I<$type> keys.

Returns 1 if it has, 0 if not, undef on errors.

=cut
sub has_type($$$) {
	my ($self, $remailer, $type) = @_;

	defined ($self->{'METADATA'}->{'addresses'}->{$remailer}) or
		Echolot::Log::cluck ("$remailer does not exist in Metadata remailer list."),
		return undef;

	return 0 unless defined $self->{'METADATA'}->{'remailers'}->{$remailer};
	return 0 unless defined $self->{'METADATA'}->{'remailers'}->{$remailer}->{'keys'};
	return 0 unless defined $self->{'METADATA'}->{'remailers'}->{$remailer}->{'keys'}->{$type};
	return 0 unless scalar keys %{$self->{'METADATA'}->{'remailers'}->{$remailer}->{'keys'}->{$type}};
	return 1;
};


=item $storage->B<get_keys>( I<$remailer>, I<$type> )

Returns an array listing all keyids of type I<$type> of remailer with address
I<$remailer>.

Returns undef on errors.

=cut
sub get_keys($$$) {
	my ($self, $remailer, $type) = @_;

	defined ($self->{'METADATA'}->{'addresses'}->{$remailer}) or
		Echolot::Log::cluck ("$remailer does not exist in Metadata address list."),
		return undef;

	defined ($self->{'METADATA'}->{'remailers'}->{$remailer}) or
		Echolot::Log::cluck ("$remailer does not exist in Metadata remailer list."),
		return undef;

	defined ($self->{'METADATA'}->{'remailers'}->{$remailer}->{'keys'}) or
		Echolot::Log::cluck ("$remailer does not have keys in Metadata remailer list."),
		return undef;

	defined ($self->{'METADATA'}->{'remailers'}->{$remailer}->{'keys'}->{$type}) or
		Echolot::Log::cluck ("$remailer does not have type '$type' in Metadata remailer list."),
		return undef;

	my @keys = keys %{$self->{'METADATA'}->{'remailers'}->{$remailer}->{'keys'}->{$type}};
	return @keys;
};



=item $storage->B<get_key>( I<$remailer>, I<$type>, I<$key> )

Returns a hash having they keys C<summary>, C<key>, C<nick>, and
C<last_updated> of the I<$type> key with id I<$key> of remailer with address
I<$remailer>.

Returns undef on errors.

=cut
sub get_key($$$$) {
	my ($self, $remailer, $type, $key) = @_;

	defined ($self->{'METADATA'}->{'addresses'}->{$remailer}) or
		Echolot::Log::cluck ("$remailer does not exist in Metadata address list."),
		return undef;

	defined ($self->{'METADATA'}->{'remailers'}->{$remailer}) or
		Echolot::Log::cluck ("$remailer does not exist in Metadata remailer list."),
		return undef;

	defined ($self->{'METADATA'}->{'remailers'}->{$remailer}->{'keys'}) or
		Echolot::Log::cluck ("$remailer does not have keys in Metadata remailer list."),
		return undef;

	defined ($self->{'METADATA'}->{'remailers'}->{$remailer}->{'keys'}->{$type}) or
		Echolot::Log::cluck ("$remailer does not have type '$type' in Metadata remailer list."),
		return undef;

	defined ($self->{'METADATA'}->{'remailers'}->{$remailer}->{'keys'}->{$type}->{$key}) or
		Echolot::Log::cluck ("$remailer does not have key '$key' in type '$type' in Metadata remailer list."),
		return undef;

	my %result = (
		summary => $self->{'METADATA'}->{'remailers'}->{$remailer}->{'keys'}->{$type}->{$key}->{'summary'},
		key => $self->{'METADATA'}->{'remailers'}->{$remailer}->{'keys'}->{$type}->{$key}->{'key'},
		nick => $self->{'METADATA'}->{'remailers'}->{$remailer}->{'keys'}->{$type}->{$key}->{'nick'},
		last_update => $self->{'METADATA'}->{'remailers'}->{$remailer}->{'keys'}->{$type}->{$key}->{'last_update'}
	);

	return %result;
};


=item $storage->B<get_capabilities>( I<$remailer> )

Return the capabilities on file for remailer with address I<$remailer>.  This
is probably the one we got from remailer-conf or set manually.

Returns undef on errors.

=cut
sub get_capabilities($$) {
	my ($self, $remailer) = @_;
	
	return undef unless defined $self->{'METADATA'}->{'remailers'}->{$remailer};
	return undef unless defined $self->{'METADATA'}->{'remailers'}->{$remailer}->{'conf'};
	return $self->{'METADATA'}->{'remailers'}->{$remailer}->{'conf'}->{'capabilities'};
};


=item $storage->B<get_capabilities>( I<$remailer> )

Return the capabilities on file for remailer with address I<$remailer>.  This
is probably the one we got from remailer-conf or set manually.

Returns undef on errors.

=cut
sub get_nick($$) {
	my ($self, $remailer) = @_;
	
	defined $remailer or
		Echolot::Log::cluck ("Undefined remailer passed to get_nick()."),
		return undef;
	return undef unless defined $self->{'METADATA'}->{'remailers'}->{$remailer};
	return undef unless defined $self->{'METADATA'}->{'remailers'}->{$remailer}->{'conf'};
	return $self->{'METADATA'}->{'remailers'}->{$remailer}->{'conf'}->{'nick'};
};


=item $storage->B<expire>( )

Expires old keys, confs and pings from the Storage as configured by
I<expire_keys>, I<expire_confs>, and I<expire_pings>.

See L<pingd.conf(5)> for more information on these settings.

Returns 1 on success, undef on errors.

=cut
sub expire($) {
	my ($self) = @_;

	my $now = time();
	my $expire_keys  = $now - Echolot::Config::get()->{'expire_keys'};
	my $expire_conf = $now - Echolot::Config::get()->{'expire_confs'};
	my $expire_pings = $now - Echolot::Config::get()->{'expire_pings'};
	my $expire_chainpings = $now - Echolot::Config::get()->{'expire_chainpings'};
	my $expire_fromlines = $now - Echolot::Config::get()->{'expire_fromlines'};

	# Remailer Information and pings
	for my $remailer_addr ( keys %{$self->{'METADATA'}->{'remailers'}} ) {
		if (exists $self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'keys'}) {
			for my $type ( keys %{$self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'keys'}} ) {
				if (exists $self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'keys'}->{$type}) {
					for my $key ( keys %{$self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'keys'}->{$type}} ) {
						if ($self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'keys'}->{$type}->{$key}->{'last_update'} < $expire_keys) {
							Echolot::Log::info("Expiring $remailer_addr, key, $type, $key.");
							$self->pingdata_close_one($remailer_addr, $type, $key, 'delete');
							delete $self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'keys'}->{$type}->{$key};
						};
					};
					delete $self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'keys'}->{$type}
						unless (scalar keys %{$self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'keys'}->{$type}});
				};
			};
			delete $self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'keys'}
				unless (scalar keys %{$self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'keys'}});
		}

		if (exists $self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'conf'}) {
			delete $self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'conf'}
				if (defined $self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'conf'} &&
				   ($self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'conf'}->{'last_update'} < $expire_conf) &&
				   ! ($self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'conf'}->{'dont_expire'}));
		}

		delete $self->{'METADATA'}->{'remailers'}->{$remailer_addr},
			next
			unless ( defined ($self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'conf'}) ||
			         defined ($self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'keys'}));


		next unless exists $self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'keys'};
		for my $type ( keys %{$self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'keys'}} ) {
			next unless exists $self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'keys'}->{$type};
			for my $key ( keys %{$self->{'METADATA'}->{'remailers'}->{$remailer_addr}->{'keys'}->{$type}} ) {
				my @out  = grep {$_      > $expire_pings} $self->get_pings($remailer_addr, $type, $key, 'out');
				my @done = grep {$_->[0] > $expire_pings} $self->get_pings($remailer_addr, $type, $key, 'done');


				# write ping to done
				my $fh = $self->get_ping_fh($remailer_addr, $type, $key, 'done') or
					Echolot::Log::cluck ("$remailer_addr; type=$type; key=$key has no assigned filehandle for done pings."),
					return undef;
				seek($fh, 0, SEEK_SET) or
					Echolot::Log::warn("Cannot seek to start of $remailer_addr out pings: $!."),
					return undef;
				truncate($fh, 0) or
					Echolot::Log::warn("Cannot truncate done pings file for remailer $remailer_addr; key=$key file to zero length: $!."),
					return undef;
				for my $done (@done) {
					print($fh $done->[0]." ".$done->[1]."\n") or
						Echolot::Log::warn("Error when writing to $remailer_addr out pings: $!."),
						return undef;
				};
				$fh->flush();

				# rewrite outstanding pings
				$fh = $self->get_ping_fh($remailer_addr, $type, $key, 'out') or
					Echolot::Log::cluck ("$remailer_addr; type=$type; key=$key has no assigned filehandle for out pings."),
					return undef;
				seek($fh, 0, SEEK_SET) or
					Echolot::Log::warn("Cannot seek to start of outgoing pings file for remailer $remailer_addr; key=$key: $!."),
					return undef;
				truncate($fh, 0) or
					Echolot::Log::warn("Cannot truncate outgoing pings file for remailer $remailer_addr; key=$key file to zero length: $!."),
					return undef;
				print($fh (join "\n", @out), (scalar @out ? "\n" : '') ) or
					Echolot::Log::warn("Error when writing to outgoing pings file for remailer $remailer_addr; key=$key file: $!."),
					return undef;
				$fh->flush();
			};
		};
	};

	# Chainpings
	for my $type ( keys %{$self->{'CHAINPING_FHS'}} ) {
		my $pings = $self->get_chainpings($type);

		@{ $pings->{'out'} } = map {
				my $a = $_;
				join (' ', map ({ $a->{$_} } qw{sent addr1 type1 key1 addr2 type2 key2}))
			} grep {
				$_->{'sent'} > $expire_chainpings
			}
			@{ $pings->{'out'} };
		@{ $pings->{'done'} } = map {
				my $a = $_;
				join (' ', map ({ $a->{$_} } qw{sent addr1 type1 key1 addr2 type2 key2 lat}))
			} grep {
				$_->{'sent'} > $expire_chainpings
			}
			@{ $pings->{'done'} };

		for my $dir (qw{out done}) {
			my $fh = $self->get_chainping_fh($type, $dir) or
				Echolot::Log::warn ("have no assigned filehandle for $type $dir chainpings."),
				return undef;
			seek($fh, 0, SEEK_SET) or
				Echolot::Log::warn("Cannot seek to start of $dir chainpings $type $!."),
				return undef;
			truncate($fh, 0) or
				Echolot::Log::warn("Cannot truncate $dir chainpings $type file to zero length: $!."),
				return undef;
			print($fh (join "\n", @{$pings->{$dir}}), (scalar @{$pings->{$dir}} ? "\n" : '') ) or
				Echolot::Log::warn("Error when writing to $dir chainpings $type file: $!."),
				return undef;
			$fh->flush();
		};
	};

	# From Header lines
	for my $remailer_addr ( keys %{$self->{'METADATA'}->{'fromlines'}} ) {
		for my $type ( keys %{$self->{'METADATA'}->{'fromlines'}->{$remailer_addr}} ) {
			for my $user_supplied ( keys %{$self->{'METADATA'}->{'fromlines'}->{$remailer_addr}->{$type}} ) {
				delete $self->{'METADATA'}->{'fromlines'}->{$remailer_addr}->{$type}->{$user_supplied}
					if ($self->{'METADATA'}->{'fromlines'}->{$remailer_addr}->{$type}->{$user_supplied}->{'last_update'} < $expire_fromlines);
			};
			delete $self->{'METADATA'}->{'fromlines'}->{$remailer_addr}->{$type}
				unless (scalar keys %{$self->{'METADATA'}->{'fromlines'}->{$remailer_addr}->{$type}});
		};
		delete $self->{'METADATA'}->{'fromlines'}->{$remailer_addr}
			unless (scalar keys %{$self->{'METADATA'}->{'fromlines'}->{$remailer_addr}});
	};

	$self->commit();
	
	return 1;
};

=item $storage->B<delete_remailer>( I<$address> )

Delete all data on the remailer with I<$address>.  This includes stored conf
and key information, pings and the remailer's settings like I<pingit> et al.

If this remailer is still referenced by other remailers' remailer-conf reply it
is likely to get picked up again.

Returns 1.

=cut
sub delete_remailer($$) {
	my ($self, $address) = @_;

	Echolot::Log::notice("Deleting remailer $address.");

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

	delete $self->{'METADATA'}->{'fromlines'}->{$address}
		if (defined $self->{'METADATA'}->{'fromlines'}->{$address});

	$self->commit();
	
	return 1;
};

=item $storage->B<delete_remailercaps>( I<$address> )

Delete conf data of the remailer with I<$address>.

Returns 1.

=cut
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


=item $storage->B<register_fromline>( I<$address>, I<$with_from>, I<$from>, $I<disclaimer_top>, $I<disclaimer_bot> )

Register that the remailer I<$address> returned the From header
line I<$from>.  If I<$with_from> is 1 we had tried to supply our own
From, otherwise not.

$I<disclaimer_top> and $I<disclaimer_bot> are boolean variables indicating
presence or absense of any disclaimer.

Returns 1, undef on error.

=cut

sub register_fromline($$$$$$$) {
	my ($self, $address, $type, $with_from, $from, $top, $bot) = @_;

	defined ($self->{'METADATA'}->{'addresses'}->{$address}) or
		Echolot::Log::cluck ("$address does not exist in Metadata address list."),
		return undef;
	defined ($from) or
		Echolot::Log::cluck ("from is not defined in register_fromline."),
		return undef;
	defined ($with_from) or
		Echolot::Log::cluck ("from is not defined in register_fromline."),
		return undef;
	($with_from == 0 || $with_from == 1) or
		Echolot::Log::cluck ("with_from has evil value $with_from in register_fromline."),
		return undef;

	Echolot::Log::debug("registering fromline $address, $type, $with_from, $from, $top, $bot.");

	$self->{'METADATA'}->{'fromlines'}->{$address}->{$type}->{$with_from} = {
		last_update => time(),
		from => $from,
		disclaim_top => $top,
		disclaim_bot => $bot,
	};
	$self->commit();

	return 1;
};


=item $storage->B<get_fromline>( I<$addr>, I<$type>, I<$user_supplied> )

Return a hash reference with header From line information.

The hash has two keys, B<last_update> and B<from>, which holds the actual information.

If there is no from line registered for the given combination, undef is returned.

On Error, also undef is returned.

=cut

sub get_fromline($$$$) {
	my ($self, $addr, $type, $user_supplied) = @_;

	defined $self->{'METADATA'}->{'fromlines'}->{$addr} or
		return undef;
	defined $self->{'METADATA'}->{'fromlines'}->{$addr}->{$type} or
		return undef;
	defined $self->{'METADATA'}->{'fromlines'}->{$addr}->{$type}->{$user_supplied} or
		return undef;

	defined $self->{'METADATA'}->{'fromlines'}->{$addr}->{$type}->{$user_supplied}->{'last_update'} or
		Echolot::Log::cluck ("last_update is undefined with $addr $type $user_supplied."),
		return undef;
	defined $self->{'METADATA'}->{'fromlines'}->{$addr}->{$type}->{$user_supplied}->{'from'} or
		Echolot::Log::cluck ("from is undefined with $addr $type $user_supplied."),
		return undef;

	return { last_update  => $self->{'METADATA'}->{'fromlines'}->{$addr}->{$type}->{$user_supplied}->{'last_update'},
	         from         => $self->{'METADATA'}->{'fromlines'}->{$addr}->{$type}->{$user_supplied}->{'from'},
		 disclaim_top => $self->{'METADATA'}->{'fromlines'}->{$addr}->{$type}->{$user_supplied}->{'disclaim_top'},
		 disclaim_bot => $self->{'METADATA'}->{'fromlines'}->{$addr}->{$type}->{$user_supplied}->{'disclaim_bot'} };
}


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
