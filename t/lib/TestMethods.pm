package TestMethods;
use Moose;
use File::Spec;
use English qw( -no_match_vars );
use Bio::EnsEMBL::Registry;
use Bio::SeqIO;
use Bio::Seq;
use TestDBConnection;
use Test::MockObject;

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
            dbname => $ENV{MYSQL_TEST_DBNAME},
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
                        q{MYSQL_TEST_DBNAME, $MYSQL_DBHOST, $MYSQL_DBPORT, $MYSQL_DBUSER, $MYSQL_DBPASS}, "\n";
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
    # force mock genome to get reindexed
    my $db = Bio::DB::Fasta->new( $genome_file_path, -reindex );
    
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
    
    if( !-e $annotation_file_path ){
        my $slice = $self->slice_adaptor->fetch_by_region( 'toplevel', '3',  );
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

sub create_mock_object_and_add_to_db {
    my ( $self, $type, $args, $db_connection, ) = @_;
    
    my ( $mock_object, $db_id );
    if( $type eq 'plex' ){
        ( $mock_object, $db_id ) = $self->create_and_add_plex_object( $db_connection, $args, );
    }
    elsif( $type eq 'cas9' ){
        ( $mock_object, $db_id ) = $self->create_and_add_cas9_object( $db_connection, $args, );
    }
    elsif( $type eq 'cas9_prep' ){
        ( $mock_object, $db_id ) = $self->create_and_add_cas9_prep_object( $db_connection, $args, );
    }
    elsif( $type eq 'target' ){
        ( $mock_object, $db_id ) = $self->create_and_add_target_object( $db_connection, $args, );
    }
    elsif( $type eq 'plate' ){
        ( $mock_object, $db_id ) = $self->create_and_add_plate_object( $db_connection, $args, );
    }
    elsif( $type eq 'crRNA' ){
        ( $mock_object, $db_id ) = $self->create_and_add_crRNA_object( $db_connection, $args, );
    }
    elsif( $type eq 'allele' ){
        ( $mock_object, $db_id ) = $self->create_and_add_allele_object( $db_connection, $args, );
    }
    elsif( $type eq 'well' ){
        ( $mock_object, $db_id ) = $self->create_well_object( $db_connection, $args, );
    }
    elsif( $type eq 'gRNA' ){
        ( $mock_object, $db_id ) = $self->create_and_add_gRNA_object( $db_connection, $args, );
    }
    elsif( $type eq 'injection_pool' ){
        ( $mock_object, $db_id ) = $self->create_and_add_injection_pool_object( $db_connection, $args, );
    }
    elsif( $type eq 'sample' ){
        ( $mock_object, $db_id ) = $self->create_and_add_sample_object( $db_connection, $args, );
    }

    return ( $mock_object, $db_id );
}

sub create_and_add_plex_object {
    my ( $self, $db_connection, $args, ) = @_;
    
    # make mock Plex object
    my $mock_plex = Test::MockObject->new();
    $mock_plex->set_isa( 'Crispr::DB::Plex' );
    my $p_id = 1;
    $mock_plex->mock( 'db_id', sub{ my @args = @_; if( $_[1] ){ $p_id = $_[1] } return $p_id; } );
    $mock_plex->mock( 'plex_name', sub{ return 'miseq14' } );
    $mock_plex->mock( 'run_id', sub{ return 13831 } );
    $mock_plex->mock( 'analysis_started', sub{ return '2014-09-27' } );
    $mock_plex->mock( 'analysis_finished', sub{ return undef } );
    
    if( $args->{add_to_db} ){
        my $dbh = $db_connection->connection->dbh;
        # insert directly into db
        my $statement = "insert into plex values( ?, ?, ?, ?, ? );";
        my $sth = $dbh->prepare($statement);
        $sth->execute(
            $mock_plex->db_id,
            $mock_plex->plex_name,
            $mock_plex->run_id,
            $mock_plex->analysis_started,
            $mock_plex->analysis_finished,
        );
    }
    
    return ( $mock_plex, $p_id );
}

sub create_and_add_cas9_object {
    my ( $self, $db_connection, $args, ) = @_;
    
    my $type = 'ZfnCas9n';
    my $vector = 'pCS2';
    my $name = join(q{-}, $vector, $type, );
    my $species = 's_pyogenes';
    my $target_seq = 'NNNNNNNNNNNNNNNNNN';
    my $pam = 'NGG';
    my $crispr_target_seq = $target_seq . $pam;
    my $mock_cas9_object = Test::MockObject->new();
    $mock_cas9_object->set_isa( 'Crispr::Cas9' );
    $mock_cas9_object->mock( 'db_id', sub{ return 1 } );
    $mock_cas9_object->mock( 'type', sub{ return $type } );
    $mock_cas9_object->mock( 'species', sub{ return $species } );
    $mock_cas9_object->mock( 'target_seq', sub{ return $target_seq } );
    $mock_cas9_object->mock( 'PAM', sub{ return $pam } );
    $mock_cas9_object->mock( 'name', sub{ return $name } );
    $mock_cas9_object->mock( 'vector', sub{ return $vector } );
    $mock_cas9_object->mock( 'species', sub{ return $species } );
    $mock_cas9_object->mock( 'crispr_target_seq', sub{ return $crispr_target_seq } );
    $mock_cas9_object->mock( 'info', sub{ return ( $type, $species, $crispr_target_seq ) } );
    
    if( $args->{add_to_db} ){
        my $dbh = $db_connection->connection->dbh;
        # insert directly into db
        my $statement = "insert into cas9 values( ?, ?, ?, ?, ? );";
        my $sth = $dbh->prepare($statement);
        $sth->execute( $mock_cas9_object->db_id,
            $mock_cas9_object->name,
            $mock_cas9_object->type,
            $mock_cas9_object->vector,
            $mock_cas9_object->species,
            );
    }    
    return ( $mock_cas9_object, 1 );
}

sub create_and_add_cas9_prep_object {
    my ( $self, $db_connection, $args, ) = @_;
    
    my $prep_type = 'rna';
    my $made_by = 'cr_test';
    my $todays_date_obj = DateTime->now();
    my $mock_cas9_prep_object_1 = Test::MockObject->new();
    $mock_cas9_prep_object_1->set_isa( 'Crispr::DB::Cas9Prep' );
    $mock_cas9_prep_object_1->mock( 'db_id', sub{ return 1 } );
    $mock_cas9_prep_object_1->mock( 'cas9', sub{ return $args->{mock_cas9_object} } );
    $mock_cas9_prep_object_1->mock( 'prep_type', sub{ return $prep_type } );
    $mock_cas9_prep_object_1->mock( 'made_by', sub{ return $made_by } );
    $mock_cas9_prep_object_1->mock( 'date', sub{ return $todays_date_obj->ymd } );
    $mock_cas9_prep_object_1->mock( 'type', sub{ return $args->{mock_cas9_object}->type } );
    $mock_cas9_prep_object_1->mock( 'notes', sub{ return 'some notes' } );
    $mock_cas9_prep_object_1->mock('concentration', sub { return 200 } );

    if( $args->{add_to_db} ){
        my $dbh = $db_connection->connection->dbh;
        # insert directly into db
        my $statement = "insert into cas9_prep values( ?, ?, ?, ?, ?, ? );";
        my $sth = $dbh->prepare($statement);
        $sth->execute( $mock_cas9_prep_object_1->db_id, $args->{mock_cas9_object}->db_id,
            $mock_cas9_prep_object_1->prep_type, $mock_cas9_prep_object_1->made_by,
            $mock_cas9_prep_object_1->date, $mock_cas9_prep_object_1->notes  );
    }    
    return ( $mock_cas9_prep_object_1, 1 );
}

sub create_and_add_target_object {
    my ( $self, $db_connection, $args, ) = @_;
    
    # make a new mock target object
    my $mock_target = Test::MockObject->new();
    $mock_target->set_isa( 'Crispr::Target' );
    my $t_id = 1;
	$mock_target->mock('target_id', sub{ my @args = @_; if( $_[1] ){ $t_id = $_[1] } return $t_id; } );
	$mock_target->mock('target_name', sub { return 'SLC39A14' } );
	$mock_target->mock('assembly', sub { return 'Zv9' } );
	$mock_target->mock('chr', sub { return '5' } );
	$mock_target->mock('start', sub { return 18067321 } );
	$mock_target->mock('end', sub { return 18083466 } );
	$mock_target->mock('strand', sub { return '-1' } );
	$mock_target->mock('species', sub { return 'danio_rerio' } );
	$mock_target->mock('requires_enzyme', sub { return 'n' } );
	$mock_target->mock('gene_id', sub { return 'ENSDARG00000090174' } );
	$mock_target->mock('gene_name', sub { return 'SLC39A14' } );
	$mock_target->mock('requestor', sub { return 'crispr_test' } );
	$mock_target->mock('ensembl_version', sub { return 71 } );
	$mock_target->mock('status', sub { return 'INJECTED'; } );
	$mock_target->mock('status_id', sub { return 5; } );
	$mock_target->mock('status_changed', sub { return '2015-11-30' } );
    
    if( $args->{add_to_db} ){
        my $dbh = $db_connection->connection->dbh;
        # insert directly into db
        my $statement = "insert into target values( ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ? );";
        my $sth = $dbh->prepare($statement);
        $sth->execute(
            $mock_target->target_id,
            $mock_target->target_name,
            $mock_target->assembly,
            $mock_target->chr,
            $mock_target->start,
            $mock_target->end,
            $mock_target->strand,
            $mock_target->species,
            $mock_target->requires_enzyme,
            $mock_target->gene_id,
            $mock_target->gene_name,
            $mock_target->requestor,
            $mock_target->ensembl_version,
            $mock_target->status_id,
            $mock_target->status_changed,
        );
    }
    return ( $mock_target, $t_id );
}

sub create_and_add_plate_object {
    my ( $self, $db_connection, $args, ) = @_;
    
    my $mock_plate = Test::MockObject->new();
    $mock_plate->set_isa('Crispr::Plate');
    my $pl_id = 1;
    $mock_plate->mock('plate_id', sub { my @args = @_; if( $_[1] ){ $pl_id = $_[1] } return $pl_id; } );
    $mock_plate->mock('plate_name', sub { return 'CR_000001-' } );
    $mock_plate->mock('plate_type', sub { return '96' } );
    $mock_plate->mock('plate_category', sub { return 'crispr' } );
    $mock_plate->mock('ordered', sub { return '2015-01-12' } );
    $mock_plate->mock('received', sub { return '2015-01-19' } );
    
    if( $args->{add_to_db} ){
    my $dbh = $db_connection->connection->dbh;
        my $statement = "insert into plate values( ?, ?, ?, ?, ?, ? );";
        my $sth = $dbh->prepare($statement);
        $sth->execute(
            $mock_plate->plate_id,
            $mock_plate->plate_name,
            $mock_plate->plate_type,
            $mock_plate->plate_category,
            $mock_plate->ordered,
            $mock_plate->received,
        );
    }
    return ( $mock_plate, $pl_id );
}

sub create_and_add_crRNA_object {
    my ( $self, $db_connection, $args, ) = @_;
    
    my $crRNA_args = {
        1 => {
            'crRNA_id' => sub{ return 1 },
            'crRNA_name', => sub{ return 'crRNA:5:50383-50405:-1' },
            'chr' => sub{ return '5' },
            'start' => sub{ return '50383' },
            'end' => sub{ return '50405' },
            'strand' => sub{ return '-1' },
            'cut_site' => sub{ return '50388' },
            'sequence' => sub{ return 'GGAATAGAGAGATAGAGAGTCGG' },
            'forward_oligo' => sub{ return 'ATGGGGAATAGAGAGATAGAGAGT' },
            'reverse_oligo' => sub{ return 'AAACACTCTCTATCTCTCTATTCC' },
            'score' => sub{ return '0.853' },
            'coding_score' => sub{ return '0.853' },
            'off_target_score' => sub{ return '0.95' },
            'target_id' => sub{ return '1' },
            'target' => sub{ return $args->{mock_target} },
            'unique_restriction_sites' => sub { return undef },
            'coding_scores' => sub { return undef },
            'off_target_hits' => sub { return undef },
            'plasmid_backbone' => sub { return 'pDR274' },
            'num_five_prime_Gs' => sub { return 2 },
            'plate_id' => sub { return 1 },
            'well_id' => sub { return 'A01' },
            'primer_pairs' => sub { return undef },
            'status' => sub { return 'PASSED_EMBRYO_SCREENING' },
            'status_id' => sub { return 7 },
            'status_changed' => sub { return '2015-01-26' },
            'info' => sub { return ( qw{ crRNA:5:50383-50405:-1 5 50383
                50405 -1 0.853 GGAATAGAGAGATAGAGAGTCGG ATGGGGAATAGAGAGATAGAGAGT
                AAACACTCTCTATCTCTCTATTCC NULL NULL NULL NULL NULL NULL NULL 2 pDR274 } ); },
        },
        2 => {
            'crRNA_id' => sub{ return 2 },
            'crRNA_name', => sub{ return 'crRNA:4:21-43:1' },
            'chr' => sub{ return '4' },
            'start' => sub{ return 21 },
            'end' => sub{ return 43 },
            'strand' => sub{ return '1' },
            'cut_site' => sub{ return 37 },
            'sequence' => sub{ return 'TAGATCAGTAGATCGATAGTAGG' },
            'forward_oligo' => sub{ return 'ATGGGGAATAGAGAGATAGAGAGT' },
            'reverse_oligo' => sub{ return 'AAACACTCTCTATCTCTCTATTCC' },
            'score' => sub{ return '0.81' },
            'coding_score' => sub{ return '0.9' },
            'off_target_score' => sub{ return '0.9' },
            'target_id' => sub{ return '1' },
            'target' => sub{ return $args->{mock_target} },
            'unique_restriction_sites' => sub { return undef },
            'coding_scores' => sub { return undef },
            'off_target_hits' => sub { return undef },
            'plasmid_backbone' => sub { return 'pDR274' },
            'num_five_prime_Gs' => sub { return 0 },
            'plate_id' => sub { return 1 },
            'well_id' => sub { return 'B01' },
            'primer_pairs' => sub { return undef },
            'status' => sub { return 'FAILED_SPERM_SCREENING' },
            'status_id' => sub { return 11 },
            'status_changed' => sub { return '2015-03-26' },
            'info', sub { return ( qw{ crRNA:5:50403-50425:-1 5 50403
                50425 1 0.853 GGAATAGAGAGATAGAGAGTCGG ATGGGGAATAGAGAGATAGAGAGT
                AAACACTCTCTATCTCTCTATTCC NULL NULL NULL NULL NULL NULL NULL 2 pDR274 } ); },
        },
    };

    my $mock_crRNA = Test::MockObject->new();
    $mock_crRNA->set_isa('Crispr::crRNA');
    foreach my $meth ( keys $crRNA_args->{ $args->{crRNA_num} } ){
        $mock_crRNA->mock($meth, $crRNA_args->{ $args->{crRNA_num} }->{$meth} );
    }

    if( $args->{add_to_db} ){
        my $dbh = $db_connection->connection->dbh;
        # add to db
        my $statement = "insert into crRNA values( ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ? );";
        my $sth = $dbh->prepare($statement);
        $sth->execute(
            $mock_crRNA->crRNA_id,
            $mock_crRNA->crRNA_name,
            $mock_crRNA->chr,
            $mock_crRNA->start,
            $mock_crRNA->end,
            $mock_crRNA->strand,
            $mock_crRNA->sequence,
            $mock_crRNA->num_five_prime_Gs,
            $mock_crRNA->score,
            $mock_crRNA->off_target_score,
            $mock_crRNA->coding_score,
            $mock_crRNA->target_id,
            $mock_crRNA->plate_id,
            $mock_crRNA->well_id,
            $mock_crRNA->status_id,
            $mock_crRNA->status_changed,
        );
    }
    return ( $mock_crRNA, $mock_crRNA->crRNA_id );
}

sub create_well_object {
    my ( $self, $db_connection, $args, ) = @_;
    
    my $mock_well = Test::MockObject->new();
    $mock_well->set_isa('Labware::Well');
    $mock_well->mock( 'plate', sub{ return $args->{mock_plate} } );
    $mock_well->mock( 'plate_type', sub{ return '96' } );
    $mock_well->mock( 'position', sub{ return 'A01' } );
    
    return $mock_well;
}

sub create_and_add_gRNA_object {
    my ( $self, $db_connection, $args, ) = @_;
    
    my $gRNA_args = {
        1 => {
            'db_id' => sub{ return 1 },
            'type' => sub{ return 'sgRNA' },
            'stock_concentration' => sub{ return 50 },
            'injection_concentration' => sub{ return 10 },
            'made_by' => sub{ return 'cr1' },
            'date' => sub{ return '2014-10-02' },
            'crRNA' => sub{ return $args->{mock_crRNA} },
            'crRNA_id' => sub{ return $args->{mock_crRNA}->crRNA_id },
            'well' => sub{ return $args->{mock_well} },
        },
        2 => {
            'db_id' => sub{ return 2 },
            'type' => sub{ return 'sgRNA' },
            'stock_concentration' => sub{ return 50 },
            'injection_concentration' => sub{ return 10 },
            'made_by' => sub{ return 'cr1' },
            'date' => sub{ return '2014-10-02' },
            'crRNA' => sub{ return $args->{mock_crRNA} },
            'crRNA_id' => sub{ return $args->{mock_crRNA}->crRNA_id },
            'well' => sub{ return $args->{mock_well} },
        },
    };
    
    my $mock_gRNA = Test::MockObject->new();
    $mock_gRNA->set_isa( 'Crispr::guideRNA_prep' );
    foreach my $meth ( keys $gRNA_args->{ $args->{gRNA_num} } ){
        $mock_gRNA->mock($meth, $gRNA_args->{ $args->{gRNA_num} }->{$meth} );
    }
    
    if( $args->{add_to_db} ){
        my $dbh = $db_connection->connection->dbh;
        # add to db
        my $statement = "insert into guideRNA_prep values( ?, ?, ?, ?, ?, ?, ?, ? );";
        my $sth = $dbh->prepare($statement);
        $sth->execute(
            $mock_gRNA->db_id,
            $mock_gRNA->crRNA_id,
            $mock_gRNA->type,
            $mock_gRNA->stock_concentration,
            $mock_gRNA->made_by,
            $mock_gRNA->date,
            $mock_gRNA->well->plate->plate_id,
            $mock_gRNA->well->position,
        );
    }
    
    return ( $mock_gRNA, $mock_gRNA->db_id );
}

sub create_and_add_allele_object {
    my ( $self, $db_connection, $args, ) = @_;
    
    my $mock_allele = Test::MockObject->new();
    $mock_allele->set_isa('Crispr::Allele');
    my $allele_id = 1;
    $mock_allele->mock('db_id', sub { return $allele_id } );
    $mock_allele->mock('allele_number', sub { return 31121 } );
    $mock_allele->mock('chr', sub { return 'Zv9_scaffold12' } );
    $mock_allele->mock('pos', sub { return 256738 } );
    $mock_allele->mock('ref_allele', sub { return 'ACGTA' } );
    $mock_allele->mock('alt_allele', sub { return 'A' } );
    $mock_allele->mock('crisprs', sub{ return [ $args->{ mock_crRNA }, ]; } );
    $mock_allele->mock('percent_of_reads', sub{ return 10.4; } );
    
    if( $args->{add_to_db} ){
        my $dbh = $db_connection->connection->dbh;
        # add to db
        my $statement = "insert into allele values( ?, ?, ?, ?, ?, ? );";
        my $sth = $dbh->prepare($statement);
        $sth->execute(
            $mock_allele->db_id,
            $mock_allele->allele_number,
            $mock_allele->chr,
            $mock_allele->pos,
            $mock_allele->ref_allele,
            $mock_allele->alt_allele,
        );
    }
    
    return ( $mock_allele, $allele_id );
}

sub create_and_add_injection_pool_object {
    my ( $self, $db_connection, $args, ) = @_;
    
    my $mock_injection_pool = Test::MockObject->new();
    $mock_injection_pool->set_isa( 'Crispr::DB::InjectionPool' );
    my $i_id = 1;
    $mock_injection_pool->mock( 'db_id', sub{ my @args = @_; if( $_[1] ){ $i_id = $_[1] } return $i_id; } );
    $mock_injection_pool->mock( 'pool_name', sub{ return '170' } );
    $mock_injection_pool->mock( 'cas9_prep', sub{ return $args->{mock_cas9_prep} } );
    $mock_injection_pool->mock( 'cas9_conc', sub{ return 200 } );
    $mock_injection_pool->mock( 'date', sub{ return '2014-10-13' } );
    $mock_injection_pool->mock( 'line_injected', sub{ return 'H1530' } );
    $mock_injection_pool->mock( 'line_raised', sub{ return undef } );
    $mock_injection_pool->mock( 'sorted_by', sub{ return 'cr_1' } );
    $mock_injection_pool->mock( 'guideRNAs', sub{ return [ $args->{mock_gRNA_1}, $args->{mock_gRNA_2}, ] } );

    if( $args->{add_to_db} ){
        my $dbh = $db_connection->connection->dbh;
        # add to db
        my $statement = "insert into injection values( ?, ?, ?, ?, ?, ?, ?, ? );";
        my $sth = $dbh->prepare($statement);
        $sth->execute(
            $mock_injection_pool->db_id,
            $mock_injection_pool->pool_name,
            $mock_injection_pool->cas9_prep->db_id,
            $mock_injection_pool->cas9_prep->concentration,
            $mock_injection_pool->date,
            $mock_injection_pool->line_injected,
            $mock_injection_pool->line_raised,
            $mock_injection_pool->sorted_by,
        );
        
        $statement = "insert into injection_pool values( ?, ?, ?, ? );";
        $sth = $dbh->prepare($statement);
        foreach my $mock_gRNA ( @{ $mock_injection_pool->guideRNAs } ){
            $sth->execute(
                $mock_injection_pool->db_id,
                $mock_gRNA->crRNA_id,
                $mock_gRNA->db_id,
                $mock_gRNA->injection_concentration,
            );
        }
    }
    return ( $mock_injection_pool, $i_id );
}

sub create_and_add_sample_object {
    my ( $self, $db_connection, $args, ) = @_;
    
    my $mock_sample = Test::MockObject->new();
    $mock_sample->set_isa( 'Crispr::DB::InjectionPool' );
    my $s_id = 1;
    $mock_sample->mock( 'db_id', sub{ my @args = @_; if( $_[1] ){ $s_id = $_[1] } return $s_id; } );
    $mock_sample->mock( 'sample_name', sub{ return '170_A01' } );
    $mock_sample->mock( 'sample_number', sub{ return 1 } );
    $mock_sample->mock( 'injection_pool', sub{ return $args->{mock_injection_pool} } );
    $mock_sample->mock( 'generation', sub{ return 'G0' } );
    $mock_sample->mock( 'type', sub{ return 'embryo' } );
    $mock_sample->mock( 'species', sub{ return 'zebrafish' } );
    $mock_sample->mock( 'well_id', sub{ return 'A01' } );
    $mock_sample->mock( 'cryo_box', sub{ return 'Cr_Sperm_1' } );
    $mock_sample->mock( 'alleles', sub{ my @args = @_; if( $_[1] ){ $args->{alleles} = $_[1] } return $args->{alleles}; } );

    if( $args->{add_to_db} ){
        my $dbh = $db_connection->connection->dbh;
        # add to db
        my $statement = "insert into sample values( ?, ?, ?, ?, ?, ?, ?, ?, ? );";
        my $sth = $dbh->prepare($statement);
        $sth->execute(
            $mock_sample->db_id,
            $mock_sample->sample_name,
            $mock_sample->sample_number,
            $mock_sample->injection_pool->db_id,
            $mock_sample->generation,
            $mock_sample->type,
            $mock_sample->species,
            $mock_sample->well_id,
            $mock_sample->cryo_box,
        );
    }
    
    return ( $mock_sample, $s_id );
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
 
