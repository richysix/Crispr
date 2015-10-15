CREATE TABLE target (
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
    designed DATE
) ENGINE = InnoDB;
CREATE UNIQUE INDEX `target_target_name_requestor` ON target ( `target_name`, `requestor` );

CREATE TABLE plate (
    plate_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    plate_name CHAR(10) UNIQUE,
    plate_type ENUM('96', '384') NOT NULL,
    plate_category ENUM('crispr', 'cloning_oligos', 'expression_construct', 't7_hairpin_oligos', 't7_fill-in_oligos', 'guideRNA_prep', 'pcr_primers', 'kaspar_assays' ) NOT NULL,
    ordered DATE,
    received DATE
) ENGINE = InnoDB;
CREATE UNIQUE INDEX `plate_plate_name` ON plate (`plate_name` );

CREATE TABLE crRNA (
    crRNA_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    crRNA_name VARCHAR(50),
    chr VARCHAR(30),
    start INT UNSIGNED NOT NULL,
    end INT UNSIGNED NOT NULL,
    strand ENUM( '1', '-1' ) NOT NULL,
    sequence VARCHAR(23) NOT NULL,
    num_five_prime_Gs TINYINT NOT NULL,
    score DECIMAL(4,3),
    off_target_score DECIMAL(4,3),
    coding_score DECIMAL(4,3),
    target_id INT UNSIGNED NOT NULL,
    plate_id INT UNSIGNED,
    well_id CHAR(3),
    CONSTRAINT `crRNA_plate_id_well_id` UNIQUE (`plate_id`, `well_id`),
    FOREIGN KEY (target_id) REFERENCES target (target_id),
    FOREIGN KEY (plate_id) REFERENCES plate (plate_id)
)  ENGINE = InnoDB;
CREATE UNIQUE INDEX `crRNA_crRNA_name_target_id_plate_id` ON crRNA ( `crRNA_name`, `target_id`, `plate_id` );

CREATE TABLE crRNA_pair (
    crRNA_pair_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    crRNA_1_id INT UNSIGNED NOT NULL,
    crRNA_2_id INT UNSIGNED NOT NULL,
    CONSTRAINT `crRNA_pair_crRNA_pair_id_crRNA_1_id_crRNA_2_id` UNIQUE ( `crRNA_pair_id`, `crRNA_1_id`, `crRNA_2_id` ),
    FOREIGN KEY (crRNA_1_id) REFERENCES crRNA (crRNA_id),
    FOREIGN KEY (crRNA_2_id) REFERENCES crRNA (crRNA_id)
)  ENGINE = InnoDB;

CREATE TABLE coding_scores (
    crRNA_id INT UNSIGNED NOT NULL,
    transcript_id VARCHAR(20) NOT NULL,
    score DECIMAL(4,3) NOT NULL,
    CONSTRAINT `coding_scores_crRNA_id_transcript_id` PRIMARY KEY (`crRNA_id`,`transcript_id`),
    FOREIGN KEY (crRNA_id) REFERENCES crRNA(crRNA_id)
) ENGINE = InnoDB;

CREATE TABLE off_target_info (
    crRNA_id INT UNSIGNED NOT NULL,
    off_target_hit VARCHAR(120) NOT NULL,
    mismatches TINYINT UNSIGNED NOT NULL,
    annotation ENUM('exon', 'intron', 'nongenic') NOT NULL,
    CONSTRAINT `off_target_info_crRNA_id_off_target_hit` PRIMARY KEY (`crRNA_id`,`off_target_hit`),
    FOREIGN KEY (crRNA_id) REFERENCES crRNA(crRNA_id)
) ENGINE = InnoDB;

CREATE TABLE plasmid_backbone (
    plasmid_backbone_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    plasmid_backbone VARCHAR(50) NOT NULL
) ENGINE = InnoDB;

CREATE TABLE construction_oligos (
    crRNA_id INT UNSIGNED NOT NULL,
    forward_oligo VARCHAR(200) NOT NULL,
    reverse_oligo VARCHAR(30),
    plasmid_backbone_id INT UNSIGNED,
    plate_id INT UNSIGNED,
    well_id CHAR(3),
    CONSTRAINT `construction_oligos_crRNA_id_plate_id_well_id` PRIMARY KEY ( `crRNA_id`, `plate_id`, `well_id` ),
    FOREIGN KEY (crRNA_id) REFERENCES crRNA(crRNA_id),
    FOREIGN KEY (plate_id) REFERENCES plate(plate_id)
) ENGINE = InnoDB;

