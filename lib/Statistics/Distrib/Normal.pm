#
# Author:      Peter J. Acklam
# Time-stamp:  2000-06-02 23:42:57
# E-mail:      pjacklam@online.no
# URL:         http://home.online.no/~pjacklam

=head1 NAME

Statistics::Distrib::Normal - the normal distribution

=head1 SYNOPSIS

    use Statistics::Distrib::Normal;

    $dist = new Statistics::Distrib::Normal;

    $dist->mu(3);                # set the location parameter
    $dist->sigma(5);             # set the scale parameter
    @x = $dist->rand(10);        # generate random numbers

    # or

    @x = Statistics::Distrib::Normal->new(Mu => 3, Sigma => 5)->rand(10);

=head1 DESCRIPTION

This module contains miscellaneous functions related to the normal
distribution.

=cut

package Statistics::Distrib::Normal;
require 5.000;

use strict;
use vars qw($VERSION);
use Carp;

$VERSION = '0.01';

use constant PI    => 4 * atan2 1, 1;
use constant TWOPI => 2 * PI;

# the smallest positive floating-point number such that 1+EPS > 1
use constant EPS   => 2.220446049250313080847263336181640625e-016;

##
## Constructor
##

=head1 CONSTRUCTOR

=over 4

=item new ( [ OPTIONS ] )

C<OPTIONS> is a list of options given in the form of key-value
pairs, just like a hash table. Valid options are

=over 8

=item B<Mu>

Sets the mu parameter (the mean) of the distribution to the specified
value.

=item B<Sigma>

Sets the sigma parameter (the standard deviation) of the distribution
to the specified value.

=back

=back

=cut

sub new {
    my $self = shift;
    my $class = ref($self) || $self;
    my %arg = @_;

    my %hash = ( mu    => 0,
                 sigma => 1,
               );

    my $me = bless \%hash, $class;

    foreach my $key ( keys %arg ) {
        $me->mu($arg{Mu}),       next if $key eq 'Mu';
        $me->sigma($arg{Sigma}), next if $key eq 'Sigma';
        carp "Unknown option $arg{$key} ignored";
    }

    return $me;
}

##
## Methods
##

=pod

=head1 METHODS

=over 4

=item mean ( [ MEAN ] )

Set the mu parameter (the mean) of the distribution to C<MU>.  If
C<MU> is omitted, the current value of mu is returned.

=cut

sub mu {
    my $me = shift;
    croak 'Too many arguments' if @_ > 1;
    if ( @_ ) {
        $me->{mu} = shift;
        return 1;
    }
    return $me->{mu};
}

=pod

=item sigma ( [ SDEV ] )

Set the sigma parameter (the standard deviation) of the distribution
to C<SIGMA>.  If C<SIGMA> is omitted, the current value of sigma is
returned.

=cut

sub sigma {
    my $me = shift;
    croak 'Too many arguments' if @_ > 1;
    if ( @_ ) {
        my $sigma = shift;
        croak 'Standard deviation most be positive' unless $sigma > 0;
        $me->{sigma} = $sigma;
        return 1;
    }
    return $me->{sigma};
}

=pod

=item pdf ( X1 [, X2 [, X3 ... ] ] )

Evaluate the probability density function at C<X1>, C<X2>, C<X3>, ...

=cut

sub pdf {
    my $me = shift;
    croak 'Not enough arguments' unless @_;
    my $mu    = $me->{mu};
    my $sigma = $me->{sigma};
    my $const = log(TWOPI * $sigma * $sigma);
    my @f;
    foreach my $x ( @_ ) {
        my $z = ( $x - $mu ) / $sigma;
        push @f, exp( -0.5 * ( $const + $z*$z ) );
    }
    return @f;
}

=pod

=item ltp ( X1 [, X2 [, ... ] ] )

Evaluate the lower tail probability function at C<X1>, C<X2>, C<X3>,
...

=cut

sub ltp {
    my $me = shift;
    croak 'Not enough arguments' unless @_;
    my $mu    = $me->{mu};
    my $sigma = $me->{sigma};

    require Math::SpecFun::Erf;
    import Math::SpecFun::Erf qw(erfc);

    my @p;
    foreach my $x ( @_ ) {
        my $z = ( $x - $mu ) / $sigma;
        push @p, erfc( - $_[0] / sqrt(2) )/2;
    }
    return @p;
}

=pod

