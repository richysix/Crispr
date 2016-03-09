CREATE TABLE status (
   status_id integer PRIMARY KEY,
   status VARCHAR(50)
);

CREATE TABLE target (
    target_id integer PRIMARY KEY,
    target_name VARCHAR(45) NOT NULL,
    assembly VARCHAR(20),
    chr VARCHAR(30),
    start integer  NOT NULL,
    end integer  NOT NULL,
    strand  NOT NULL,
    species VARCHAR(50),
    requires_enzyme  NOT NULL,
    gene_id VARCHAR (30),
    gene_name VARCHAR (50),
    requestor VARCHAR(50) NOT NULL,
    ensembl_version  integer UNSIGNED,
    status_id integer NOT NULL,
    status_changed DATE,
    FOREIGN KEY (status_id) REFERENCES status (status_id)
);
CREATE UNIQUE INDEX `target_target_name_requestor` ON target ( `target_name`, `requestor` );

CREATE TABLE plate (
    plate_id integer   PRIMARY KEY,
    plate_name CHAR(10) UNIQUE,
    plate_type  NOT NULL,
    plate_category  NOT NULL,
    ordered DATE,
    received DATE
);
CREATE UNIQUE INDEX `plate_plate_name` ON plate (`plate_name` );

CREATE TABLE crRNA (
    crRNA_id integer   PRIMARY KEY,
    crRNA_name VARCHAR(50),
    chr VARCHAR(30),
    start integer  NOT NULL,
    end integer  NOT NULL,
    strand  NOT NULL,
    sequence VARCHAR(23) NOT NULL,
    num_five_prime_Gs  integer NOT NULL,
    score DECIMAL(4,3),
    off_target_score DECIMAL(4,3),
    coding_score DECIMAL(4,3),
    target_id integer  NOT NULL,
    plate_id integer UNSIGNED,
    well_id CHAR(3),
    status_id integer NOT NULL,
    status_changed DATE,
    CONSTRAINT `crRNA_plate_id_well_id` UNIQUE (`plate_id`, `well_id`),
    FOREIGN KEY (target_id) REFERENCES target (target_id),
    FOREIGN KEY (plate_id) REFERENCES plate (plate_id),
    FOREIGN KEY (status_id) REFERENCES status (status_id)
);
CREATE UNIQUE INDEX `crRNA_crRNA_name_target_id_plate_id` ON crRNA ( `crRNA_name`, `target_id`, `plate_id` );

CREATE TABLE crRNA_pair (
    crRNA_pair_id integer   PRIMARY KEY,
    crRNA_1_id integer  NOT NULL,
    crRNA_2_id integer  NOT NULL,
    CONSTRAINT `crRNA_pair_crRNA_pair_id_crRNA_1_id_crRNA_2_id` UNIQUE ( `crRNA_pair_id`, `crRNA_1_id`, `crRNA_2_id` ),
    FOREIGN KEY (crRNA_1_id) REFERENCES crRNA (crRNA_id),
    FOREIGN KEY (crRNA_2_id) REFERENCES crRNA (crRNA_id)
);

CREATE TABLE coding_scores (
    crRNA_id integer  NOT NULL,
    transcript_id VARCHAR(20) NOT NULL,
    score DECIMAL(4,3) NOT NULL,
    CONSTRAINT `coding_scores_crRNA_id_transcript_id` PRIMARY KEY (`crRNA_id`,`transcript_id`),
    FOREIGN KEY (crRNA_id) REFERENCES crRNA(crRNA_id)
);

CREATE TABLE off_target_info (
    crRNA_id integer  NOT NULL,
    off_target_hit VARCHAR(120) NOT NULL,
    mismatches  integer  NOT NULL,
    annotation  NOT NULL,
    CONSTRAINT `off_target_info_crRNA_id_off_target_hit` PRIMARY KEY (`crRNA_id`,`off_target_hit`),
    FOREIGN KEY (crRNA_id) REFERENCES crRNA(crRNA_id)
);

CREATE TABLE plasmid_backbone (
    plasmid_backbone_id integer   PRIMARY KEY,
    plasmid_backbone VARCHAR(50) NOT NULL
);

