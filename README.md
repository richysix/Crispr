# Crispr

CRISPR/Cas9 guide RNA Design

## Summary

This is a set of Perl modules and scripts for designing CRISPR/Cas9 guide RNAs
in batch.

## Modules

Contains the following modules:

*   Crispr.pm       - object used to find and score CRISPR target sites

*   Target.pm       - object representing a target stretch of DNA

*   crRNA.pm        - object representing a CRISPR target site

*   EnzymeInfo.pm   - object that holds information about restriction enzymes found in amplicons for screening guide RNAs

*   OffTarget.pm    - object for potential off target sites for CRISPR target sites

*   CrisprPair.pm   - object representing two CRISPR target sites designed together as a pair

*   PrimerDesign.pm - object used to design PCR primers for efficiency screening

*   Config.pm       - helper module to parse configurations files

## Scripts

#### find_and_score_crispr_sites.pl

    Takes a list of targets, finds all possible CRISPR target sites and scores them for their potential off-target sites. Can also score sites for position within coding sequence.

    Inputs that are accepted are:
    Ensembl Gene IDs (including RNA Seq gene)
    Ensembl Transcript IDs (including RNA Seq transcripts)
    Ensembl Exon IDs
    Genomic Regions (CHR:START-END)

#### crispr_pairs_for_deletions.pl

    Designs pairs of CRISPR target sites to be used together to produce specific deletions.

    Inputs that are accepted are:
    Ensembl Gene IDs (including RNA Seq gene)
    Ensembl Transcript IDs (including RNA Seq transcripts)
    Ensembl Exon IDs
    Genomic Regions (CHR:START-END)

#### design_pcr_primers_for_illumina_screening.pl

    Design PCR primers to amplify regions around CRISPR target sites. Designed as nested primer pairs with internal primers that have Next Generation sequencing adaptor sequences added to enable a sequencing library to be produced. Takes CRISPR target site IDs as produced by the design scripts.

For more information use the --help or --man options for each individual script.

### Required Modules
*   [Moose](http://search.cpan.org/~ether/Moose-2.1210/lib/Moose.pm)
*   [BioPerl](www.bioperl.org/) and [Ensembl API](http://www.ensembl.org/info/docs/api/index.html)
*   [Number::Format](http://search.cpan.org/~wrw/Number-Format-1.73/Format.pm)
*   [Set::Interval](http://search.cpan.org/~benbooth/Set-IntervalTree-0.01/lib/Set/IntervalTree.pm)
*   [PCR](http://github.com/richysix/PCR)
*   [Tree](http://github.com/richysix/Tree)

## Copyright

This software is Copyright (c) 2014 by Genome Research Ltd.

This is free software, licensed under:

  The GNU General Public License, Version 3, June 2007