=item utp ( X1 [, X2 [, ... ] ] )

Evaluate the upper tail probability function at C<X1>, C<X2>, C<X3>,
...

=cut

sub utp {
    my $me = shift;
    croak 'Not enough arguments' unless @_;
    my $mu    = $me->{mu};
    my $sigma = $me->{sigma};

    require Math::SpecFun::Erf;
    import Math::SpecFun::Erf qw(erfc);

    my @p;
    foreach my $x ( @_ ) {
        my $z = ( $x - $mu ) / $sigma;
        push @p, erfc( $_[0] / sqrt(2) )/2;
    }
    return @p;
}

=pod

=item ltq ( P1 [, P2 [, ... ] ] )

Returns the lower tail quantile for the probabilities C<P1>, C<P2>,
C<P3>, ...

=cut

sub ltq {
    croak 'Method not implemented yet';
}

=pod

=item utq ( P1 [, P2 [, P3 ... ] ] )

Returns the upper tail quantile for the probabilities C<P1>, C<P2>,
C<P3>, ...

=cut

sub utq {
    croak 'Method not implemented yet';
}

=pod

=item intprob( XLOW, XHIGH )

Interval probability.  Returns the probability of an outcome in the
interval from XLOW to XHIGH.

=cut

sub intprob {
    my $me = shift;
    croak 'Bad number of arguments' unless @_ == 2;
    my ($xlow, $xhigh) = @_;
    return 0 unless $xlow < $xhigh;
    my $mu    = $me->{mu};
    my $sigma = $me->{sigma};

    if ( $mu < $xlow ) {
        return $me->utp($xlow) - $me->utp($xhigh);
    } else {
        return $me->ltp($xhigh) - $me->ltp($xlow);
    }
}

=pod

=item rand( [ NUM ] )

Generate random variables.  If C<NUM> is omitted, a single variable is
returned.

=cut

sub rand {
    my $me = shift;
    my $num;
    if ( @_ ) {
        $num = shift;
        croak 'Too many arguments' if @_;
        croak 'Argument must be positive integer'
          unless ($num == int $num) && ($num > 0);
    } else {
        $num = 1;
    }

    # Generate the random variables by the Box-Muller method.
    my @z;
    my $mu    = $me->{mu};
    my $sigma = $me->{sigma};
    my $const = -2 * $sigma * $sigma;
    my $i;
    for ( $i = 0 ; $i < $num ; $i += 2 ) {
        my $r = sqrt $const * log rand;
        my $t = TWOPI * rand;
        push @z, $mu + $r * sin $t, $mu + $r * cos $t;
    }
    pop @z if $i > $num;
    return @z;
}

=pod

=item expectation ()

Return the expectation of the distribution.

=cut

sub expectation {
    my $me = shift;
    croak 'Too many arguments' if @_;
    return $me->{mu};
}

=pod

=item variance ()

Return the variance of the distribution.

=cut

sub variance {
    my $me = shift;
    croak 'Too many arguments' if @_;
    return $me->{sigma}**2;
}

=pod

=item skewness ()

Return the skewness of the distribution.

=cut

sub skewness {
    my $me = shift;
    croak 'Too many arguments' if @_;
    return 0;
}

=pod

=item kurtosis ()

Return the kurtosis (normalized) of the distribution.

=cut

sub kurtosis {
    my $me = shift;
    croak 'Too many arguments' if @_;
    return 0;
}

=item dmo

Direct moments for the distribution.

Not implemented yet.

=cut

sub dmo {
    croak 'Method not implemented yet';
}

=pod

=item cmo

Central moments for the distribution.

=cut

sub cmo {
    croak 'Method not implemented yet';
}

=pod

=item mode ()

Returns the mode of the distribution.

=cut

sub mode {
    my $me = shift;
    croak 'Too many input arguments' if @_;
    return $me->{mu};
}

=back

=head1 BUGS

None known.

=head1 LIMITATIONS

Degenerate cases are not allowed for most methods; e.g., a
distribution with zero variance.

=head1 HISTORY

=over 4

=item Version 0.02

Code formatting changes.

=item Version 0.01

First release.

=back

=head1 AUTHOR

Peter J. Acklam E<lt>pjacklam@online.noE<gt>.

=head1 COPYRIGHT/LICENSE

Copyright (c) 1999-2000 Peter J. Acklam.  All rights reserved.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

1;              # Modules must return true.
