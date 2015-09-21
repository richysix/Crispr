# Crispr

CRISPR/Cas9 guide RNA Design and Analysis

## Summary

This is a set of Perl modules and scripts for CRISPR/Cas9 design and analysis.

Features:
* designing guide RNAs in batch.
* designing screening PCR primers (for amplicon sequencing or T7 endonuclease/restriction digest)
* analysing amplicon sequencing for indels
* MySQL/SQLite database to hold the information

## Installation

###Download and install prerequisites

These modules rely on other Perl modules which must be installed for the scripts to work.  
BioPerl v1.6.9 - [Instructions for installing](http://www.bioperl.org/wiki/Installing_BioPerl)  
Ensembl API - [Instructions for installing](http://www.ensembl.org/info/docs/api/api_installation.html)

Other required modules can be installed from [CPAN](http://www.cpan.org/modules/INSTALL.html)  
See below for a way to install any required modules automatically.  
Otherwise, they can be installed manually. See **Required Modules** below for a list of modules.  

The Crispr modules also use a few other modules not on CPAN.
These can be installed from github.
The modules are:  
####[PCR](http://github.com/richysix/PCR)  
    cd ~/src  
    wget https://github.com/richysix/PCR/releases/download/v0.2.2/PCR-0.2.2.tar.gz  
    tar -xvzf PCR-0.2.2.tar.gz  
    cd PCR-0.2.2  
    perl Makefile.PL  
    make  
    make test  
    make install
    
####[Labware](http://github.com/richysix/Labware)  
    cd ~/src  
    wget https://github.com/richysix/Labware/releases/download/v0.0.4/Labware-0.0.4.tar.gz  
    tar -xvzf Labware-0.0.4.tar.gz  
    cd Labware-0.0.4  
    perl Makefile.PL  
    make  
    make test  
    make install  

####[Tree](http://github.com/richysix/Tree)  
    cd ~/src  
    wget https://github.com/richysix/Tree/releases/download/v0.1.2/Tree-0.1.2.tar.gz  
    tar -xvzf Tree-0.1.2.tar.gz  
    cd Tree-0.1.2  
    # install dependencies. This uses cpanm to install any modules that are required for the package in question
    cpanm --installdeps .
    
    perl Makefile.PL  
    make  
    make test  
    make install  

###Install the Crispr modules

    Download the latest release from github  
    cd ~/src  
    wget https://github.com/richysix/Crispr/releases/download/v0.1.10/Crispr-0.1.10.tar.gz  
    tar -xvzf Crispr-0.1.10.tar.gz  
    cd Crispr-0.1.10  
    # install dependencies  
    cpanm --installdeps .  
    
    perl Makefile.PL  
    make  
    make test  
    make install  
    
In each case, the `perl Makefile.PL` step will tell you if any of the required modules are not installed.  


### Required Modules
*   [Moose](https://metacpan.org/release/Moose)
*   [BioPerl](www.bioperl.org/)
*   [Ensembl API](http://www.ensembl.org/info/docs/api/index.html)
*   [Bio-SamTools](https://metacpan.org/release/Bio-SamTools)
*   [Clone](https://metacpan.org/pod/Clone)
*   [DBIx::Connector](https://metacpan.org/pod/DBIx::Connector)
*   [DateTime](https://metacpan.org/pod/DateTime)
*   [File::Find::Rule](https://metacpan.org/pod/File::Find::Rule)
*   [File::Which](https://metacpan.org/pod/File::Which)
*   [Hash::Merge](https://metacpan.org/pod/Hash::Merge)
*   [List::MoreUtils](https://metacpan.org/pod/List::MoreUtils)
*   [Number::Format](https://metacpan.org/pod/Number::Format)
*   [YAML::Tiny](https://metacpan.org/pod/YAML::Tiny)
*   [Set::IntervalTree](https://metacpan.org/pod/Set::IntervalTree)
*   [Labware](http://github.com/richysix/Labware)
*   [PCR](http://github.com/richysix/PCR)
*   [Tree](http://github.com/richysix/Tree)

### Other requirements
In addition to the Perl modules some of the scripts use programs which need to be installed.

1. [bwa](http://bio-bwa.sourceforge.net/) is used in off-target checking to map CRISPR target sites back to the genome.
2. [primer3](http://primer3.sourceforge.net/) is used for primer design
3. [dindel](https://sites.google.com/site/keesalbers/soft/dindel) is used for indel calling
4. [samtools](http://samtools.sourceforge.net/) is used in the indel calling for indexing and accessing bam files

The scripts will try and find them in the current path.

---

## Tutorial

The assumed workflow is

1. select CRISPR target sites for a list of targets
    * find_and_score_crispr_sites.pl
    * crispr_pairs_for_deletions.pl

2. design PCR primers for screening CRISPR cutting efficiency
    * design_pcr_primers_for_illumina_screening.pl

3. Analyse MiSeq sequencing of amplicons
    * count_indel_reads_from_bam.pl

The steps are independent of each other and do not have to all be run.  
At each step there are also scripts to add the information to an SQL database.

### CRISPR guide RNA design

The CRISPR design scripts scan target regions for valid CRISPR target sites and
score off-target potential by mapping the CRISPR target sequence back to the
target genome allowing mismatches (up to 4 at the moment).
The default CRISPR target sequence to search for is N{21}GG, but this can altered
As the scripts use the Ensembl database, a target region can be an Ensembl gene, transcript or exon id
or the coordinates of a genomic region. At the moment, there isn't support for
searching arbitrary fasta files.
The input must be tab-separated  
Columns are: TARGETS    [REQUESTOR]   [GENE_ID]  

TARGETS: Acceptable targets are Ensembl exon ids, gene ids, transcript ids or
genomic positions/regions. RNA Seq gene/transcript ids are also accepted.
All four types can be present in one file.

REQUESTOR: This is optional. We use it for tracking purposes.
The option --requestor can be used to set a requestor name for all targets and
then the input file doesn't need them.
It is required if you are using the SQL database to store guide RNAs as the targets
are indexed by target name and requestor.
Each target can have a different requestor if supplied in the input rather than by the --requestor option.

GENE_ID: Optionally an Ensembl gene id can be supplied for genomic regions.

This input can also be supplied on STDIN rather than a file.

An example command is shown below

    # make a targets file
    echo -e "ENSDARE00001194351
    ENSDART00000158694
    ENSDARG00000101846
    5:2443741-2444279:1" > targets_file.txt
    
    # run design script
    perl \
    find_and_score_crispr_sites.pl
    --target_genome /path/to/genome/file.fa \
    --annotation_file /path/to/annotation/file.gff \
    --target_sequence GGNNNNNNNNNNNNNNNNNNNGG \
    --species zebrafish > crRNAs-scored.txt



## Scripts

For more information use the --help or --man options for each individual script.

#### find_and_score_crispr_sites.pl

    Takes a list of targets, finds all possible CRISPR target sites 
    and scores them for their potential off-target sites. 
    Can also score sites for position within coding sequence.

    Inputs that are accepted are:
    Ensembl Gene IDs (including RNA Seq gene)
    Ensembl Transcript IDs (including RNA Seq transcripts)
    Ensembl Exon IDs
    Genomic Regions (CHR:START-END)

#### crispr_pairs_for_deletions.pl

    Designs pairs of CRISPR target sites to be used together 
    to produce specific deletions.

    Inputs that are accepted are:
    Ensembl Gene IDs (including RNA Seq gene)
    Ensembl Transcript IDs (including RNA Seq transcripts)
    Ensembl Exon IDs
    Genomic Regions (CHR:START-END)

#### design_pcr_primers_for_illumina_screening.pl

    Design PCR primers to amplify regions around CRISPR target sites.
    Designed as nested primer pairs with internal primers that have 
    Next Generation sequencing adaptor sequences added to enable a sequencing 
    library to be produced. Takes CRISPR target site IDs as produced by the
    design scripts.

#### count_indel_reads_from_bam.pl

    Analyse MiSeq amplicon data for CRISPR-induced indels.
    Requires a YAML configuration file:
        specifies bam files and sample names
    Takes mapped bam files and outputs indels with an estimate of the fraction of reads containing the indel.

#### score_crisprs_from_id.pl

    Accessory script to score crispr target sites from a crispr name 
    crRNA:CHR:START-END:STRAND

### Database Scripts

Scripts for storing to and retrieving information from an SQL database. Supports both MySQL and SQLite. 

* add_targets_to_db_from_file.pl
* add_crRNAs_to_db_from_file.pl
* add_crispr_pairs_to_db_from_file.pl
* add_primer_pair_plus_enzyme_info_for_crRNAs_to_db_from_file.pl
* add_guide_RNA_preps_to_db_from_file.pl
* add_cas9_preps_to_db.pl
* add_injection_info_to_db_from_file.pl
* add_samples_to_db_from_sample_manifest.pl
* add_analysis_information_to_db_from_file.pl
* get_pcr_primers_from_db.pl
* create_YAML_file_from_db.pl


## Modules

Contains the following modules:

*   Crispr.pm                   - object used to find and score CRISPR target sites

*   Target.pm                   - object representing a target stretch of DNA

*   crRNA.pm                    - object representing a CRISPR target site

*   EnzymeInfo.pm               - object that holds information about restriction enzymes found in amplicons for screening guide RNAs

*   OffTargetInfo.pm            - object for potential off-target sites for CRISPR target sites

*   OffTarget.pm                - object representing a single off-target site

*   CrisprPair.pm               - object representing two CRISPR target sites designed together as a pair

*   PrimerDesign.pm             - object used to design PCR primers for efficiency screening

*   Primer.pm                   - object representing a PCR primer

*   PrimerPair.pm               - object representing a pair of PCR primers

*   Cas9.pm                     - object representing a particular type of Cas9

*   Allele.pm                   - object representing a CRISPR induced allele

*   Config.pm                   - helper module to parse configuration files

*   SharedMethods.pm            - helper module for commonly used function

### Database Modules

*   Cas9Prep.pm                 - object representing a particular preparation of Cas9 (protein or RNA)

*   GuideRNAPrep.pm             - object representing a particular preparation of a Cas9 synthetic guide RNA

*   InjectionPool.pm            - object representing guide RNAs injected/tranfected into samples

*   Sample.pm                   - object representing a single Sample

*   SampleAmplicon.pm           - object representing the pairing of a Sample with and Amplicon for analysis

*   Plex.pm                     - object representing a multiplexed sequencing run

*   Analysis.pm                 - object representing a set of samples to be analysed together

*   Kasp.pm                     - object representing a Kasp genotyping assay

#### Database Adaptors

These objects are connection adaptors to the database for storing and retrieving
information about those objects.

*   DBConnection.pm             - object for connecting to the database

*   BaseAdaptor.pm              - base adaptor object from which the other adaptors inherit

*   TargetAdaptor.pm            - For storing/retrieving Target objects

*   crRNAAdaptor.pm             - For storing/retrieving crRNA objects

*   CrisprPairAdaptor.pm        - For storing/retrieving CrisprPair objects

*   PlateAdaptor.pm             - For storing/retrieving Plate objects

*   PrimerAdaptor.pm            - For storing/retrieving Primer objects

*   PrimerPairAdaptor.pm        - For storing/retrieving PrimerPair objects

*   Cas9Adaptor.pm              - For storing/retrieving Cas9 objects

*   Cas9PrepAdaptor.pm          - For storing/retrieving Cas9Prep objects

*   GuideRNAPrepAdaptor.pm      - For storing/retrieving GuideRNAPrep objects

*   InjectionPoolAdaptor.pm     - For storing/retrieving InjectionPool objects

*   SampleAdaptor.pm            - For storing/retrieving Sample objects

*   PlexAdaptor.pm              - For storing/retrieving Plex objects

*   AnalysisAdaptor.pm          - For storing/retrieving Analysis objects

*   SampleAmpliconAdaptor.pm    - For storing/retrieving SampleAmplicon objects


## Copyright

This software is Copyright (c) 2014,2015 by Genome Research Ltd.

This is free software, licensed under:

  The GNU General Public License, Version 3, June 2007
