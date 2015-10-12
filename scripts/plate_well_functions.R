well_to_row <- function( well_vector ){
	return( as.factor(substr(well_vector, 1, 1)) )
}

well_to_column <- function( well_vector ){
	columns <- substr(well_vector, 2, 3)
	columns <- as.integer( sub("^0", "", columns, perl=TRUE ) )
	return( columns )
}

add_row_indices_for_tile_plot <- function(data_frame) {
	# check object is a data.frame and check that it has a row column
	if( class(data_frame) != "data.frame" ){
		stop("Supplied object is not a data frame")
	}
	if( sum( grepl("row", colnames(data_frame) ) ) == 0 ){
		stop("There is no column labelled 'row'.")
	}
	
	row_names <- LETTERS[1:16]
	row_i <- c( seq(-1,-16) )
	row_indices <- vector(length=nrow(data_frame))
	for( letter in row_names ){
		row_indices[ data_frame$row == letter ] <- row_i[row_names == letter]
	}
	data_frame$row_indices <- as.integer(row_indices)
	return( data_frame )
}


plate_tile_plot <- function( data_frame, summary_results, palette = "Reds", plate_type = '96' ){
	# check data_frame is a data.frame and check that it has the right columns
	if( class(data_frame) != "data.frame" ){
		stop("Supplied object is not a data frame")
	}
	for( column_name in c("plex", "plate", "group_name", "row_i", "col", "pc_reads", "total_on_target_reads") ){
		if( sum( grepl(column_name, colnames(data_frame) ) ) == 0 ){
			stop( paste("There is no column labelled '", column_name, "'.", sep="") )
		}
	}
	
	# change settings based on plate_type
	if( plate_type == '96' ){
		last_col <- 12
		last_row_i <- 8
		pcs_text_size <- 4
		reads_text_size <- 3
	}else{
		last_col <- 24
		last_row_i <- 16
		pcs_text_size <- 2.5
		reads_text_size <- 2
	}
	
	# set scale_limits
	scale_limits <- c( 0, 100 )
	
	data_frame$row_i <- as.integer(data_frame$row_i)
	data_frame$col <- as.integer(data_frame$col)
	
	# prepare text for plotting. 
	pc_reads_text <- subset(data_frame, select = c(col, row_i, pc_reads ))
	# Needs to be offset from center of square to fit both in
	pc_reads_text$row_i <- pc_reads_text$row_i + 0.25 
	pc_reads_text$pc_reads <- as.character(pc_reads_text$pc_reads)

	# same for total reads text
	total_reads_text <- subset(data_frame, select = c(col, row_i, total_on_target_reads))
	total_reads_text$total_on_target_reads <- as.character(total_reads_text$total_on_target_reads)
	# add brackets
#	total_reads_text$total_on_target_reads <- sub("^", "(", total_reads_text$total_on_target_reads, perl=TRUE)
#	total_reads_text$total_on_target_reads <- sub("$", ")", total_reads_text$total_on_target_reads, perl=TRUE)
	# shift text down to fit into box
	total_reads_text$row_i <- total_reads_text$row_i - 0.25 
	
	# go through wells and add line if it doesn't exist
	for( column in 1:last_col ){
		for( row_num in -1:-(last_row_i) ){
			if( nrow( data_frame[ data_frame$col == column & data_frame$row_i == row_num, ] ) == 0 ){
				new_row <- data.frame( plex=data_frame$plex[1],
										plate=data_frame$plate[1],
										analysis=NA,
										sample_name=NA,
										crispr_name=NA,
										amplicon=NA,
										gene_name=NA,
										group_name=data_frame$group_name[1],
										total_indels=0,
										Deletions=0,
										Insertions=0,
										pc_reads=NA,
										pc_reads_per_indel=NA,
										pc_major_variant=NA,
										total_on_target_reads=NA,
										row=NA,
										col=column,
										row_i=row_num )
				data_frame <- rbind(data_frame, new_row)
			}
		}
	}

	# create title text
	title_text <- paste("Number of indels per embryo (", data_frame$plex[1], " - plate ", data_frame$plate[1],
						", group ", data_frame$group_name[1], ")", sep="" )
	
	# sort out colours
	plot_colours <- character()
	if( missing(palette) ){
		plot_colours <- c( "white", "#cb181d" )
	}else if( palette == "Blues"){
		plot_colours <- c( "white", "#2171b5" )
	}else if( palette == "Reds"){
		plot_colours <- c( "white", "#cb181d" )
	}else{
		plot_colours <- c( "white", "#cb181d" )
	}
	
#	# make legend
#	legend_table <- subset( summary_results, summary_results$group == data_frame$group_name[1], select=c(group, sub_plex, gene_name ) )
	
	row_labels <- LETTERS[1:last_row_i]
	row_breaks <- c(seq(-1, -last_row_i))
	col_breaks <- c(seq(1, last_col))
	# make plot
	plate_plot <- ggplot(data_frame, aes(x=col,y=row_i)) + geom_tile(aes(fill=pc_reads)) + 
			scale_fill_continuous(low = plot_colours[1], high = plot_colours[2], space = "Lab", 
				na.value = "grey90", guide = "colourbar", limits = scale_limits) + 
			geom_text(data=pc_reads_text, aes(label=pc_reads), size = pcs_text_size ) + 
			geom_text(data=total_reads_text, aes(label=total_on_target_reads), size = reads_text_size ) + 
#			annotation_custom(tableGrob(legend_table), xmin=13, xmax=15, ymin=-6, ymax=-8) +
			scale_y_continuous(breaks=row_breaks, labels=row_labels ) + 
			scale_x_continuous(breaks=col_breaks) + 
			labs(y="Rows", x="Columns", title=title_text)
	
	return( plate_plot )
}

