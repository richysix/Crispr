## no critic (RequireUseStrict, RequireUseWarnings, RequireTidyCode)
package Crispr::Config;
## use critic

# ABSTRACT: Config - for parsing and loading config files

## Author         : rw4
## Maintainer     : rw4
## Created        : 2013-02-25
## Last commit by : $Author$
## Last modified  : $Date$
## Revision       : $Revision$
## Repository URL : $HeadURL$

use warnings;
use strict;

=method new

  Usage       : my $crispr = Crispr::crRNA->new( $config_file );
  Purpose     : Constructor for creating a config object
  Returns     : Crispr::Config object
  Parameters  : $config_file => Str
  Throws      : If no config file name is supplied
  Comments    : None

=cut

sub new {
	my ($class, $conf_file) = @_;
	my $self;
	if ($conf_file) {
		$self = bless {
			'file' => $conf_file
		}, $class;
		
		$self->load_cfg;
	}
    else{
        die "A config file name must be supplied to method new!\n";
    }
	return $self;
	
}

=method load_cfg

  Usage       : $config->load_cfg;
  Purpose     : Internal method to open and parse file config file contents
  Returns     : Crispr::Config object
  Parameters  : None
  Throws      : 
  Comments    : None

=cut

sub load_cfg {
	my $self = shift;
	my $file = $self->{file};
	die "No cfg file found at $file\n" if !-f $file;
	open my $fh, '<', $file;
	while( my $line = <$fh> ) {
		next if $line =~ /^\s*\#/; # skip comments
        next if $line eq qq{\n}; # skip empty lines
		$line =~ s/[\n\r]//g;
        # check if key-value pair is tab-separated
		if( $line =~ m/^(.+)\t(.+)$/){
            my ($k, $v) = ($1, $2);
            $self->{ $k } = $v;
        }
        else{
            warn "Line: $line, is not in correct format. It should be KEY VALUE separated by tabs\n";
        }
	}
	close( $fh );
	return $self;
}

1;
