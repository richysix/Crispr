# Crispr

CRISPR/Cas9 guide RNA Design and Analysis

## Summary

This is a set of Perl modules and scripts for using CRISPR/Cas9.

Features:
* designing guide RNAs in batch.
* designing screening PCR primers (T7 endonuclease/restriction digest and MiSeq)
* analysing MiSeq amplicon sequencing for indels
* MySQL/SQLite database to hold the information

The assumed workflow is

1. select CRISPR target sites for a list of targets
    * find_and_score_crispr_sites.pl
    * crispr_pairs_for_deletions.pl

2. design PCR primers for screening CRISPR cutting efficiency
    * design_pcr_primers_for_illumina_screening.pl

3. Analyse MiSeq sequencing of amplicons
    * count_indel_reads_from_bam.pl

At each step there are scripts to add the information to an SQL database.

### Required Modules
*   [Moose](http://search.cpan.org/~ether/Moose-2.1210/lib/Moose.pm)
*   [BioPerl](www.bioperl.org/) and [Ensembl API](http://www.ensembl.org/info/docs/api/index.html)
*   [Number::Format](http://search.cpan.org/~wrw/Number-Format-1.73/Format.pm)
*   [Set::Interval](http://search.cpan.org/~benbooth/Set-IntervalTree-0.01/lib/Set/IntervalTree.pm)
*   [PCR](http://github.com/richysix/PCR)
*   [Tree](http://github.com/richysix/Tree)

---


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
