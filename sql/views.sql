

/** crRNA joined to amplicons **/
CREATE OR REPLACE VIEW crispr2primer_pair AS
    SELECT pl1.plate_name as crRNA_plate_name, cr.well_id as crRNA_well_id, crRNA_name, cr.sequence,
    pl2.plate_name as primer_plate_name, p.well_id as primer_well_id, 
    concat_ws(":", pp.chr, concat_ws("_", pp.start, pp.end ), pp.strand ) as primer_name,
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
