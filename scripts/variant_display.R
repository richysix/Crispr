#!/usr/bin/env Rscript

# load packages
library(ggplot2)
library(optparse)

# define options
option_list <- list(
  make_option(c("-d", "--directory"), type="character", default='cwd',
              help="Working directory [default %default]" ),
  make_option("--file_type", type="character", default='pdf',
              help = "Type of files to generate - pdf | png [default %default]"),
  make_option("--display_type", type="character", default='top_30',
              help = "Type of figures to generate - top_30 | no_pc [default %default]"),
  make_option("--basename", type="character", default='variants',
              help="A base name for all output files [default %default]"),
  make_option("--variant_percentage", type="numeric", default=0.01,
              help="Only displaying variants above this percentage [default %default]"),
  make_option(c("-v", "--verbose"), action="store_true", default=TRUE,
              help="Print extra output [default]"),
  make_option(c("-q", "--quietly"), action="store_false",
              dest="verbose", help="Print little output")
)

# parse command line for options and arguments
cmd_line_args <- parse_args(
	OptionParser(
		option_list=option_list, prog = 'variant_display.R',
		usage = "Usage: %prog [options] input_file" ),
		positional_arguments = 1
)

# default is for working directory to be pwd
if( cmd_line_args$options[['directory']] == 'cwd' ){
	cmd_line_args$options[['directory']] <- getwd()
}
# set working directory
setwd( cmd_line_args$options[['directory']] )

# verbose output if set
if( cmd_line_args$options[['verbose']] ){
	cat( "Working directory:", cmd_line_args$options[['directory']], "\n", sep=" " )
	cat( "File Type:", cmd_line_args$options[['file_type']], "\n", sep=" " )
	cat( "Display Type:", cmd_line_args$options[['display_type']], "\n", sep=" " )
	cat( "Output files basename:", cmd_line_args$options[['basename']], "\n", sep=" " )
}

# open data file
input_file <- cmd_line_args$args[1]

data_types <- c("plex"="factor", "plate"="factor", "subplex"="factor", "well"="factor",
               "sample_name"="factor", "gene_name"="factor", "group_name"="factor", 
               "amplicon"="factor", "caller"="factor", "type"="factor",
               "crispr_name"="factor", 
               "chr"="character", "variant_position"="integer", 
               "reference_allele"="character", "alternate_allele"="character",
               "num_reads_with_indel"="integer", "total_reads"="integer",
               "percentage_reads_with_indel"="numeric", "consensus_start"="integer", 
               "ref_seq"="character", "consensus_alt_seq"="character")

# read in header line to check column names
header <- read.table(file=input_file, sep="\t", comment.char="%", header=FALSE, nrows=1 )
header <- as.character( unlist(header[1,]) )
header[1] <- sub( "^#", "", header[1])

# check required columns
for( cols in c( "sample_name", "gene_name", "amplicon", "caller", "crispr_name",
				"chr", "variant_position", "reference_allele", "alternate_allele",
				"percentage_reads_with_indel", "consensus_start", 
               "ref_seq", "consensus_alt_seq" ) ){
  if( sum( header == cols ) == 0 ){
    stop( "One of the required columns isn't present.\n", 
          "Required columns are:\n",
          paste(cols, sep=" ") )
  }
}

# get classes for those columns that are present
column_classes <- data_types[ header ]
all_indels <- read.table(file=input_file, sep="\t", comment.char="%", 
                         header=TRUE, colClasses=column_classes )
names(all_indels)[1] <- sub("^X\\.", "", names(all_indels)[1])

# remove lines with caller as NA
all_indels <- all_indels[ !is.na( all_indels$caller ), ]

# subset data to remove PINDEL calls. No consensus.
all_indels <- subset( all_indels, caller != "PINDEL" )
all_indels$ref_length <- nchar(all_indels$reference_allele)
all_indels$alt_length <- nchar(all_indels$alternate_allele)
all_indels$ref_cons_length <- nchar(all_indels$ref_seq)
all_indels$alt_cons_length <- nchar(all_indels$consensus_alt_seq)

indel_type = character(length=nrow(all_indels))
indel_type[ all_indels$ref_length > 1 & all_indels$alt_length > 1 ] <- "complex"
indel_type[ all_indels$ref_length == 1 & all_indels$alt_length > 1 ] <- "insertion"
indel_type[ all_indels$ref_length > 1 & all_indels$alt_length == 1 ] <- "deletion"

all_indels$indel_type <- factor(indel_type, levels=c("deletion", "insertion", "complex") )

# function to make crispr line info
crispr_line_info <- function( var_data, line_info_list ){
  var_data <- droplevels(var_data)
  crispr_data <- vector()
  cut_sites <- vector()
  for( crispr in levels(var_data$crispr_name)){
    crispr_info <- unlist( strsplit(crispr, ":") )
    positions <- as.integer( unlist( strsplit(crispr_info[3], "-") ) )
    if( crispr_info[4] == '1' ){
      crispr_data <- c( crispr_data,
                        positions[1], 0.5,
                        positions[2], 0.5,
                        positions[2], 0.5,
                        positions[2] - 6, 0.7
      )
      cut_sites <- c(cut_sites, positions[2] - 5.5)
    }else{
      crispr_data <- c( crispr_data,
                        positions[1], -0.5,
                        positions[2], -0.5,
                        positions[1], -0.5,
                        positions[1] + 5, -0.7
      )
      cut_sites <- c(cut_sites, positions[1] + 5.5)
    }
  }
  cut_sites_data <- data.frame(cut_sites = cut_sites)
  crispr_lines <- as.data.frame( t(matrix( crispr_data, nrow=4 ) ) )
  names(crispr_lines) <- c("x_starts", "y_starts", "x_ends", "y_ends")
  line_info_list[["crispr_lines"]] <- crispr_lines
  line_info_list[["cut_sites_data"]] <- cut_sites_data
  return( line_info_list )
}

# function to make sequence dataframe
create_seq_data_frame <- function( var_data, line_info_list ){
  # find minimum starting position
  start <- min(var_data$consensus_start)
  # get_sequence for first line that starts at start
  ref_seq <- var_data$ref_seq[ var_data$consensus_start == start ][1]
  
  base_sequence <- data.frame(
    xpos = seq(start,start+nchar(ref_seq)-1),
    ypos = rep(0,nchar(ref_seq)),
    ref_sequence = strsplit(ref_seq,'')
  )
  names(base_sequence) <- c("xpos","ypos","ref_sequence")
  line_info_list[["start"]] = start
  line_info_list[["base_sequence"]] = base_sequence
  return( line_info_list )
}


# function to calculate line points
create_indel_line_info <- function( var_data, line_info_list ){
  line_data = vector()
  insertion_lines <- vector()
  rows <- vector()
  percentages <- character()
  sample_names <- character()
  # calculate min starting position
  start <- min(var_data$consensus_start, na.rm=TRUE)
  
  # remove duplicate rows in the same samples (crispr pair deletions)
  var_data <- var_data[ !duplicated(var_data[, c("sample_name", "chr", "variant_position", "reference_allele", "alternate_allele") ]), ]
  
  # remove alleles below the threshold percentage
  var_data <- subset(var_data, percentage_reads_with_indel >= cmd_line_args$options[['variant_percentage']] )
  
  # sort var_data by percentage
  var_data <- var_data[ order(-var_data$percentage_reads_with_indel), ]
  # if there are too many variants and the display type is top_30
  if( nrow(var_data) > 30 & cmd_line_args$options[['display_type']] == "top_30" ){
    # keep top 30 variants
    var_data <- var_data[ 1:30, ]
  }
  del_row_num <- 1
  ins_row_num <- -1
  for( row_num in seq(1,nrow(var_data) ) ){
    row <- var_data[ row_num, ]
    percentages <- c(percentages, sprintf('%.2f%%', row$percentage_reads_with_indel*100) )
	sample_names <- c(sample_names, as.character(row$well))
    if( row$indel_type == "deletion" ){
      line_data <- c(line_data, 
                     start, del_row_num,
                     row$variant_position, del_row_num,
                     row$variant_position + row$ref_length, del_row_num,
                     row$consensus_start + row$ref_length + row$alt_cons_length-1, del_row_num
      )
      rows <- c(rows, del_row_num)
      del_row_num <- del_row_num + 1
    } else if( row$indel_type == "insertion" ){
      ins_step <- row$alt_length/2
      line_data <- c(line_data,
                     start, ins_row_num,
                     row$variant_position + 0.3, ins_row_num,
                     row$variant_position + 0.7, ins_row_num,
                     row$consensus_start + row$ref_cons_length-1, ins_row_num,
                     row$variant_position + 0.5, ins_row_num,
                     row$variant_position + 0.5 - ins_step, ins_row_num - 0.5,
                     row$variant_position + 0.5, ins_row_num,
                     row$variant_position + 0.5 + ins_step, ins_row_num - 0.5
      )
      insertion_lines <- c( insertion_lines,
                            row$variant_position + 0.5 - ins_step, ins_row_num - 0.5,
                            row$variant_position + 0.5 + ins_step, ins_row_num - 0.5
      )
      rows <- c(rows, ins_row_num)
      ins_row_num <- ins_row_num - 1
    } else{
      ins_step <- row$alt_length/2
      line_data <- c(line_data, 
                     start, ins_row_num,
                     row$variant_position, ins_row_num,
                     row$variant_position + row$ref_length, ins_row_num,
                     row$consensus_start + row$ref_length + row$alt_cons_length-1, ins_row_num,
                     row$variant_position + 0.5, ins_row_num,
                     row$variant_position + 0.5 - ins_step, ins_row_num - 0.5,
                     row$variant_position + 0.5, ins_row_num,
                     row$variant_position + 0.5 + ins_step, ins_row_num - 0.5                   
      )
      insertion_lines <- c( insertion_lines,
                            row$variant_position + 0.5 - ins_step, ins_row_num - 0.5,
                            row$variant_position + 0.5 + ins_step, ins_row_num - 0.5
      )
      rows <- c(rows, ins_row_num)
      ins_row_num <- ins_row_num - 1
    }
  }
  
  del_lines <- as.data.frame( t(matrix( line_data, nrow=4 ) ) )
  names(del_lines) <- c("x_starts", "y_starts", "x_ends", "y_ends")
  
  ins_lines <- as.data.frame( t(matrix( insertion_lines, nrow=4 ) ) )
  names(ins_lines) <- c("x_starts", "y_starts", "x_ends", "y_ends")
  
  max_x = max(c(del_lines$x_ends, ins_lines$x_ends), na.rm=TRUE)
  percentage_labels <- data.frame(xpos=rep(max_x+10,length(rows)), ypos=rows, pc=percentages )
  
  sample_name_labels <- data.frame(xpos=rep(max_x+25,length(rows)), ypos=rows, names=sample_names )
  
  if( nrow(var_data) > 30 & cmd_line_args$options[['display_type']] == "no_pc" ){
    line_info_list[["percentage_labels"]] <- NULL
    line_info_list[["sample_name_labels"]] <- NULL
  }else{
    line_info_list[["percentage_labels"]] <- percentage_labels
    line_info_list[["sample_name_labels"]] <- sample_name_labels
  }
  line_info_list[["del_lines"]] <- del_lines
  line_info_list[["ins_lines"]] <- ins_lines
  return(line_info_list)
}

# function to calculate line info. 
# expects data frame for just one amplicon
calculate_line_info <- function( var_data ){
  var_data <- droplevels(var_data)
  line_info_list <- list()
  line_info_list[["var_data"]] <- var_data
  line_info_list <- crispr_line_info( var_data, line_info_list )
  line_info_list <- create_seq_data_frame( var_data, line_info_list )
  line_info_list <- create_indel_line_info( var_data, line_info_list )
  return( line_info_list )
}

