package Echolot::Config;

# (c) 2002 Peter Palfrader <peter@palfrader.org>
# $Id: Config.pm,v 1.1 2002/06/05 04:05:40 weasel Exp $
#

=pod

=head1 Name

Echolot::Config - echolot configuration

=head1 DESCRIPTION

=cut

use strict;
use warnings;
use XML::Parser;
use XML::Dumper;
use Carp;

my $CONFIG;

sub init() {
	my $DEFAULT;
	$DEFAULT->{'recipient_delimiter'} = '+';
	$DEFAULT->{'dev_random'}          = '/dev/random';
	$DEFAULT->{'hash_len'}            = 8;

	{
		my $parser = new XML::Parser(Style => 'Tree');
		my $tree = $parser->parsefile('pingd.conf');
		my $dump = new XML::Dumper;
		$CONFIG = $dump->xml2pl($tree);
	}
	
	for my $key (keys %$DEFAULT) {
		$CONFIG->{$key} = $DEFAULT->{$key} unless defined $CONFIG->{$key};
	};
};

sub get() {
	return $CONFIG;
};

1;
# vim: set ts=4 shiftwidth=4:
