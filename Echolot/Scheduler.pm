package Echolot::Scheduler;

# (c) 2002 Peter Palfrader <peter@palfrader.org>
# $Id: Scheduler.pm,v 1.10 2002/07/17 17:53:44 weasel Exp $
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
use Carp qw{cluck confess};

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

	confess("Must not add zero intervall for job $name")
		unless $interval;

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

Schedule execution of I<name> for I<for>. If I<for> is not given it is calculated
from I<interval> and I<offset> passed to B<new>.

=cut
sub schedule($$;$$) {
	my ($self, $name, $for, $arguments) = @_;
	
	(defined $self->{'tasks'}->{$name}) or
		cluck("Task $name is not defined"),
		return 0;

	my $interval = $self->{'tasks'}->{$name}->{'interval'};
	my $offset = $self->{'tasks'}->{$name}->{'offset'};


	unless (defined $for) {
		($interval < 0) and
			return 1;
		my $now = time();
		$for = $now - $now % $interval + $offset;
		($for <= $now) and $for += $interval;
	};

	$arguments = [] unless defined $arguments;

	push @{ $self->{'schedule'} },
		{
			start => $for,
			order => $self->{'tasks'}->{$name}->{'order'},
			name => $name,
			arguments => $arguments
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
		cluck("Scheduler is empty"),
		return 0;

	while(1) {
		my $now = time();
		my $task = $self->{'schedule'}->[0];
		if ($task->{'start'} < $now) {
			warn("Task $task->{'name'} could not be started on time\n");
		} else {
			print "zZzZZzz at $now\n" if Echolot::Config::get()->{'verbose'};
			sleep ($task->{'start'} - $now);
		};

		(time() < $task->{'start'}) and
			next;

		$now = $task->{'start'};
		do {
			$task = shift @{ $self->{'schedule'} };
			my $name = $task->{'name'};
			(defined $self->{'tasks'}->{$name}) or
				warn("Task $task->{'name'} is not defined\n");

			my $what = $self->{'tasks'}->{$name}->{'what'};
			print "Running $name at ".(time())." (scheduled for $now)\n" if Echolot::Config::get()->{'verbose'};
			last if ($what eq 'exit');
			&$what( @{ $task->{'arguments'} } );
			$self->schedule($name, $now + $self->{'tasks'}->{$name}->{'interval'}) if
				($self->{'tasks'}->{$name}->{'interval'} > 0);

			(defined $self->{'schedule'}->[0]) or
				cluck("Scheduler is empty"),
				return 0;
		} while ($now >= $self->{'schedule'}->[0]->{'start'});
	};

	return 1;
};

# vim: set ts=4 shiftwidth=4:
