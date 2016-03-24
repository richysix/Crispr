#!/usr/bin/env perl

# PODNAME: run_dindel.pl
# ABSTRACT: run dindel for a sample

## Author         : rw4
## Maintainer     : rw4
## Created        : 2016-03-18

use warnings;
use strict;
use Getopt::Long;
use autodie qw(:all);
use Pod::Usage;

use File::Spec;
use File::Find::Rule;
use File::Path qw(make_path);
use English qw( -no_match_vars );

# get options
my %options;
get_and_check_options();

# set up base dindel directory
my $dindel_dir = File::Spec->catfile( $options{output_directory}, 'dindel' );
if( !-e $dindel_dir ){
    make_path( $dindel_dir );
}

my $sample_name = $ARGV[0];
if( !$sample_name ){
    my $err_msg = 'A sample name must be supplied!';
    pod2usage( $err_msg );
}
$sample_name =~ m/\A(\d+)     # run_ids are all digits
                    _       # run_id and lane are separated by an underscore
                    (\d)      # lane is a single digit
                    \#      # lane and index are separated by a #
                    (\d+)     # index
                    \.      # literal dot
                    (\d+)     # var number
                /xms;

my ( $run_id, $lane, $index, $var_num ) = ( $1, $2, $3, $4 );
my $sample = $sample_name;
$sample =~ s|\..*\z||xms; # remove var number
if( $options{verbose} ){
    print "Sample: ", $sample_name, "\n";
    print "Run ID: ", $run_id, "\n";
    print "Lane: ", $lane, "\n";
    print "Index: ", $index, "\n";
    print "Variant Number: ", $var_num, "\n";
}
warn $sample_name, "\n" if( $options{debug} );

my $sample_dir = set_up_dindel_directories( $options{analysis_id}, $sample, $sample_name, );
                        
my ( $selected_var_file, $lib_file ) =
    dindel_extract_indels( $options{bam_file}, $sample_dir, $sample_name, );

if( $selected_var_file ){
    #make windows
    my @window_files = dindel_make_windows( $sample_dir, $selected_var_file, );
    
    #realign windows
    my @glf_files = dindel_realign_windows( $options{bam_file}, $sample_dir,
                                           \@window_files, $lib_file );
    
    my $sample_name_for_vcf = $options{alternate_sample_name} || $sample;
    my $vcf_file = dindel_make_vcf_file( $sample_dir, $sample_name_for_vcf, \@glf_files, );
                                
}
else{
    warn "No candidate variants for $sample_name.\n";
}

sub set_up_dindel_directories {
    my ( $analysis_id, $sample, $sample_name, ) = @_;
    
    my $dindel_dir = File::Spec->catfile(
        $options{output_directory}, 'dindel', $analysis_id, 
        $sample, $sample_name, );
    foreach my $dir ( 'extract_indels', 'windows' ){
        my $work_dir = File::Spec->catfile( $dindel_dir, $dir );
        make_path( $work_dir );
    }
    return $dindel_dir;
}

sub dindel_extract_indels {
    my ( $bam_file, $output_dir, $sample_name, ) = @_;
    
    my $selected_var_file = File::Spec->catfile(
        $output_dir, 'selected_variants.txt' );
    my $final_library_file = File::Spec->catfile(
        $output_dir, 'libraries.txt' );
    if( -e $selected_var_file && -s $selected_var_file &&
        -e $final_library_file && -s $final_library_file ){
        print "Extract Indels already done.\n" if $options{verbose};
        return( $selected_var_file, $final_library_file );
    }
    else{
        my $output_file = File::Spec->catfile(
                    $output_dir, 'extract_indels',
                    join(q{.}, $sample_name, 'dindel_extract_indels', ), );
        my $out_file = File::Spec->catfile(
                    $output_dir, 'extract_indels',
                    'dindel_extract_indels.o', );
        my $error_file = File::Spec->catfile(
                    $output_dir, 'extract_indels',
                    'dindel_extract_indels.e', );
        
        my $cmd = join(q{ },
            $options{dindel_bin},
            '--analysis getCIGARindels',
            "--bamFile $bam_file",
            join(q{ }, '--ref', $options{reference}, ),
            "--outputFile $output_file",
            "> $out_file",
            "2> $error_file",
        );
        
        warn $cmd, "\n" if $options{debug};
        system( $cmd ) == 0
            or die "system $cmd failed: $?";
        
        # sort variants file
        my $var_file = join(q{.}, $output_file, 'variants', 'txt' );
        $cmd = join(q{ }, 'sort', '-k1,1', '-k2,2n', $var_file, '>', $selected_var_file );
        
        warn $cmd, "\n" if $options{debug};
        system( $cmd ) == 0
            or die "system $cmd failed: $?";
        
        # check that selected_variants file has non-zero size;
        if( -z $selected_var_file ){
            return;
        }
        
        # copy libraries file
        my $lib_file = join(q{.}, $output_file, 'libraries', 'txt' );
        $cmd = join(q{ }, 'cp', $lib_file, $final_library_file, );
        
        warn $cmd, "\n" if $options{debug};
        system( $cmd ) == 0
            or die "system $cmd failed: $?";
            
        print "Extract Indels done.\n" if $options{verbose};
        
        return( $selected_var_file, $final_library_file );
    }
}

sub dindel_make_windows {
    my ( $output_dir, $selected_var_file, ) = @_;
    
    # check for windows files
    my @window_files = get_window_files( $output_dir );
    
    if( @window_files ){
        print "Make Windows already done.\n" if $options{verbose};
        return @window_files;
    }
    else{
        my $make_windows_py = File::Spec->catfile(
            $options{dindel_scripts},
            'makeWindows.py',
        );
        my $window_prefix = File::Spec->catfile(
                    $output_dir, 'windows',
                    'window', );
        my $out_file = File::Spec->catfile(
                    $output_dir, 'windows',
                    'dindel_make_windows.o', );
        my $error_file = File::Spec->catfile(
                    $output_dir, 'windows',
                    'dindel_make_windows.e', );
        my $cmd = join(q{ },
            'python',
            $make_windows_py,
            "--inputVarFile  $selected_var_file",
            "--windowFilePrefix $window_prefix",
            "--numWindowsPerFile 1",
            "> $out_file",
            "2> $error_file",
        );
        
        warn $cmd, "\n" if $options{debug};
        system($cmd) == 0
            or die "system $cmd failed: $?";
        
        # get window files
        @window_files = get_window_files( $output_dir );
        print "Make Windows done.\n" if $options{verbose};
        return @window_files;
    }
}

sub get_window_files {
    my ( $output_dir, ) = @_;
    # get window files
    my $window_dir = File::Spec->catfile(
                $output_dir, 'windows', );
    
    opendir(my $windowfh, $window_dir);
    my @window_files = ();
    foreach my $file (readdir($windowfh)) {
        if ($file =~ /window\.\d+\.txt/) {
            push(@window_files, $file);
        }
    }
    return @window_files;
}

sub dindel_realign_windows {
    my ( $bam_file, $output_dir, $window_files, $lib_file ) = @_;
    
    # check for glf files
    my @glf_files;
    my $all_glf_files = 1;
    
    foreach my $window_file ( @{$window_files} ){
        my $window_out_prefix = $window_file;
        $window_out_prefix =~ s/\.txt \z//xms;
        $window_out_prefix = File::Spec->catfile(
                $output_dir, 'windows', $window_out_prefix, );
        my $glf_file = join(q{.}, $window_out_prefix, 'glf', 'txt', );
        if( !-e $glf_file || -z $glf_file ){
            $all_glf_files = 0;
        }
        else{
            push @glf_files, $glf_file;
        }
    }
    
    if( $all_glf_files ){
        print "Realign Windows already done.\n" if $options{verbose};
        return @glf_files;
    }
    else{
        my @glf_files;
        foreach my $window_file ( @{$window_files} ){
            my $window_out_prefix = $window_file;
            $window_out_prefix =~ s/\.txt \z//xms;
            my $window_file = File::Spec->catfile(
                    $output_dir, 'windows', $window_file, );
            $window_out_prefix = File::Spec->catfile(
                    $output_dir, 'windows', $window_out_prefix, );
            my $out_file = File::Spec->catfile(
                    $output_dir, 'realign_windows.o', );
            my $error_file = File::Spec->catfile(
                    $output_dir, 'realign_windows.e', );
            
            my $cmd = join(q{ },
                $options{dindel_bin},
                '--analysis indels',
                "--bamFile $bam_file",
                '--doDiploid',
                "--maxRead 50000",
                join(q{ }, '--ref', $options{reference}, ),
                "--varFile $window_file",
                "--libFile $lib_file",
                "--outputFile $window_out_prefix",
                "> $out_file",
                "2> $error_file",
            );
            
            warn $cmd, "\n" if $options{debug};
            system($cmd) == 0
                or die "system $cmd failed: $?";
            
            my $glf_file = join(q{.}, $window_out_prefix, 'glf', 'txt', );
            if( !-e $glf_file ){
                die "Dindel realign windows: Couldn't find glf file $glf_file.\n";
            }
            push @glf_files, $glf_file;
        }    
        print "Realign Windows done.\n" if $options{verbose};
        return @glf_files;
    }
}

sub dindel_make_vcf_file {
    my ( $output_dir, $sample_name, $glf_files, ) = @_;

    my $output_vcf_file = File::Spec->catfile(
        $output_dir, 'calls.vcf', );
    
    # check whether vcf file exists
    if( -e $output_vcf_file && -s $output_vcf_file ){
        print "Convert to vcf already done.\n" if $options{verbose};
        return $output_vcf_file;
    }
    else{
        my $merge_output_py = File::Spec->catfile(
            $options{dindel_scripts},
            'mergeOutputDiploid.py',
        );
        
        # make glf file of file names
        my $glf_fofn = File::Spec->catfile( $output_dir, 'glf.fofn');
        open my $ofh, '>', $glf_fofn;
        print $ofh join("\n", @{$glf_files} ), "\n";
        close($ofh);
        
        my $cmd = join(q{ },
            'python',
            $merge_output_py,
            "--inputFiles $glf_fofn",
            "--outputFile $output_vcf_file",
            "--sampleID $sample_name",
            join(q{ }, '--ref', $options{reference}, ),
        );
        
        warn $cmd, "\n" if $options{debug};
        system($cmd) == 0
            or die "system $cmd failed: $?";
        
        print "Convert to vcf done.\n" if $options{verbose};
        return $output_vcf_file;
    }
}



sub get_and_check_options {
    
    GetOptions(
        \%options,
        'output_directory=s',
        'bam_file=s',
        'alternate_sample_name=s',
        'analysis_id=i',
        'dindel_bin=s',
        'dindel_scripts=s',
        'reference=s',
        'help',
        'man',
        'debug+',
        'verbose',
    ) or pod2usage(2);
    
    # Documentation
    if( $options{help} ) {
        pod2usage( -verbose => 0, exitval => 1, );
    }
    elsif( $options{man} ) {
        pod2usage( -verbose => 2 );
    }
    
    if( !$options{output_directory} ){
        $options{output_directory} = 'results';
    }
    
    
    if( !$options{dindel_bin} ){
        $options{dindel_bin} = which( 'dindel' );
    }
    if( !defined $options{dindel_bin} ){
        my $msg = join(q{ }, "Couldn't find dindel in the current path!",
            "Please change path or specify option --dindel_bin", );
        pod2usage($msg);
    }
    # Check dindel can be run
    my $dindel_test_cmd = join(q{ }, $options{dindel_bin}, '2>&1' );
    open my $dindel_fh, '-|', $dindel_test_cmd;
    my @lines;
    while(<$dindel_fh>){
        chomp;
        push @lines, $_;
    }
    if( $lines[0] ne 'Error: One of the following options was not specified:  --ref --tid or --outputFile' ){
        my $msg = join("\n", 'Could not run dindel: ', @lines, ) . "\n";
        pod2usage( $msg );
    }
    
    if( !$options{dindel_scripts} ){
        my $err_msg = join(q{ }, 'Option --dindel_scripts',
            'must be specified unless the --no_dindel option is set.',
            ) . "\n";
        pod2usage( $err_msg );
    }
    else{
        if( !-d $options{dindel_scripts} || !-r $options{dindel_scripts} ||
           !-x $options{dindel_scripts} ){
            my $err_msg = join(q{ }, "Dindel scripts directory:",
                $options{dindel_scripts},
                "does not exist or is not readable/executable!\n" );
            pod2usage( $err_msg );
        }
    }
    
    # CHECK REFERENCE EXISTS
    if( exists $options{reference} ){
        if( ! -e $options{reference} || ! -f $options{reference} || ! -r $options{reference} ){
            my $err_msg = join(q{ }, "Reference file:", $options{reference}, "does not exist or is not readable!\n" );
            pod2usage( $err_msg );
        }
    }
    
    $options{analysis_id} = $options{analysis_id} ? $options{analysis_id} : 1;
    
    if( !$options{debug} ){
        $options{debug} = 0;
    }
    
    print "Settings:\n", map { join(' - ', $_, defined $options{$_} ? $options{$_} : 'off'),"\n" } sort keys %options if $options{verbose};
}

__END__

=pod

=head1 NAME

run_dindel.pl

=head1 DESCRIPTION

Description

=cut

=head1 SYNOPSIS

    run_dindel.pl [options] sample_name
        --output_directory          directory for output files                  default: results
        --bam_file                  name of the sample bam file
        --alternate_sample_name     alternate sample name to enter in the final vcf
        --analysis_id               number of the analysis                      default: 1
        --dindel_bin                path of the dindel binary
        --dindel_scripts            path of the dindel python scripts folder
        --reference                 genome reference file
        --help                      print this help message
        --man                       print the manual page
        --debug                     print debugging information
        --verbose                   turn on verbose output


=head1 ARGUMENTS

=over

=item B<sample_name>

A sample name to identified. The sample name is expected to be of the form runID_lane#index.varNum

=back

=head1 OPTIONS

=over

=item B<--output_directory>

Directory for output files [default: results]

=item B<--bam_file>

name of the sample bam file. Required

=item B<--alternate_sample_name>

If the sample has an alternate name not of the form runID_lane#index.varNum, this can be specified here.

=item B<--analysis_id>

An analysis id. Directories for samples from the same analysis will then be placed in the same directory [default: 1]

=item B<--dindel_bin>

Location of the dindel binary. If this is not specified then the script tries
to locate dindel in the current path and if it can't do that it exits

=item B<--dindel_scripts>

Location of the folder that the python scripts are in. Required.

=item B<--reference>

Path to the genome reference file.

=item B<--debug>

Print debugging information.

=item B<--help>

Print a brief help message and exit.

=item B<--man>

Print this script's manual page and exit.

=back

=head1 DEPENDENCIES

Crispr

=head1 AUTHOR

=over 4

=item *

Richard White <richard.white@sanger.ac.uk>

=back

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2016 by Genome Research Ltd.

This is free software, licensed under:

  The GNU General Public License, Version 3, June 2007

=cut
