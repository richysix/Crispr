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