CREATE TABLE construction_oligos (
    crRNA_id integer  NOT NULL,
    forward_oligo VARCHAR(200) NOT NULL,
    reverse_oligo VARCHAR(30),
    plasmid_backbone_id integer UNSIGNED,
    plate_id integer UNSIGNED,
    well_id CHAR(3),
    CONSTRAINT `construction_oligos_crRNA_id_plate_id_well_id` PRIMARY KEY ( `crRNA_id`, `plate_id`, `well_id` ),
    FOREIGN KEY (crRNA_id) REFERENCES crRNA(crRNA_id),
    FOREIGN KEY (plate_id) REFERENCES plate(plate_id)
);

CREATE TABLE expression_construct (
    crRNA_id integer  NOT NULL,
    plate_id integer UNSIGNED,
    well_id CHAR(3),
    trace_file VARCHAR(50),
    seq_verified DATE,
    plasmid_backbone_id integer  NOT NULL,
    CONSTRAINT `expression_construct_crRNA_id_plate_id_well_id` PRIMARY KEY ( `crRNA_id`, `plate_id`, `well_id` ),
    FOREIGN KEY (crRNA_id) REFERENCES crRNA(crRNA_id),
    FOREIGN KEY (plasmid_backbone_id) REFERENCES plasmid_backbone(plasmid_backbone_id),
    FOREIGN KEY (plate_id) REFERENCES plate(plate_id)
);

CREATE TABLE guideRNA_prep (
    guideRNA_prep_id integer   PRIMARY KEY,
    crRNA_id integer  NOT NULL,
    guideRNA_type  NOT NULL,
    concentration DECIMAL(5,1) NOT NULL,
    made_by VARCHAR(5) NOT NULL,
    date DATE NOT NULL,
    plate_id integer UNSIGNED,
    well_id CHAR(3),
    CONSTRAINT `guideRNA_prep_crRNA_id_plate_id_well_id` UNIQUE ( `crRNA_id`, `plate_id`, `well_id` ),
    FOREIGN KEY (crRNA_id) REFERENCES crRNA(crRNA_id),
    FOREIGN KEY (plate_id) REFERENCES plate(plate_id)
);

CREATE TABLE primer (
    primer_id integer   PRIMARY KEY,
    primer_sequence VARCHAR(50) NOT NULL,
    primer_chr VARCHAR(30),
    primer_start integer  NOT NULL,
    primer_end integer  NOT NULL,
    primer_strand  NOT NULL,
    primer_tail ,
    plate_id integer UNSIGNED,
    well_id CHAR(3),
    FOREIGN KEY (plate_id) REFERENCES plate(plate_id)
);
CREATE INDEX `primer_plate_id_well_id` ON primer ( `plate_id`, `well_id` );

CREATE TABLE primer_pair (
    primer_pair_id integer   PRIMARY KEY,
    type  NOT NULL,
    left_primer_id integer  NOT NULL,
    right_primer_id integer  NOT NULL,
    chr VARCHAR(30),
    start integer  NOT NULL,
    end integer  NOT NULL,
    strand  NOT NULL,
    product_size  integer NOT NULL,
    FOREIGN KEY (left_primer_id) REFERENCES primer(primer_id),
    FOREIGN KEY (right_primer_id) REFERENCES primer(primer_id)
);

CREATE TABLE amplicon_to_crRNA (
    primer_pair_id integer  NOT NULL,
    crRNA_id integer  NOT NULL,
    CONSTRAINT `amplicon_to_crRNA_primer_pair_id_crRNA_id` PRIMARY KEY ( `primer_pair_id`, `crRNA_id` ),
    FOREIGN KEY (primer_pair_id) REFERENCES primer_pair(primer_pair_id),
    FOREIGN KEY (crRNA_id) REFERENCES crRNA(crRNA_id)
);

CREATE TABLE enzyme (
    enzyme_id  integer   PRIMARY KEY,
    name VARCHAR(20) NOT NULL,
    site VARCHAR(20) NOT NULL,
    CONSTRAINT `enzyme_name` UNIQUE ( `name` )
);

CREATE TABLE enzyme_ordering (
    order_no VARCHAR(20) PRIMARY KEY,
    enzyme_id  integer  NOT NULL,
    company VARCHAR(20) NOT NULL,
    notes VARCHAR(50),
    last_order DATE,
    FOREIGN KEY (enzyme_id) REFERENCES enzyme(enzyme_id)
);

CREATE TABLE restriction_enzymes (
    primer_pair_id integer  NOT NULL,
    crRNA_id integer  NOT NULL,
    enzyme_id  integer  NOT NULL,
    proximity_to_crRNA_cut_site  integer NOT NULL,
    cleavage_products VARCHAR(20),
    CONSTRAINT `restriction_enzymes_primer_pair_id_crRNA_id_enzyme_id` PRIMARY KEY ( `primer_pair_id`, `crRNA_id`, `enzyme_id` ),
    FOREIGN KEY (primer_pair_id) REFERENCES primer_pair(primer_pair_id),
    FOREIGN KEY (crRNA_id) REFERENCES crRNA(crRNA_id),
    FOREIGN KEY (enzyme_id) REFERENCES enzyme(enzyme_id)
);

CREATE TABLE cas9 (
    cas9_id integer   PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    type VARCHAR(100) NOT NULL,
    vector VARCHAR(100) NOT NULL,
    species VARCHAR(100) NOT NULL,
    CONSTRAINT `cas9_name` UNIQUE ( `name` ),
    CONSTRAINT `cas9_type_vector` UNIQUE ( `type`, `vector` )
);

CREATE TABLE cas9_prep (
    cas9_prep_id integer   PRIMARY KEY,
    cas9_id integer  NOT NULL,
    prep_type  NOT NULL,
    made_by VARCHAR(10) NOT NULL,
    date DATE NOT NULL,
    notes VARCHAR(200),
    CONSTRAINT `cas9_cas9_id_prep_type_made_by_date` UNIQUE ( `cas9_id`, `prep_type`, `made_by`, `date` ),
    FOREIGN KEY (cas9_id) REFERENCES cas9(cas9_id)
);

CREATE TABLE injection (
    injection_id integer   PRIMARY KEY,
    injection_name VARCHAR(30) NOT NULL,
    cas9_prep_id integer  NOT NULL,
    cas9_concentration DECIMAL(5,1) NOT NULL,
    date DATE NOT NULL,
    line_injected VARCHAR(10) NOT NULL,
    line_raised VARCHAR(10),
    sorted_by VARCHAR(40),
    CONSTRAINT `injection_injection_name` UNIQUE ( `injection_name` ),
    FOREIGN KEY (cas9_prep_id) REFERENCES cas9_prep(cas9_prep_id)
);

CREATE TABLE injection_pool (
    injection_id integer  NOT NULL,
    crRNA_id integer  NOT NULL,
    guideRNA_prep_id integer  NOT NULL,
    guideRNA_concentration integer  NOT NULL,
    CONSTRAINT `injection_pool_injection_id_guideRNA_prep_id` PRIMARY KEY ( `injection_id`, `guideRNA_prep_id` ),
    FOREIGN KEY (injection_id) REFERENCES injection(injection_id),
    FOREIGN KEY (crRNA_id) REFERENCES crRNA(crRNA_id),
    FOREIGN KEY (guideRNA_prep_id) REFERENCES guideRNA_prep(guideRNA_prep_id)
);

CREATE TABLE plex (
    plex_id integer   PRIMARY KEY,
    plex_name VARCHAR(10) NOT NULL,
    run_id integer  NOT NULL,
    analysis_started DATE,
    analysis_finished DATE,
    CONSTRAINT `plex_plex_name` UNIQUE ( `plex_name` )
);

CREATE TABLE sample (
    sample_id integer   PRIMARY KEY,
    sample_name VARCHAR(20) NOT NULL,
    sample_number integer  NOT NULL,
    injection_id integer  NOT NULL,
    generation  NOT NULL,
    type  NOT NULL,
    species VARCHAR(50) NOT NULL,
    well_id CHAR(3),
    cryo_box VARCHAR(30),
    FOREIGN KEY (injection_id) REFERENCES injection(injection_id)
);
CREATE UNIQUE INDEX `sample_name` ON sample (`sample_name`);
CREATE UNIQUE INDEX `box_n_well` ON sample (`cryo_box`, `well_id`);

CREATE TABLE analysis (
    analysis_id integer   PRIMARY KEY,
    plex_id integer  NOT NULL,
    analysis_started DATE,
    analysis_finished DATE,
    FOREIGN KEY (plex_id) REFERENCES plex(plex_id)
);

CREATE TABLE analysis_information (
    analysis_id integer  NOT NULL,
    sample_id integer  NOT NULL,
    primer_pair_id integer  NOT NULL,
    barcode_id  integer NOT NULL,
    plate_number  integer NOT NULL,
    well_id CHAR(3) NOT NULL,
    CONSTRAINT `analysis_analysis_id_sample_id_primer_pair_id` UNIQUE ( `analysis_id`, `sample_id`, `primer_pair_id` ),
    FOREIGN KEY (analysis_id) REFERENCES analysis(analysis_id),
    FOREIGN KEY (sample_id) REFERENCES sample(sample_id),
    FOREIGN KEY (primer_pair_id) REFERENCES primer_pair(primer_pair_id)
);
CREATE INDEX `analysis_analysis_id` ON analysis (`analysis_id`);

CREATE TABLE sequencing_results (
    sample_id integer  NOT NULL,
    crRNA_id integer  NOT NULL,
    pass BOOLEAN NOT NULL,
    num_indels integer UNSIGNED,
    total_percentage_of_reads DECIMAL(4,1),
    percentage_major_variant DECIMAL(4,1),
    total_reads integer  NOT NULL,
    CONSTRAINT `sequencing_results_sample_id_crRNA_id` PRIMARY KEY ( `sample_id`, `crRNA_id` ),
    FOREIGN KEY (sample_id) REFERENCES sample(sample_id),
    FOREIGN KEY (crRNA_id) REFERENCES crRNA(crRNA_id)
);

CREATE TABLE allele (
    allele_id integer PRIMARY KEY,
    allele_number integer,
    chr VARCHAR(30) NOT NULL,
    pos integer  NOT NULL,
    ref_allele VARCHAR(200) NOT NULL,
    alt_allele VARCHAR(200) NOT NULL,
    CONSTRAINT `allele_chr_pos_ref_alt` UNIQUE (`chr`, `pos`, `ref_allele`, `alt_allele`)
);

CREATE TABLE allele_to_crispr (
    allele_id integer  NOT NULL,
    crRNA_id integer  NOT NULL,
    FOREIGN KEY (allele_id) REFERENCES allele(allele_id),
    FOREIGN KEY (crRNA_id) REFERENCES crRNA(crRNA_id)
);

CREATE TABLE sample_allele (
    sample_id integer  NOT NULL,
    allele_id integer  NOT NULL,
    percentage_of_reads DECIMAL(4,1) NOT NULL,
    CONSTRAINT `sample_allele_sample_id_allele_id` PRIMARY KEY ( `sample_id`, `allele_id` ),
    FOREIGN KEY (sample_id) REFERENCES sample(sample_id),
    FOREIGN KEY (allele_id) REFERENCES allele(allele_id)
);

CREATE TABLE kasp (
    kasp_id VARCHAR(10) PRIMARY KEY,
    allele_id integer NOT NULL,
    allele_specific_primer_1 VARCHAR(50) NOT NULL,
    allele_specific_primer_2 VARCHAR(50) NOT NULL,
    common_primer_1 VARCHAR(50) NOT NULL,
    common_primer_2 VARCHAR(50),
    plate_id integer UNSIGNED,
    well_id CHAR(3),
    CONSTRAINT `kasp_kasp_id_allele_id` UNIQUE ( `kasp_id`, `allele_id` ),
    FOREIGN KEY (allele_id) REFERENCES allele(allele_id),
    FOREIGN KEY (plate_id) REFERENCES plate(plate_id)
);