# apply calculate_line_info to each amplicon
# returns a list of lists
line_info_list <- by(all_indels, all_indels$amplicon, calculate_line_info )
# remove empty elements of the list
lines_list = list()
j <- 1
for( i in 1:length(line_info_list) ){
	if( !is.null( line_info_list[[i]] ) ){
		lines_list[[j]] <- line_info_list[[i]]
		j <- j + 1
	}
}

# function to produce a crispr indel plot
create_crispr_indel_plot <- function( line_info_list ){
  # set up some variables
  var_data <- line_info_list[["var_data"]]
  gene_name <- var_data$gene_name[1]
  amplicon <- var_data$amplicon[1]
  chr <- var_data$chr[1]
  
  crispr_indel_plot <- ggplot() + 
    geom_text(data = line_info_list$base_sequence, 
              aes( x = xpos, y = ypos, label = ref_sequence), 
              size=1,) +
    geom_segment(data=line_info_list$del_lines, 
                 aes(x = x_starts, y = y_starts, xend = x_ends, yend = y_ends )) +
    geom_vline(data=line_info_list$cut_sites_data, 
               aes(xintercept = cut_sites), 
               colour="steelblue1", linetype = "longdash") + 
    geom_segment(data=line_info_list$crispr_lines, 
                 aes(x = x_starts, y = y_starts, xend = x_ends, yend = y_ends), 
                 colour = "steelblue1")
  if( !is.null(line_info_list$percentage_labels ) ){
    crispr_indel_plot <- crispr_indel_plot + 
      geom_text(data = line_info_list$percentage_labels, 
              aes( x = xpos, y = ypos, label = pc ), 
              size=3)
  }
  if( !is.null(line_info_list$sample_name_labels ) ){
    crispr_indel_plot <- crispr_indel_plot + 
      geom_text(data = line_info_list$sample_name_labels, 
              aes( x = xpos, y = ypos, label = names ), 
              size=3, hjust = 0 )
  }
  if( nrow( line_info_list$ins_lines ) > 0 ){
    crispr_indel_plot <- crispr_indel_plot + geom_segment(data=line_info_list$ins_lines, 
                   aes(x = x_starts, y = y_starts, xend = x_ends, yend = y_ends), 
                   colour = "red")
  }
  crispr_indel_plot <- crispr_indel_plot + labs( 
    title = paste("Distribution of indels for", gene_name, sep=" ",
                  paste("(", amplicon, ")", sep="")),
    x = paste("Genomic Position ( Chr", chr, ")", sep="" ),
    y = ""
    ) + 
    theme( axis.text.y = element_blank(), axis.ticks.y = element_blank() )
  
  return( crispr_indel_plot )
}

# lapply to create a list of indel plots
crispr_plot_list <- lapply(lines_list, create_crispr_indel_plot )

# print plots to file
cat("Printing plots...\n")
if( cmd_line_args$options[['file_type']] == 'pdf' ){
  file_name <- paste(cmd_line_args$options[['basename']], paste('display', cmd_line_args$options[['display_type']], sep="-"), 'pdf', sep='.')
  pdf(file=file_name,onefile=TRUE,width=9,height=6,paper="special") 
  print(crispr_plot_list)
  dev.off()
}else if( cmd_line_args$options[['file_type']] == 'png' ){
  for( i in 1:length(crispr_plot_list) ){
    amplicon <- lines_list[[i]][["var_data"]]$amplicon[1]
    file_name <- paste( paste(cmd_line_args$options[['basename']], amplicon, sep='_' ), paste('display', cmd_line_args$options[['display_type']], sep="-"), 'png', sep='.' )
    png(filename=file_name, width=720, height=480 )
    print(crispr_plot_list[[i]])
    dev.off()
  }
}

