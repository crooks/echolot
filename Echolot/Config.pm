package Echolot::Config;

# (c) 2002 Peter Palfrader <peter@palfrader.org>
# $Id: Config.pm,v 1.3 2002/07/02 14:16:13 weasel Exp $
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

sub init($) {
	my ($params) = @_;

	my $DEFAULT;
	$DEFAULT->{'recipient_delimiter'} = '+';
	$DEFAULT->{'dev_random'}          = '/dev/random';
	$DEFAULT->{'hash_len'}            = 8;

	$DEFAULT = {
		addresses_default_ttl       => 5, # days
		smarthost                   => 'localhost',
		mailindir                   => 'mail/IN',
		mailerrordir                => 'mail/ERROR',
		ping_new                    => 1,
		show_new                    => 1,
		pinger_interval             => 300,
		ping_every_nth_time         => 48,
		resultdir                   => 'results',
		gnupghome                   => 'gnupg',
		tmpdir                      => 'tmp',
		prospective_addresses_ttl   => 432000, # 5 days
		reliable_auto_add_min       => 3, # 3 remailes need to list new address
		commands_file               => 'commands.txt',
		pidfile                     => 'pingd.pid',
		expire_keys                 => 432000, # 5 days
		expire_confs                => 432000, # 5 days
		expire_pings                => 1123200, # 12 days
		storage                     => {
			backend                 	=> 'File',
			File                    	=> {
				basedir             		=> 'data'
			}
		},

		homedir                     => undef,
		my_localpart                => undef,
		my_domain                   => undef,
		verbose                     => 0
	};

	{
		my $parser = new XML::Parser(Style => 'Tree');
		my $tree = $parser->parsefile('pingd.conf');
		my $dump = new XML::Dumper;
		$CONFIG = $dump->xml2pl($tree);
	}
	
	for my $key (keys %$DEFAULT) {
		$CONFIG->{$key} = $DEFAULT->{$key} unless defined $CONFIG->{$key};
	};

	for my $key (keys %$params) {
		$CONFIG->{$key} = $params->{$key} if defined $CONFIG->{$key};
	};

	for my $key (keys %$CONFIG) {
		warn ("Config option $key is not defined\n") unless defined $CONFIG->{$key};
	};
};

sub get() {
	return $CONFIG;
};

1;
# vim: set ts=4 shiftwidth=4:
