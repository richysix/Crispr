package TestMethods;
use Moose;
use File::Spec;
use English qw( -no_match_vars );
use Bio::EnsEMBL::Registry;
use Bio::SeqIO;
use Bio::Seq;
use TestDBConnection;

has 'slice_adaptor' => (
    is => 'ro',
    isa => 'Bio::EnsEMBL::DBSQL::SliceAdaptor',
    lazy => 1,
    builder => '_build_slice_adaptor',
);

sub create_test_db {
    my ( $self, ) = @_;
    
    my %db_connection_params = (
        mysql => {
            driver => 'mysql',
            dbname => $ENV{MYSQL_DBNAME},
            host => $ENV{MYSQL_DBHOST},
            port => $ENV{MYSQL_DBPORT},
            user => $ENV{MYSQL_DBUSER},
            pass => $ENV{MYSQL_DBPASS},
        },
        sqlite => {
            driver => 'sqlite',
            dbfile => 'test.db',
            dbname => 'test',
        }
    );
    
    # TestDB creates test database, connects to it and gets db handle
    my @db_connections;
    foreach my $driver ( 'mysql', 'sqlite' ){
        my $adaptor;
        eval {
            $adaptor = TestDBConnection->new( $driver );
        };
        if( $EVAL_ERROR ){
            if( $EVAL_ERROR =~ m/ENVIRONMENT VARIABLES/ ){
                warn "The following environment variables need to be set for testing connections to a MySQL database!\n",
                        q{$MYSQL_DBNAME, $MYSQL_DBHOST, $MYSQL_DBPORT, $MYSQL_DBUSER, $MYSQL_DBPASS}, "\n";
            }
        }
        if( defined $adaptor ){
            # reconnect to db using DBConnection
            push @db_connections, $adaptor;
        }
    }
    
    return ( \%db_connection_params, \@db_connections );
}


sub check_for_test_genome {
    my ( $self, $test_genome_prefix ) = @_;
    
    my $genome_file = $test_genome_prefix   ?   $test_genome_prefix
        :                                       'mock_genome.fa';
    my $genome_file_path = File::Spec->catfile( 't/data', $genome_file );
    
    #check whether file exists
    if( !-e $genome_file_path ){
        # create file from Ensembl
        my $slice = $self->slice_adaptor->fetch_by_region( 'toplevel', '3',  );
        # need to make a new Bio::Seq object because need to change display_id to 3
        my $chr3 = Bio::Seq->new(
            -display_id => '3',
            -seq => $slice->seq,
        );
        
        # write to fasta file
        my $out = Bio::SeqIO->new(-format=>'Fasta',
                                  -file => ">$genome_file_path", );
        $out->write_seq($chr3);
    }
    
    # check whether bwa index exists
    my $bwa_index_file = File::Spec->catfile( 't/data', $genome_file . '.bwt' );
    if( !-e $bwa_index_file ){
        my $index_cmd = join(q{ }, 'bwa', 'index', $genome_file_path, '2> /dev/null');
        eval{ system( $index_cmd ) };
        if( $EVAL_ERROR ){
            confess "Attempt to index test genome file $genome_file_path failed!",
                $EVAL_ERROR;
        }
    }
}

sub check_for_annotation {
    my ( $self, $annotation_file_name ) = @_;
    
    my $annotation_file = $annotation_file_name   ?     $annotation_file_name
        :                                               'mock_annotation.gff';
    my $annotation_file_path = File::Spec->catfile( 't/data', $annotation_file );
    my $slice = $self->slice_adaptor->fetch_by_region( 'toplevel', '3',  );
    
    if( !-e $annotation_file_path ){
        # output annotation to gff
        my %exon_seen;
        my %intron_seen;
        
        # open output file
        open my $gff_fh, '>', $annotation_file_path;
        
        #get all exons
        my $genes = $slice->get_all_Genes();
        
        foreach my $gene ( @{$genes} ){
            next if( $gene->biotype =~ m/pseudogene/xms );
            my $gene_id = $gene->stable_id();
            my $transcripts = $gene->get_all_Transcripts();
            foreach my $transcript ( @{$transcripts} ){
                my $exons = $transcript->get_all_Exons();
                foreach my $exon ( @{$exons} ){
                    my $exon_id = $exon->stable_id;
                    if( exists $exon_seen{$exon_id} ){
                        next;
                    }
                    else{
                        $exon_seen{$exon_id} = 1;
                    }
                    my $name = $exon->seq_region_name();
                    my $start = $exon->seq_region_start();
                    my $end = $exon->seq_region_end();
                    my $strand = $exon->seq_region_strand();
                    $strand = $strand eq '1'    ?       '+'
                        :                               '-';
                    print {$gff_fh} join("\t", $name, 'Ensembl', 'exon',
                                        $start, $end, '.', $strand,'.',
                                        join(';',
                                            join('=', 'exon_id', $exon_id),
                                            join('=', 'gene_id', $gene_id),
                                        ), ), "\n";
                }
                
                my $introns = $transcript->get_all_Introns();
                if( defined $introns){
                    my $transcript_id = $transcript->stable_id();
                    foreach my $intron ( @{$introns} ){
                        my $name = $intron->seq_region_name();
                        my $start = $intron->seq_region_start();
                        my $end = $intron->seq_region_end();
                        #my $intron_length = $end - $start + 1;
                        #
                        #if ( $count == 1 ){
                        #    $total_bases += $intron_length;
                        #    next INTRON;
                        #}
                        
                        my $prev_exon = $intron->prev_Exon()->stable_id();
                        my $next_exon = $intron->next_Exon()->stable_id();
                        my $intron_id = $prev_exon . '-' . $next_exon;
                        
                        my $strand = $intron->seq_region_strand();
                        $strand = $strand eq '1'    ?       '+'
                            :                               '-';
                        
                        print {$gff_fh}
                            join("\t", $name, 'get_introns', 'intron',
                                $start, $end, '.', $strand, '.',
                                join(";",
                                    join("=", 'gene_id', $gene_id,),
                                    join("=", 'transcript_id', $transcript_id ),
                                    join("=", 'intron_id', $intron_id, ),
                                    ),
                                ), "\n";
                    }            
                }
            }
        }
    }
}

sub _build_slice_adaptor {
    my ( $self, ) = @_;
    
    # connect to db
    Bio::EnsEMBL::Registry->load_registry_from_db(
        -host    => 'ensembldb.ensembl.org',
        -user    => 'anonymous',
        -port    => 5306,
        -verbose => 0,
        -species => 'danio_rerio', );
    
    #my $slice_adaptor = Bio::EnsEMBL::Registry->get_adaptor( 'zebrafish', 'core', 'slice' );
    my $slice_adaptor = Bio::EnsEMBL::Registry->get_adaptor( 'danio_rerio', 'core', 'slice' );
    return $slice_adaptor;
}

no Moose;
__PACKAGE__->meta->make_immutable;
1;

##########################
# DOCUMENTATION
##########################


=head1 TestMethods
 
TestMethods - methods to share between test scripts
 
 
=head1 VERSION
 
This documentation refers to TestMethods version 0.0.1
 
 
=head1 SYNOPSIS
 
  use TestMethods;
  
  
=head1 DESCRIPTION
  
 
=head1 SUBROUTINES/METHODS 
  
 
=head1 DIAGNOSTICS
 
 
 
=head1 CONFIGURATION AND ENVIRONMENT
 
 
 
=head1 DEPENDENCIES
  
 
=head1 INCOMPATIBILITIES
 