CREATE TABLE expression_construct (
    crRNA_id INT UNSIGNED NOT NULL,
    plate_id INT UNSIGNED,
    well_id CHAR(3),
    trace_file VARCHAR(50),
    seq_verified DATE,
    plasmid_backbone_id INT UNSIGNED NOT NULL,
    CONSTRAINT `expression_construct_crRNA_id_plate_id_well_id` PRIMARY KEY ( `crRNA_id`, `plate_id`, `well_id` ),
    FOREIGN KEY (crRNA_id) REFERENCES crRNA(crRNA_id),
    FOREIGN KEY (plasmid_backbone_id) REFERENCES plasmid_backbone(plasmid_backbone_id),
    FOREIGN KEY (plate_id) REFERENCES plate(plate_id)
) ENGINE = InnoDB;

CREATE TABLE guideRNA_prep (
    guideRNA_prep_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    crRNA_id INT UNSIGNED NOT NULL,
    guideRNA_type ENUM('sgRNA', 'tracrRNA') NOT NULL,
    concentration DECIMAL(5,1) NOT NULL,
    made_by VARCHAR(5) NOT NULL,
    date DATE NOT NULL,
    plate_id INT UNSIGNED,
    well_id CHAR(3),
    CONSTRAINT `guideRNA_prep_crRNA_id_plate_id_well_id` UNIQUE ( `crRNA_id`, `plate_id`, `well_id` ),
    FOREIGN KEY (crRNA_id) REFERENCES crRNA(crRNA_id),
    FOREIGN KEY (plate_id) REFERENCES plate(plate_id)
) ENGINE = InnoDB;

CREATE TABLE primer (
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
CREATE INDEX `primer_plate_id_well_id` ON primer ( `plate_id`, `well_id` );

CREATE TABLE primer_pair (
    primer_pair_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    type ENUM('ext','int','ext-illumina', 'int-illumina', 'int-illumina_tailed') NOT NULL,
    left_primer_id INT UNSIGNED NOT NULL,
    right_primer_id INT UNSIGNED NOT NULL,
    chr VARCHAR(30),
    start INT UNSIGNED NOT NULL,
    end INT UNSIGNED NOT NULL,
    strand ENUM('1', '-1') NOT NULL,
    product_size SMALLINT NOT NULL,
    FOREIGN KEY (left_primer_id) REFERENCES primer(primer_id),
    FOREIGN KEY (right_primer_id) REFERENCES primer(primer_id)
) ENGINE = InnoDB;

CREATE TABLE amplicon_to_crRNA (
    primer_pair_id INT UNSIGNED NOT NULL,
    crRNA_id INT UNSIGNED NOT NULL,
    CONSTRAINT `amplicon_to_crRNA_primer_pair_id_crRNA_id` PRIMARY KEY ( `primer_pair_id`, `crRNA_id` ),
    FOREIGN KEY (primer_pair_id) REFERENCES primer_pair(primer_pair_id),
    FOREIGN KEY (crRNA_id) REFERENCES crRNA(crRNA_id)
) ENGINE = InnoDB;

CREATE TABLE enzyme (
    enzyme_id SMALLINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(20) NOT NULL,
    site VARCHAR(20) NOT NULL,
    CONSTRAINT `enzyme_name` UNIQUE ( `name` )
) ENGINE = InnoDB;

CREATE TABLE enzyme_ordering (
    order_no VARCHAR(20) PRIMARY KEY,
    enzyme_id SMALLINT UNSIGNED NOT NULL,
    company VARCHAR(20) NOT NULL,
    notes VARCHAR(50),
    last_order DATE,
    FOREIGN KEY (enzyme_id) REFERENCES enzyme(enzyme_id)
) ENGINE = InnoDB;

CREATE TABLE restriction_enzymes (
    primer_pair_id INT UNSIGNED NOT NULL,
    crRNA_id INT UNSIGNED NOT NULL,
    enzyme_id SMALLINT UNSIGNED NOT NULL,
    proximity_to_crRNA_cut_site TINYINT NOT NULL,
    cleavage_products VARCHAR(20),
    CONSTRAINT `restriction_enzymes_primer_pair_id_crRNA_id_enzyme_id` PRIMARY KEY ( `primer_pair_id`, `crRNA_id`, `enzyme_id` ),
    FOREIGN KEY (primer_pair_id) REFERENCES primer_pair(primer_pair_id),
    FOREIGN KEY (crRNA_id) REFERENCES crRNA(crRNA_id),
    FOREIGN KEY (enzyme_id) REFERENCES enzyme(enzyme_id)
) ENGINE = InnoDB;

CREATE TABLE cas9 (
    cas9_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    type VARCHAR(100) NOT NULL,
    vector VARCHAR(100) NOT NULL,
    species VARCHAR(100) NOT NULL,
    CONSTRAINT `cas9_name` UNIQUE ( `name` ),
    CONSTRAINT `cas9_type_vector` UNIQUE ( `type`, `vector` )
) ENGINE = InnoDB;

CREATE TABLE cas9_prep (
    cas9_prep_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    cas9_id INT UNSIGNED NOT NULL,
    prep_type ENUM('dna', 'rna', 'protein') NOT NULL,
    made_by VARCHAR(10) NOT NULL,
    date DATE NOT NULL,
    notes VARCHAR(200),
    CONSTRAINT `cas9_cas9_id_prep_type_made_by_date` UNIQUE ( `cas9_id`, `prep_type`, `made_by`, `date` ),
    FOREIGN KEY (cas9_id) REFERENCES cas9(cas9_id)
) ENGINE = InnoDB;

CREATE TABLE injection (
    injection_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    injection_name VARCHAR(30) NOT NULL,
    cas9_prep_id INT UNSIGNED NOT NULL,
    cas9_concentration DECIMAL(5,1) NOT NULL,
    date DATE NOT NULL,
    line_injected VARCHAR(10) NOT NULL,
    line_raised VARCHAR(10),
    sorted_by VARCHAR(40),
    CONSTRAINT `injection_injection_name` UNIQUE ( `injection_name` ),
    FOREIGN KEY (cas9_prep_id) REFERENCES cas9_prep(cas9_prep_id)
) ENGINE = InnoDB;

CREATE TABLE injection_pool (
    injection_id INT UNSIGNED NOT NULL,
    crRNA_id INT UNSIGNED NOT NULL,
    guideRNA_prep_id INT UNSIGNED NOT NULL,
    guideRNA_concentration INT UNSIGNED NOT NULL,
    CONSTRAINT `injection_pool_injection_id_guideRNA_prep_id` PRIMARY KEY ( `injection_id`, `guideRNA_prep_id` ),
    FOREIGN KEY (injection_id) REFERENCES injection(injection_id),
    FOREIGN KEY (crRNA_id) REFERENCES crRNA(crRNA_id),
    FOREIGN KEY (guideRNA_prep_id) REFERENCES guideRNA_prep(guideRNA_prep_id)
) ENGINE = InnoDB;

CREATE TABLE plex (
    plex_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    plex_name VARCHAR(10) NOT NULL,
    run_id INT UNSIGNED NOT NULL,
    analysis_started DATE,
    analysis_finished DATE,
    CONSTRAINT `plex_plex_name` UNIQUE ( `plex_name` )
) ENGINE = InnoDB;

CREATE TABLE sample (
    sample_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    sample_name VARCHAR(20) NOT NULL,
    sample_number INT UNSIGNED NOT NULL,
    injection_id INT UNSIGNED NOT NULL,
    generation ENUM('G0', 'F1', 'F2') NOT NULL,
    type ENUM('sperm', 'embryo', 'finclip', 'earclip', 'blastocyst' ) NOT NULL,
    species VARCHAR(50) NOT NULL,
    well_id CHAR(3),
    cryo_box VARCHAR(30),
    FOREIGN KEY (injection_id) REFERENCES injection(injection_id)
) ENGINE = InnoDB;
CREATE UNIQUE INDEX `sample_name` ON sample (`sample_name`);
CREATE UNIQUE INDEX `box_n_well` ON sample (`cryo_box`, `well_id`);

CREATE TABLE analysis (
    analysis_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    plex_id INT UNSIGNED NOT NULL,
    analysis_started DATE,
    analysis_finished DATE,
    FOREIGN KEY (plex_id) REFERENCES plex(plex_id)
) ENGINE = InnoDB;

CREATE TABLE analysis_information (
    analysis_id INT UNSIGNED NOT NULL,
    sample_id INT UNSIGNED NOT NULL,
    primer_pair_id INT UNSIGNED NOT NULL,
    barcode_id SMALLINT NOT NULL,
    plate_number TINYINT NOT NULL,
    well_id CHAR(3) NOT NULL,
    CONSTRAINT `analysis_analysis_id_sample_id_primer_pair_id` UNIQUE ( `analysis_id`, `sample_id`, `primer_pair_id` ),
    FOREIGN KEY (analysis_id) REFERENCES analysis(analysis_id),
    FOREIGN KEY (sample_id) REFERENCES sample(sample_id),
    FOREIGN KEY (primer_pair_id) REFERENCES primer_pair(primer_pair_id)
) ENGINE = InnoDB;
CREATE INDEX `analysis_analysis_id` ON analysis (`analysis_id`);

CREATE TABLE sequencing_results (
    sample_id INT UNSIGNED NOT NULL,
    crRNA_id INT UNSIGNED NOT NULL,
    fail BOOLEAN NOT NULL,
    num_indels INT UNSIGNED,
    total_percentage_of_reads DECIMAL(4,1),
    percentage_major_variant DECIMAL(4,1),
    total_reads INT UNSIGNED NOT NULL,
    CONSTRAINT `sequencing_results_sample_id_crRNA_id` PRIMARY KEY ( `sample_id`, `crRNA_id` ),
    FOREIGN KEY (sample_id) REFERENCES sample(sample_id),
    FOREIGN KEY (crRNA_id) REFERENCES crRNA(crRNA_id)
) ENGINE = InnoDB;

CREATE TABLE allele (
    allele_id INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    chr VARCHAR(30) NOT NULL,
    pos INT UNSIGNED NOT NULL,
    ref_allele VARCHAR(200) NOT NULL,
    alt_allele VARCHAR(200) NOT NULL,
    ref_seq VARCHAR(200),
    alt_seq VARCHAR(200),
    primer_pair_id INT UNSIGNED NOT NULL,
    type ENUM("crispr", "crispr_pair" ),
    FOREIGN KEY (primer_pair_id) REFERENCES primer_pair(primer_pair_id)
) ENGINE = InnoDB;

CREATE TABLE allele_to_crispr (
    allele_id INT UNSIGNED NOT NULL,
    crRNA_id INT UNSIGNED NOT NULL,
    FOREIGN KEY (allele_id) REFERENCES allele(allele_id),
    FOREIGN KEY (crRNA_id) REFERENCES crRNA(crRNA_id)
) ENGINE = InnoDB;

CREATE TABLE sample_allele (
    sample_id INT UNSIGNED NOT NULL,
    allele_id INT UNSIGNED NOT NULL,
    percentage_of_reads DECIMAL(4,1) NOT NULL,
    CONSTRAINT `sample_allele_sample_id_allele_id` PRIMARY KEY ( `sample_id`, `allele_id` ),
    FOREIGN KEY (sample_id) REFERENCES sample(sample_id),
    FOREIGN KEY (allele_id) REFERENCES allele(allele_id)
) ENGINE = InnoDB;

CREATE TABLE kasp (
    kasp_id VARCHAR(10) PRIMARY KEY,
    allele_id INT UNSIGNED NOT NULL,
    allele_number VARCHAR(10) NOT NULL,
    allele_specific_primer_1 VARCHAR(50) NOT NULL,
    allele_specific_primer_2 VARCHAR(50) NOT NULL,
    common_primer_1 VARCHAR(50) NOT NULL,
    common_primer_2 VARCHAR(50),
    plate_id INT UNSIGNED,
    well_id CHAR(3),
    CONSTRAINT `kasp_kasp_id_allele_id` UNIQUE ( `kasp_id`, `allele_id` ),
    FOREIGN KEY (allele_id) REFERENCES allele(allele_id),
    FOREIGN KEY (plate_id) REFERENCES plate(plate_id)
) ENGINE = InnoDB;


