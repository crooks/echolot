package Echolot::Config;

# (c) 2002 Peter Palfrader <peter@palfrader.org>
# $Id: Config.pm,v 1.41 2002/09/21 03:24:41 weasel Exp $
#

=pod

=head1 Name

Echolot::Config - echolot configuration

=head1 DESCRIPTION

Sets default configuration options and
reads configuration from the config file.

=head1 FILES

The configuration file is searched in those places in that order:

=over

=item the file pointed to by the B<ECHOLOT_CONF> environment variable

=item <basedir>/pingd.conf

=item $HOME/echolot/pingd.conf

=item $HOME/pingd.conf

=item $HOME/.pingd.conf

=item /etc/echolot/pingd.conf

=item /etc/pingd.conf

=back

=cut

use strict;
use Carp;
use English;

my $CONFIG;

sub init($) {
	my ($params) = @_;
	
	die ("Basedir is not defined\n") unless defined $params->{'basedir'};

	my @CONFIG_FILES = 
		( $ENV{'ECHOLOT_CONF'},
		  $params->{'basedir'}.'/pingd.conf',
		  $ENV{'HOME'}.'/echolot/pingd.conf',
		  $ENV{'HOME'}.'/pingd.conf',
		  $ENV{'HOME'}.'/.pingd.conf',
		  '/etc/echolot/pingd.conf',
		  '/etc/pingd.conf' );
	  
	my $DEFAULT;
	$DEFAULT = {
		# System Specific Options
		recipient_delimiter         => '+',
		dev_random                  => '/dev/random',
		sendmail                    => '/usr/sbin/sendmail',

		# Magic Numbers
		hash_len                    => 8,

		# New Remailers
		fetch_new                   => 1,
		ping_new                    => 1,
		show_new                    => 1,

		# Statistics Generation
		separate_rlists             => 0,
		combined_list               => 0,
		thesaurus                   => 1,
		stats_sort_by_latency       => 0,

		# Timers and Counters
		processmail                 => 60,   # process incomng mail every minute
		buildstats                  => 5*60, # build statistics every 5 minutes
		buildkeys                   => 8*60*60, # build keyring every 8 hours
		buildthesaurus              => 60*60, # hourly
		commitprospectives          => 8*60*60, # commit prospective addresses every 8 hours
		expire                      => 24*60*60, # daily
		getkeyconf_interval         => 5*60, # send out requests every 5 minutes
		getkeyconf_every_nth_time   => 24*60/5, # send out the same request to the same remailer once a day
		check_resurrection          => 7*24*60*60, # weekly

		metadata_backup             => 8*60*60, # make backups of metadata and rotate them every 8 hours
		metadata_backup_count       => 32, # keep 32 rotations of metadata

		pinger_interval             => 5*60, # send out pings every 5 minutes
		ping_every_nth_time         => 48,   # send out pings to the same remailer every 48 calls, i.e. every 4 hours

		addresses_default_ttl       => 5, # getkeyconf seconds (days)
		check_resurrection_ttl      => 8, # check_resurrection seconds (weeks)
		prospective_addresses_ttl   => 5*24*60*60, # 5 days
		reliable_auto_add_min       => 3, # 3 remailes need to list new address
		
		expire_keys                 => 5*24*60*60, # 5 days
		expire_confs                => 5*24*60*60, # 5 days
		expire_pings                => 12*24*60*60, # 12 days
		expire_thesaurus            => 21*24*60*60, # 21 days

		# Directories and files
		mailin                      => 'mail',
		mailerrordir                => 'mail-errors',
		resultdir                   => 'results',
		thesaurusdir                => 'results/thesaurus',
		thesaurusindexfile          => 'results/thesaurus/index.html',
		private_resultdir           => 'results.private',
		indexfilebasename           => 'echolot.html',
		gnupghome                   => 'gnupghome',
		gnupg                       => '',
		mixhome                     => 'mixhome',
		mixmaster                   => 'mix',
		tmpdir                      => 'tmp',
		broken1                     => 'broken1.txt',
		broken2                     => 'broken2.txt',
		sameop                      => 'sameop.txt',
		gzip                        => 'gzip',

		commands_file               => 'commands.txt',
		pidfile                     => 'pingd.pid',

		write_meta_files            => 1,
		meta_extension              => '.meta',

		storage                     => {
			backend                 	=> 'File',
			File                    	=> {
				basedir             		=> 'data'
			}
		},

		# ping types
		do_pings => {
			'cpunk-dsa' => 1,
			'cpunk-rsa' => 1,
			'cpunk-clear' => 1,
			'mix' => 1
		},

		# templates
		templates => {
			'indexfile'             => 'templates/echolot.html',
			'thesaurusindexfile'    => 'templates/thesaurusindex.html',
			'mlist'                 => 'templates/mlist.html',
			'mlist2'                => 'templates/mlist2.html',
			'rlist'                 => 'templates/rlist.html',
			'rlist-rsa'             => 'templates/rlist-rsa.html',
			'rlist-dsa'             => 'templates/rlist-dsa.html',
			'rlist-clear'           => 'templates/rlist-clear.html',
			'rlist2'                => 'templates/rlist2.html',
			'rlist2-rsa'            => 'templates/rlist2-rsa.html',
			'rlist2-dsa'            => 'templates/rlist2-dsa.html',
			'rlist2-clear'          => 'templates/rlist2-clear.html',
			'clist'                 => 'templates/clist.html',
		},

		remailerxxxtext => "Hello,\n".
			"\n".
			"This message requests remailer configuration data. The pinging software thinks\n".
			"<TMPL_VAR NAME=\"address\"> is a remailer. Either it has been told so by the\n".
			"maintainer of the pinger or it found the address in a remailer-conf or\n".
			"remailer-key reply of some other remailer.\n".
			"\n".
			"If this is _not_ a remailer, you can tell this pinger that and it will stop\n".
			"sending you those requests immediately (otherwise it will try a few more times).\n".
			"Just reply and make sure the following is the first line of your message:\n".
			"	not a remailer\n".
			"\n".
			"If you want to talk to a human please mail <TMPL_VAR NAME=\"operator_address\">.\n",
		
		homedir                     => undef,
		my_localpart                => undef,
		my_domain                   => undef,
		operator_address            => undef,
		sitename                    => undef,
		verbose                     => 0
	};


	my $configfile = undef;
	for my $filename ( @CONFIG_FILES ) {
		if ( defined $filename && -e $filename ) {
			$configfile = $filename;
			print "Using config file $configfile\n" if ($params->{'verbose'});
			last;
		};
	};

	die ("no Configuration file found\n") unless defined $configfile;
	
	{
		local $/ = undef;
		open(CONFIGCODE, $configfile) or
			confess("Could not open configfile '$configfile': $!");
		my $config_code = <CONFIGCODE>;
		close (CONFIGCODE);
		($config_code) = $config_code =~ /^(.*)$/s;
		eval ($config_code);
		($EVAL_ERROR) and
			confess("Evaling config code from '$configfile' returned error: $EVAL_ERROR");
	}
	

	for my $key (keys %$CONFIG) {
		warn("Unkown option: $key\n") unless (exists $DEFAULT->{$key});
	};
	# Work around spelling bug until 2.0rc3
	if (exists $CONFIG->{'seperate_rlists'}) {
		if (exists  $CONFIG->{'separate_rlists'}) {
			warn ("seperate_rlists has been superseded by separate_rlists.");
		} else {
			warn ("seperate_rlists has been superseded by separate_rlists, please change it in your config file.\n");
			$CONFIG->{'separate_rlists'} = $CONFIG->{'seperate_rlists'};
		};
		delete $CONFIG->{'seperate_rlists'};
	}

	for my $key (keys %$DEFAULT) {
		$CONFIG->{$key} = $DEFAULT->{$key} unless defined $CONFIG->{$key};
	};
	$CONFIG->{'homedir'} = $params->{'basedir'} unless (defined $CONFIG->{'homedir'});
	$CONFIG->{'verbose'} = $params->{'verbose'} if ($params->{'verbose'});

	for my $key (keys %$CONFIG) {
		warn ("Config option $key is not defined\n") unless defined $CONFIG->{$key};
	};

};

sub get() {
	return $CONFIG;
};

sub dump() {
	print Data::Dumper->Dump( [ $CONFIG ], [ 'CONFIG' ] );
};

1;
# vim: set ts=4 shiftwidth=4:
