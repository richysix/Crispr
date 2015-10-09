
/** crRNA joined to amplicons **/
CREATE OR REPLACE VIEW crispr2primer_pair AS
    SELECT pl1.plate_name as crRNA_plate_name, cr.well_id as crRNA_well_id, crRNA_name, cr.sequence,
    pl2.plate_name as primer_plate_name, p.well_id as primer_well_id, 
    concat_ws(":", pp.chr, concat_ws("_", pp.start, pp.end ), pp.strand ) as primer_pair_name,
    pp.type, pp.product_size
        FROM crRNA cr INNER JOIN plate pl1
        ON pl1.plate_id = cr.plate_id
        INNER JOIN amplicon_to_crRNA amp
        ON amp.crRNA_id = cr.crRNA_id
        INNER JOIN primer_pair pp
        ON amp.primer_pair_id = pp.primer_pair_id
        INNER JOIN primer p
        ON pp.left_primer_id = p.primer_id
        INNER JOIN plate pl2
        ON pl2.plate_id = p.plate_id
        ORDER BY pl1.plate_name, substr(cr.well_id,2,2), substr(cr.well_id,1,1), type;


/** MiSeq info **/
CREATE OR REPLACE VIEW plex_injection_sample_analysisView AS
    SELECT plex_name, plate_number, info.well_id as sample_well_id,
    a.analysis_id, injection_name, sample_name, barcode_id,
    crRNA_name, pl1.plate_name as crRNA_plate_name, cr.well_id as crRNA_well_id,
    concat_ws(":", pp.chr, concat_ws("_", pp.start, pp.end ), pp.strand ) as primer_pair_name,
    line_injected, line_raised,
    a.analysis_started, a.analysis_finished,
    generation, s.type
        FROM crRNA cr
        INNER JOIN plate pl1
        ON pl1.plate_id = cr.plate_id
        INNER JOIN injection_pool ip
        ON cr.crRNA_id = ip.crRNA_id
        INNER JOIN injection i
        ON ip.injection_id = i.injection_id
        INNER JOIN sample s
        ON s.injection_id = i.injection_id
        INNER JOIN analysis_information info
        ON s.sample_id = info.sample_id
        INNER JOIN analysis a
        ON info.analysis_id = a.analysis_id
        INNER JOIN plex
        ON a.plex_id = plex.plex_id
        INNER JOIN primer_pair pp
        ON info.primer_pair_id = pp.primer_pair_id
        ORDER BY plex_name, plate_number, substr(info.well_id,1,1), substr(info.well_id,2,2);

/** Crisprs by plate with target info **/
CREATE OR REPLACE VIEW crispr_plate_targetView AS
    SELECT concat_ws("_", plate_name, well_id) as location, crRNA_name, target_name,
    gene_id, gene_name, requestor, designed
        FROM crRNA cr
        INNER JOIN plate pl1
        ON pl1.plate_id = cr.plate_id
        INNER JOIN target t
        ON cr.target_id = t.target_id
        ORDER BY location;


