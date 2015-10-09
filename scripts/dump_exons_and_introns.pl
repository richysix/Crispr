#!/usr/bin/env perl

# PODNAME: dump_exons_and_introns.pl
# ABSTRACT: output all exons and introns for a species

use warnings;
use strict;
use Getopt::Long;
use autodie;
use Pod::Usage;
use Bio::EnsEMBL::Registry;

# get options
my %options;
get_and_check_options();

my $species = $ARGV[0];

my $out_fh;
# check output file is specified and print to STDOUT if not
if( $options{output_file} ){
    open $out_fh, '>', $options{output_file};
}
else{
    $out_fh = \*STDOUT;
}

# check registry file
if( $options{registry_file} ){
    Bio::EnsEMBL::Registry->load_all( $options{registry_file} );
}
else{
    # if no registry file connect anonymously to the public server
    Bio::EnsEMBL::Registry->load_registry_from_db(
      -host    => 'ensembldb.ensembl.org',
      -user    => 'anonymous',
    );
}
my $ensembl_version = Bio::EnsEMBL::ApiVersion::software_version();

# Ensure database connection isn't lost; Ensembl 64+ can do this more elegantly
## no critic (ProhibitMagicNumbers)
if ( $ensembl_version < 64 ) {
## use critic
    Bio::EnsEMBL::Registry->set_disconnect_when_inactive();
}
else {
    Bio::EnsEMBL::Registry->set_reconnect_when_lost();
}

#get all top-level slices
my $slice_ad = Bio::EnsEMBL::Registry->get_adaptor( $species, 'core', 'slice' );
my $gene_ad = Bio::EnsEMBL::Registry->get_adaptor( $species, 'core', 'gene' );

my $slices = $slice_ad->fetch_all('toplevel');
foreach my $slice ( @{$slices} ){
    # get all genes
    my $genes = $slice->get_all_Genes();
    
    foreach my $gene ( @{$genes} ){
        my ( %exons, %introns );
        my @features;
        
        next if( $gene->biotype =~ m/pseudogene/xms );
        # get all transcripts for this gene
        my $transcripts = $gene->get_all_Transcripts();
        
        foreach my $transcript ( @{$transcripts} ){
            # get all exons
            my $exons = $transcript->get_all_Exons();
            foreach my $exon ( @{$exons} ){
                push @features, $exon;
                push @{$exons{ $exon->stable_id }{transcripts}}, $transcript;
            }
            
            # get all introns
            my $introns = $transcript->get_all_Introns();
            if( defined $introns){
                foreach my $intron ( @{$introns} ){
                    push @features, $intron;
                    my $intron_id = $intron->prev_Exon()->stable_id() . '-' . $intron->next_Exon()->stable_id();
                    push @{$introns{ $intron_id }{transcripts}}, $transcript;
                }
            }
        }
        
        foreach my $feature ( sort { $a->seq_region_start <=> $b->seq_region_start } @features ){
            my $feature_type = ref $feature eq 'Bio::EnsEMBL::Exon' ? 'exon' : 'intron';
            my $strand = $feature->seq_region_strand eq '1' ? '+' : '-';
            my $info_string;
            if( $feature_type eq 'exon' ){
                $info_string = join(';',
                    join('=', 'exon_id', $feature->stable_id),
                    join('=', 'gene_id', $gene->stable_id),
                    join('=', 'transcript_ids', join(',', map { $_->stable_id } @{$exons{ $feature->stable_id }{transcripts}} ) ),
                );
            }
            else{
                my $intron_id = $feature->prev_Exon()->stable_id() . '-' . $feature->next_Exon()->stable_id();
                $info_string = join(';',
                    join('=', 'intron_id', $intron_id ),
                    join('=', 'gene_id', $gene->stable_id ),
                    join('=', 'transcript_ids', join(',', map { $_->stable_id } @{$introns{ $intron_id }{transcripts}} ) ),
                );
            }
            
            print {$out_fh} join("\t",
                $feature->seq_region_name,
                'Ensembl',
                $feature_type,
                $feature->seq_region_start,
                $feature->seq_region_end,
                q{.},
                $strand,
                q{.},
                $info_string
            ), "\n";
        }
    }
}

sub get_and_check_options {
    
    GetOptions(
        \%options,
        'output_file=s',
        'help',
        'man',
        'debug+',
        'verbose',
    ) or pod2usage(2);
    
    # Documentation
    if( $options{help} ) {
        pod2usage( -verbose => 0, -exitval => 1, );
    }
    elsif( $options{man} ) {
        pod2usage( -verbose => 2 );
    }
    
    print "Settings:\n", map { join(' - ', $_, defined $options{$_} ? $options{$_} : 'off'),"\n" } sort keys %options if $options{verbose};
}

__END__

=pod

=head1 NAME

dump_exons_and_introns.pl

=head1 DESCRIPTION

Description

=cut

=head1 SYNOPSIS

    dump_exons_and_introns.pl [options] species
        --output_file           print output to file instead of STDOUT
        --help                  print this help message
        --man                   print the manual page
        --debug                 print debugging information
        --verbose               turn on verbose output


=head1 ARGUMENTS

=over

species    Dump all exons and introns for this species

=back

=head1 OPTIONS

=over

=item B <--output_file>

The name of a file to output to instead of STDOUT

=item B<--debug>

Print debugging information.

=item B<--help>

Print a brief help message and exit.

=item B<--man>

Print this script's manual page and exit.

=back

=head1 DEPENDENCIES

None

=head1 AUTHOR

=over 4

=item *

Richard White <richard.white@sanger.ac.uk>

=back

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2015 by Genome Research Ltd.

This is free software, licensed under:

  The GNU General Public License, Version 3, June 2007

=cut