package Echolot::Scheduler;

# (c) 2002 Peter Palfrader <peter@palfrader.org>
# $Id: Scheduler.pm,v 1.2 2002/06/11 10:16:38 weasel Exp $
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
use warnings;
use Carp qw{cluck};

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

=item B<add> (I<name>, I<interval>, I<offset>, I<what>)

Adds a task with I<name> to the list of tasks. Every I<interval> seconds
I<what> is called. If for example I<interval> is 3600 - meaning I<what>
should be executed hourly - setting I<offset> to 600 would mean that
it get's called 10 minutes after the hour.

=cut
sub add($$$$$) {
	my ($self, $name, $interval, $offset, $what) = @_;

	if (defined $self->{'tasks'}->{$name}) {
		@{ $self->{'schedule'} } = grep { $_->{'name'} ne $name } @{ $self->{'schedule'} };
	};

	$self->{'tasks'}->{$name} =
		{
			interval  => $interval,
			offset    => $offset,
			what      => $what,
			order     => $ORDER++
		};

	$self->schedule($name);
	
	return 1;
};

=item B<schedule> (I<name>, I<for>)

Internal function.

Schedule execution of I<name> for I<for>. If I<for> is not given it is calculated
from I<interval> and I<offset> passed to B<new>.

=cut
sub schedule($$;$) {
	my ($self, $name, $for) = @_;
	
	(defined $self->{'tasks'}->{$name}) or
		cluck("Task $name is not defined"),
		return 0;

	my $interval = $self->{'tasks'}->{$name}->{'interval'};
	my $offset = $self->{'tasks'}->{$name}->{'offset'};


	unless (defined $for) {
		my $now = time();
		$for = $now - $now % $interval + $offset;
		($for <= $now) and $for += $interval;
	};

	push @{ $self->{'schedule'} },
		{
			start => $for,
			order => $self->{'tasks'}->{$name}->{'order'},
			name => $name
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

	my $task = shift @{ $self->{'schedule'} };
	(defined $task) or
		croak("Scheduler is empty"),
		return 0;

	while(1) {
		my $now = time();
		if ($task->{'start'} < $now) {
			warn("Task $task->{'name'} could not be started on time\n");
		} else {
			sleep ($task->{'start'} - $now);
		};

		$now = $task->{'start'};
		do {
			my $name = $task->{'name'};
			(defined $self->{'tasks'}->{$name}) or
				warn("Task $task->{'name'} is not defined\n");

			my $what = $self->{'tasks'}->{$name}->{'what'};
			last if ($what eq 'exit');
			&$what();
			$self->schedule($name, $now + $self->{'tasks'}->{$name}->{'interval'});

			$task = shift @{ $self->{'schedule'} };
			(defined $task) or
				croak("Scheduler is empty"),
				return 0;
		} while ($now == $task->{'start'});
	};

	return 1;
};

# vim: set ts=4 shiftwidth=4:
