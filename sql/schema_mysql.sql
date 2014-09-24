create table target (
    target_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    target_name VARCHAR(45) NOT NULL,
    assembly VARCHAR(20),
    chr VARCHAR(30),
    start INT UNSIGNED NOT NULL,
    end INT UNSIGNED NOT NULL,
    strand ENUM( '1', '-1' ) NOT NULL,
    species VARCHAR(50),
    requires_enzyme ENUM( 'n', 'y' ) NOT NULL,
    gene_id VARCHAR (30),
    gene_name VARCHAR (50),
    requestor VARCHAR(50) NOT NULL,
    ensembl_version SMALLINT UNSIGNED,
    designed DATE,
    PRIMARY KEY `target_target_name_requestor` ( `target_name`, `requestor` )
) ENGINE = InnoDB;

create table crRNA (
    crRNA_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    crRNA_name VARCHAR(50),
    chr VARCHAR(30),
    start INT UNSIGNED NOT NULL,
    end INT UNSIGNED NOT NULL,
    strand ENUM( '1', '-1' ) NOT NULL,
    sequence VARCHAR(23) NOT NULL,
    consensus ENUM('GGN19GG', 'N21GG' ) NOT NULL,
    score DECIMAL(4,3),
    off_target_score DECIMAL(4,3),
    coding_score DECIMAL(4,3),
    target_id INT UNSIGNED NOT NULL,
    FOREIGN KEY (target_id) REFERENCES target (target_id)
)  ENGINE = InnoDB;
CREATE UNIQUE INDEX crRNA_crRNA_name_target_id ON crRNA ( crRNA_name, target_id );

create table crRNA_pair (
    crRNA_pair_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    crRNA_pair_name VARCHAR(100) NOT NULL,
    crRNA_1_id INT UNSIGNED NOT NULL,
    crRNA_2_id INT UNSIGNED NOT NULL,
    FOREIGN KEY (crRNA_1_id) REFERENCES crRNA (crRNA_id),
    FOREIGN KEY (crRNA_2_id) REFERENCES crRNA (crRNA_id)
)  ENGINE = InnoDB;

create table coding_scores (
    crRNA_id INT UNSIGNED NOT NULL,
    transcript_id VARCHAR(20),
    score DECIMAL(4,3),
    PRIMARY KEY `coding_scores_crRNA_id_transcript_id` (`crRNA_id`,`transcript_id`),
    FOREIGN KEY (crRNA_id) REFERENCES crRNA(crRNA_id)
) ENGINE = InnoDB;

create table off_target_info (
    crRNA_id INT UNSIGNED NOT NULL,
    off_target_hit VARCHAR(120) NOT NULL,
    mismatches VARCHAR(60) NOT NULL,
    annotation ENUM('exon', 'intron', 'nongenic') NOT NULL,
    PRIMARY KEY `off_target_info_crRNA_id_off_target_hit` (`crRNA_id`,`off_target_hit`),
    FOREIGN KEY (crRNA_id) REFERENCES crRNA(crRNA_id)
)  ENGINE = InnoDB;

create table plate (
    plate_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    plate_name CHAR(10) UNIQUE,
    plate_type ENUM('96', '384') NOT NULL,
    plate_category ENUM('construction_oligos', 't7_hairpin_oligos', 'pcr_primers', 'expression_construct', 'kaspar_assays' ) NOT NULL,
    ordered DATE,
    received DATE
)  ENGINE = InnoDB;

create table plasmid_backbone (
    plasmid_backbone_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    plasmid_backbone VARCHAR(50) NOT NULL
)  ENGINE = InnoDB;

create table construction_oligos (
    crRNA_id INT UNSIGNED NOT NULL,
    forward_oligo VARCHAR(30) NOT NULL,
    reverse_oligo VARCHAR(30),
    plasmid_backbone_id INT UNSIGNED,
    plate_id INT UNSIGNED,
    well_id CHAR(3),
    PRIMARY KEY `construction_oligos_plate_id_well_id` (`plate_id`, `well_id`),
    FOREIGN KEY (crRNA_id) REFERENCES crRNA(crRNA_id),
    FOREIGN KEY (plate_id) REFERENCES plate(plate_id)
)  ENGINE = InnoDB;

create table expression_construct (
    crRNA_id INT UNSIGNED NOT NULL,
    plate_id INT UNSIGNED,
    well_id CHAR(3),
    trace_file VARCHAR(50),
    seq_verified DATE,
    plasmid_backbone_id INT UNSIGNED NOT NULL,
    PRIMARY KEY `expression_construct_plate_id_well_id` (`plate_id`, `well_id`),
    FOREIGN KEY (crRNA_id) REFERENCES crRNA(crRNA_id),
    FOREIGN KEY (plasmid_backbone_id) REFERENCES plasmid_backbone(plasmid_backbone_id),
    FOREIGN KEY (plate_id) REFERENCES plate(plate_id)
)  ENGINE = InnoDB;

create table guideRNA_prep (
    crRNA_id INT UNSIGNED NOT NULL,
    concentration DECIMAL(5,1) NOT NULL,
    made_by VARCHAR(5) NOT NULL,
    date DATE NOT NULL,
    plate_id INT UNSIGNED,
    well_id CHAR(3),
    PRIMARY KEY `guide_RNA_prep_plate_id_well_id` (`plate_id`, `well_id`),
    FOREIGN KEY (crRNA_id) REFERENCES crRNA(crRNA_id),
    FOREIGN KEY (plate_id) REFERENCES plate(plate_id)
) ENGINE = InnoDB;

create table primer (
    primer_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    primer_sequence VARCHAR(50) NOT NULL,
    primer_chr VARCHAR(30),
    primer_start INT UNSIGNED NOT NULL,
    primer_end INT UNSIGNED NOT NULL,
    primer_strand ENUM('1', '-1') NOT NULL,
    primer_tail ENUM('ACACTCTTTCCCTACACGACGCTCTTCCGATCT', 'TCGGCATTCCTGCTGAACCGCTCTTCCGATCT'),
    plate_id INT UNSIGNED,
    well_id CHAR(3),
    FOREIGN KEY (plate_id) REFERENCES plate(plate_id)
) ENGINE = InnoDB;
CREATE INDEX primer_plate_id_well_id_idx ON primer (plate_id, well_id);

create table primer_pair (
    primer_pair_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    type ENUM('ext', 'int', 'illumina', 'illumina_tailed' ) NOT NULL,
    left_primer_id INT UNSIGNED NOT NULL,
    right_primer_id INT UNSIGNED NOT NULL,
    product_size SMALLINT NOT NULL,
    FOREIGN KEY (left_primer_id) REFERENCES primer(primer_id),
    FOREIGN KEY (right_primer_id) REFERENCES primer(primer_id)
) ENGINE = InnoDB;

create table amplicon (
    amplicon_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    primer_pair_id INT UNSIGNED NOT NULL,
    chr VARCHAR(30),
    start INT UNSIGNED NOT NULL,
    end INT UNSIGNED NOT NULL,
    strand ENUM('1', '-1') NOT NULL,
    FOREIGN KEY (primer_pair_id) REFERENCES primer_pair(primer_pair_id)
) ENGINE = InnoDB;

create table amplicon_to_crRNA (
    amplicon_id INT UNSIGNED NOT NULL,
    crRNA_id INT UNSIGNED NOT NULL,
    PRIMARY KEY `amplicon_to_crRNA_amplicon_id_crRNA_id` ( `amplicon_id`, `crRNA_id` ),
    FOREIGN KEY (amplicon_id) REFERENCES amplicon(amplicon_id),
    FOREIGN KEY (crRNA_id) REFERENCES crRNA(crRNA_id)
) ENGINE = InnoDB;


create table enzyme (
    enzyme_id SMALLINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(20) NOT NULL,
    site VARCHAR(20) NOT NULL
) ENGINE = InnoDB;

create table enzyme_ordering (
    order_no VARCHAR(20) PRIMARY KEY,
    enzyme_id SMALLINT UNSIGNED NOT NULL,
    company VARCHAR(20) NOT NULL,
    notes VARCHAR(50),
    last_order DATE,
    FOREIGN KEY (enzyme_id) REFERENCES enzyme(enzyme_id)
) ENGINE = InnoDB;

create table restriction_enzymes (
    primer_pair_id INT UNSIGNED NOT NULL,
    crRNA_id INT UNSIGNED NOT NULL,
    enzyme_id SMALLINT UNSIGNED NOT NULL,
    proximity_to_crRNA_cut_site TINYINT NOT NULL,
    cleavage_products VARCHAR(20),
    PRIMARY KEY `restriction_enzymes_primer_pair_id_crRNA_id_enzyme_id` ( `primer_pair_id`, `crRNA_id`, `enzyme_id` ),
    FOREIGN KEY (primer_pair_id) REFERENCES primer_pair(primer_pair_id),
    FOREIGN KEY (crRNA_id) REFERENCES crRNA(crRNA_id),
    FOREIGN KEY (enzyme_id) REFERENCES enzyme(enzyme_id)
) ENGINE = InnoDB;

create table cas9 (
    cas9_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    cas9_type ENUM( 'Cas9_dnls', 'Cas9_cherry', 'Cas9_nanos' ) NOT NULL,
    substance ENUM('dna', 'rna', 'protein') NOT NULL,
    made_by VARCHAR(5),
    date DATE,
) ENGINE = InnoDB;

create table injection (
    injection_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    injection name INT UNSIGNED NOT NULL,
    cas9_id INT UNSIGNED,
    cas9_concentration INT,
    guideRNA_concentration INT,
    date DATE,
    line_injected VARCHAR(10),
    line_raised VARCHAR(10),
    sorted_by VARCHAR(40),
    FOREIGN KEY (cas9_id) REFERENCES cas9(cas9_id)
) ENGINE = InnoDB;

create table injection_pool (
    injection_id INT UNSIGNED,
    crRNA_id INT UNSIGNED,
    PRIMARY KEY `injection_pool_injection_id_crRNA_id` (`injection_id`,`crRNA_id`),
    FOREIGN KEY (injection_id) REFERENCES injection(injection_id),
    FOREIGN KEY (crRNA_id) REFERENCES crRNA(crRNA_id)
) ENGINE = InnoDB;

create table plex_info (
    plex_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    plex_name INT UNSIGNED NOT NULL,
    run_id INT UNSIGNED NOT NULL
) ENGINE = InnoDB;

create table subplex_info (
    subplex_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    plex_id INT UNSIGNED NOT NULL,
    injection_id INT UNSIGNED NOT NULL,
    FOREIGN KEY (plex_id) REFERENCES plex_info(plex_id)
) ENGINE = InnoDB;

create table sample (
    sample_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    sample_name VARCHAR(20),
    injection_id INT UNSIGNED,
    subplex_id INT UNSIGNED,
    well CHAR(3),
    barcode_number SMALLINT,
    generation ENUM('G0', 'F1', 'F2'),
    type ENUM('sperm', 'embryo', 'finclip'),
    FOREIGN KEY (injection_id) REFERENCES injection(injection_id),
    FOREIGN KEY (subplex_id) REFERENCES subplex_info(subplex_id),
    UNIQUE KEY `sample_name` ('sample_name')
) ENGINE = InnoDB;

create table sequencing_results (
    sample_id INT UNSIGNED NOT NULL,
    amplicon_id INT UNSIGNED NOT NULL,
    fail BOOLEAN NOT NULL,
    num_indels INT UNSIGNED,
    percent_reads DECIMAL(4,3),
    total_reads INT UNSIGNED NOT NULL,
    PRIMARY KEY `sample_amplicon_sample_id_amplicon_id` (`sample_id`,`amplicon_id`),    
    FOREIGN KEY (sample_id) REFERENCES sample(sample_id),
    FOREIGN KEY (amplicon_id) REFERENCES amplicon(amplicon_id)
) ENGINE = InnoDB;

create table allele (
    allele_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    allele_number VARCHAR(10) NOT NULL,
    chr VARCHAR(30) NOT NULL,
    pos INT UNSIGNED NOT NULL,
    ref_allele VARCHAR(200) NOT NULL,
    alt_allele VARCHAR(200) NOT NULL,
    subplex_id INT UNSIGNED,
    sample_id INT UNSIGNED,
    amplicon_id INT UNSIGNED,
    FOREIGN KEY (subplex_id) REFERENCES subplex_info(subplex_id),
    FOREIGN KEY (sample_id) REFERENCES sample(sample_id),
    FOREIGN KEY (amplicon_id) REFERENCES amplicon(amplicon_id)
) ENGINE = InnoDB;

create table kaspar (
    kaspar_id VARCHAR(10),
    allele_id INT UNSIGNED NOT NULL,
    plate_id INT UNSIGNED,
    well_id CHAR(3),
    PRIMARY KEY `kaspar_kaspar_id_allele_id_crRNA_id` ( `kaspar_id`, `allele_id`, `crRNA_id` ),
    FOREIGN KEY (allele_id) REFERENCES allele(allele_id),
    FOREIGN KEY (crRNA_id) REFERENCES crRNA(crRNA_id),
    FOREIGN KEY (plate_id) REFERENCES plate(plate_id)
) ENGINE = InnoDB;


