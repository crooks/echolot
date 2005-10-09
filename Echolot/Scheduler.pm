package Echolot::Scheduler;

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

Echolot::Scheduler - Task selector/scheduler for echolot

=head1 DESCRIPTION

This package provides several functions for scheduling tasks within
the ping daemon.

=over

=cut

use strict;
use English;
use Echolot::Log;

my $ORDER = 1;

=item B<new> ()

Creates a new scheduler object.

=cut
sub new {
	my ($class, %params) = @_;
	my $self = {};
	bless $self, $class;
	return $self;
};

=item B<add> (I<name>, I<interval>, I<offset>, I<missok>, I<what>)

Adds a task with I<name> to the list of tasks. Every I<interval> seconds
I<what> is called. If for example I<interval> is 3600 - meaning I<what>
should be executed hourly - setting I<offset> to 600 would mean that
it get's called 10 minutes after the hour.

I<missok> indicates that it is ok to miss one run of this job.  This can happen
if we run behind schedule for instance.

=cut
sub add($$$$$$) {
	my ($self, $name, $interval, $offset, $missok, $what) = @_;

	Echolot::Log::logdie("Must not add zero intervall for job $name.")
		unless $interval;

	if (defined $self->{'tasks'}->{$name}) {
		@{ $self->{'schedule'} } = grep { $_->{'name'} ne $name } @{ $self->{'schedule'} };
	};

	$self->{'tasks'}->{$name} =
		{
			interval  => $interval,
			offset    => $offset,
			what      => $what,
			order     => $ORDER++,
			missok    => $missok,
		};

	$self->schedule($name, 1);
	
	return 1;
};

=item B<schedule> (I<name>, I<reschedule>, [ I<for>, [I<arguments>]] )

Schedule execution of I<name> for I<for>. If I<for> is not given it is calculated
from I<interval> and I<offset> passed to B<new>. if I<reschedule> is set
the task will be rescheduled when it's done (according to its interval).
You may also give arguments to passed to the task.

=cut
sub schedule($$$;$$) {
	my ($self, $name, $reschedule, $for, $arguments) = @_;
	
	(defined $self->{'tasks'}->{$name}) or
		Echolot::Log::warn("Task $name is not defined."),
		return 0;

	my $interval = $self->{'tasks'}->{$name}->{'interval'};
	my $offset = $self->{'tasks'}->{$name}->{'offset'};


	unless (defined $for) {
		($interval < 0) and
			return 1;
		my $now = time();
		$for = $now - $now % $interval + $offset;
		($for <= $now) and $for += $interval;
		my $cnt = 0;
		while ($self->{'tasks'}->{$name}->{'missok'} && ($for <= $now)) {
			$for += $interval;
			$cnt ++;
		};
		Echolot::Log::debug("Skipping $cnt runs of $name.") if $cnt;
	};

	$arguments = [] unless defined $arguments;

	push @{ $self->{'schedule'} },
		{
			start => $for,
			order => $self->{'tasks'}->{$name}->{'order'},
			name => $name,
			arguments => $arguments,
			reschedule => $reschedule
		};

	@{ $self->{'schedule'} } = sort { $a->{'start'} <=> $b->{'start'} or $a->{'order'} <=> $b->{'order'} }
		@{ $self->{'schedule'} };

	return 1;
};

=item B<run> ()

Start the scheduling run.

It will run forever or until a task with I<what> == 'exit' is executed.

=cut
sub run($) {
	my ($self) = @_;

	(defined $self->{'schedule'}->[0]) or
		Echolot::Log::warn("Scheduler is empty."),
		return 0;

	while(1) {
		my $now = time();
		my $task = $self->{'schedule'}->[0];
		if ($task->{'start'} < $now) {
			Echolot::Log::warn("Task $task->{'name'} could not be started on time.")
				unless ($task->{'start'} == 0);
		} else {
			Echolot::Log::debug("zZzZZzz.");
			$PROGRAM_NAME = "pingd [sleeping]";
			sleep ($task->{'start'} - $now);
		};

		(time() < $task->{'start'}) and
			next;

		$now = $task->{'start'};
		do {
			$task = shift @{ $self->{'schedule'} };
			my $name = $task->{'name'};
			$PROGRAM_NAME = "pingd [executing $name]";
			(defined $self->{'tasks'}->{$name}) or
				Echolot::Log::cluck("Task $task->{'name'} is not defined.");

			my $what = $self->{'tasks'}->{$name}->{'what'};
			Echolot::Log::debug("Running $name (was scheduled for ".(time()-$now)." seconds ago).");
			last if ($what eq 'exit');
			&$what( $now, @{ $task->{'arguments'} } );
			$self->schedule($name, 1, $now + $self->{'tasks'}->{$name}->{'interval'}) if
				($task->{'reschedule'} && $self->{'tasks'}->{$name}->{'interval'} > 0);

			(defined $self->{'schedule'}->[0]) or
				Echolot::Log::warn("Scheduler is empty."),
				return 0;
		} while ($now >= $self->{'schedule'}->[0]->{'start'});
	};

	return 1;
};

# vim: set ts=4 shiftwidth=4:
