#!/usr/bin/env Rscript

# load packages
library(ggplot2)
library(plyr)
library(scales)
library(optparse)

option_list <- list(
  make_option(c("-d", "--directory"), type = "character", default = "cwd",
              help = "Working directory [default %default]"),
  make_option("--figure_type", type = "character", default = "pdf",
              help = paste("Type of figures to generate -",
                           "pdf | png | eps [default %default]")),
  make_option("--scripts_directory", type = "character",
              default = "~/checkouts/Crispr/scripts",
              help = paste("directory where plate_well_functions",
                           "is located [default %default]")),
  make_option("--basename", type = "character", default = "mpx",
              help = "A base name for all output files [default %default]"),
  make_option("--plate_type", type = "character", default = "96",
              help = "Type of plate to plot - 96 | 384 [default %default]"),
  make_option(c("-v", "--verbose"), action = "store_true", default = TRUE,
              help = "Print extra output [default]"),
  make_option(c("-q", "--quietly"), action = "store_false",
              dest = "verbose", help = "Print little output")
)

cmd_line_args <- parse_args(
  OptionParser(
    option_list = option_list, prog = "crispr_results_tile_plots.R",
    usage = "Usage: %prog [options] input_file"
  ),
  positional_arguments = 1
)

if (cmd_line_args$options[["directory"]] == "cwd") {
  cmd_line_args$options[["directory"]] <- getwd()
}
if (cmd_line_args$options[["verbose"]]) {
  cat("Working directory:", cmd_line_args$options[["directory"]], "\n",
      sep = " ")
  cat("Figure Type:", cmd_line_args$options[["figure_type"]], "\n", sep = " ")
  cat("Scripts directory:", cmd_line_args$options[["scripts_directory"]], "\n",
      sep = " ")
  cat("Output files basename:", cmd_line_args$options[["basename"]], "\n",
      sep = " ")
  cat("Plate Type:", cmd_line_args$options[["plate_type"]], "\n", sep = " ")
}
# check figure type option
accepted_output_types <- c("pdf", "png", "eps")
if (sum(accepted_output_types == cmd_line_args$options[["figure_type"]]) == 0) {
  accepted_type_string <- paste(accepted_output_types, collapse = ", ")
  error_msg <- paste("Option --figure_type is not an accepted type\n",
                     "It must be one of ", accepted_type_string, "\n")
  stop(error_msg)
}

plate_well_file <- file.path(cmd_line_args$options[["scripts_directory"]],
                             "plate_well_functions.R")
if (!file.exists(plate_well_file)) {
  # try current working directory
  plate_well_file <- file.path(getwd(), "plate_well_functions.R")
  cat(plate_well_file, "\n")
  if (!file.exists(plate_well_file)) {
    stop("Couldn't find plate well functions file\n", plate_well_file)
  }
}

# source plate well functions
source(plate_well_file)

# set working directory
setwd(cmd_line_args$options[["directory"]])

# open data file
input_file <- cmd_line_args$args[1]

#col_names <- c("plex", "plate", "analysis", "well", "sample_name", "gene_name",
# "group_name", "amplicon", "caller", "type", "crispr_name", "chr",
# "variant_position", "reference_allele", "alternate_allele",
# "num_reads_with_indel", "total_on_target_reads",
# "percentage_reads_with_indel", "consensus_start", "ref_seq",
# "consensus_alt_seq")
data_types <- c(
  "factor", "factor", "factor", "factor", "factor", "factor", "factor",
  "factor", "factor", "factor", "factor", "character", "integer", "character",
  "character", "integer", "integer", "numeric", "integer", "character",
  "character"
)

all_indels <- read.table(file = input_file, sep = "\t",
                         comment.char = "%", header = TRUE,
                         colClasses = data_types)
level_ordering <- order(as.integer(levels(all_indels$group_name)))
all_indels$group_name <-
  factor(all_indels$group_name,
         levels = levels(all_indels$group_name)[level_ordering])
names(all_indels)[1] <- sub("^X\\.", "", names(all_indels)[1])

# remove non-overlapping
indels <- subset(all_indels, (is.na(all_indels$type) |
                                all_indels$type == "crispr" |
                                all_indels$type == "crispr_pair"))

# add well info
indels$row <- well_to_row(indels$well)
indels$column <- well_to_column(indels$well)
indels <- add_row_indices_for_tile_plot(indels)

# summaries
results_by_sample_by_crispr <-
  ddply(
    indels, .(plex, plate, analysis, sample_name, crispr_name), summarise,
    amplicon = amplicon[1],
    gene_name = gene_name[1],
    group_name = group_name[1],
    total_indels = sum(!is.na(type)),
    Deletions = sum(nchar(reference_allele) > nchar(alternate_allele)),
    Insertions = sum(nchar(reference_allele) < nchar(alternate_allele)),
    pc_reads = round(sum(percentage_reads_with_indel, na.rm = TRUE) * 100,
                     digits = 1),
    pc_reads_per_indel = round(sum(percentage_reads_with_indel, na.rm = TRUE) /
                                 (length(num_reads_with_indel) - 1) * 100, 1),
    pc_major_variant = round(max(percentage_reads_with_indel,
                                 na.rm = TRUE) * 100, digits = 1),
    total_on_target_reads = total_on_target_reads[1],
    row = row[1], col = column[1], row_i = row_indices[1]
  )

results_by_gene_name <-
  ddply(
    results_by_sample_by_crispr,
    .(plex, plate, analysis, crispr_name, gene_name),
    summarise,
    amplicon = amplicon[1],
    gene_name = gene_name[1],
    group_name = group_name[1],
    min_pc = round(min(pc_reads), digits = 1),
    max_pc = round(max(pc_reads), digits = 1),
    mean_pc = round(mean(pc_reads), digits = 1),
    sd_pc = round(sd(pc_reads), digits = 1),
    num_founders_over_5pc = sum(pc_reads > 5),
    max_pc_major_variant = round(max(pc_major_variant), digits = 1)
  )

# sort and output table
sort_order <- order(results_by_sample_by_crispr$plate,
                    -results_by_sample_by_crispr$row_i,
                    results_by_sample_by_crispr$col)
results_sorted <-
  results_by_sample_by_crispr[sort_order, ]
results_sorted_subset <-
  subset(results_sorted,
         select = c("plex", "plate", "analysis", "sample_name", "amplicon",
                    "gene_name", "crispr_name", "total_indels", "pc_reads",
                    "pc_major_variant", "total_on_target_reads"))
table_filename <- paste(cmd_line_args$options[["basename"]], "results.txt",
                        sep = ".")
write.table(results_sorted_subset, file = table_filename, col.names = TRUE,
            row.names = FALSE, quote = FALSE, sep = "\t")

# output summary table
summary_table <-
  subset(results_by_gene_name,
         select = c("analysis", "gene_name", "amplicon", "crispr_name",
                    "min_pc", "max_pc", "mean_pc", "sd_pc",
                    "num_founders_over_5pc", "max_pc_major_variant"))
summary_filename <- paste(cmd_line_args$options[["basename"]], "summary.txt",
                          sep = ".")
write.table(summary_table, file = summary_filename, col.names = TRUE,
            row.names = FALSE, quote = FALSE, sep = "\t")

# coverage
log_labels <- c("10", "100", "1000", "10000", "100000", "1000000")
rows_to_keep <- results_by_sample_by_crispr$total_on_target_reads > 9
data_subset <-
  results_by_sample_by_crispr[rows_to_keep, ]
coverage_plot <- ggplot(data = data_subset) +
  geom_boxplot(aes(y = total_on_target_reads, x = analysis)) +
  scale_y_log10(limits = c(10, 1000000), breaks = as.numeric(log_labels),
                labels = log_labels) +
  labs(x = "Target", y = "Coverage")

# on target stats
# check if file exists
total_reads_file <- paste(cmd_line_args$options[["basename"]],
                          "total_reads.txt", sep = ".")
plot_on_target_plot <- FALSE
if (file.exists(total_reads_file)) {
  total_reads <- read.table(file = total_reads_file, sep = "\t",
                            col.names = c("plex", "sample_name", "total_reads"))

  # merge data frames
  results_by_sample_by_gene_name <-
    merge(results_by_sample_by_gene_name, total_reads)

  # create new ON target % column
  results_by_sample_by_gene_name$pc_on_target <-
    results_by_sample_by_gene_name$total_on_target_reads /
    results_by_sample_by_gene_name$total_reads

  # make boxplot of ON target %
  on_target_boxplot <- ggplot(data = results_by_sample_by_gene_name) +
    geom_boxplot(aes(x = plex, y = pc_on_target)) +
    scale_y_continuous(limits = c(0, 1), labels = percent) +
    labs(x = "Target", y = "Percentage ON Target")

  plot_on_target_plot <- TRUE
}

# plot tile plots
plot_list <- by(
  results_by_sample_by_crispr,
  results_by_sample_by_crispr$group_name,
  plate_tile_plot, summary_results,
  plate_type = cmd_line_args$options[["plate_type"]], simplify = FALSE
)

# print to files
if (cmd_line_args$options[["figure_type"]] == "pdf") {
  file_name <- paste(cmd_line_args$options[["basename"]], ".pdf", sep = "")
  pdf(file = file_name, onefile = TRUE, width = 9, height = 6,
      paper = "special")

  print(coverage_plot)

  if (plot_on_target_plot) {
    print(on_target_boxplot)
  }

  for (plate in seq_along(plot_list)) {
    print(plot_list[[plate]])
  }

  dev.off()
} else if (cmd_line_args$options[["figure_type"]] == "png") {
  file_name <- paste(cmd_line_args$options[["basename"]],
                     "coverage", "png", sep = ".")
  png(filename = file_name, width = 720, height = 480)
  print(coverage_plot)
  dev.off()

  if (plot_on_target_plot) {
    file_name <- paste(cmd_line_args$options[["basename"]],
                       "on_target", "png", sep = ".")
    png(filename = file_name, width = 720, height = 480)
    print(on_target_boxplot)
    dev.off()
  }

  for (plot_number in seq_along(plot_list)) {
    group <- levels(levels(all_indels$group_name))[plot_number]
    file_name <- paste(cmd_line_args$options[["basename"]],
                       paste("group", group, sep = "_"), "png", sep = ".")
    png(filename = file_name, width = 720, height = 480)
    print(plot_list[[group]])
    dev.off()
  }
} else if (cmd_line_args$options[["figure_type"]] == "eps") {
  file_name <- paste(cmd_line_args$options[["basename"]],
                     "coverage", "eps", sep = ".")
  postscript(file = file_name, onefile = FALSE, width = 9, height = 6,
             horizontal = FALSE, paper = "special", colormodel = "cmyk")
  print(coverage_plot)
  dev.off()

  if (plot_on_target_plot) {
    file_name <- paste(cmd_line_args$options[["basename"]],
                       "on_target", "eps", sep = ".")
    postscript(file = file_name, onefile = FALSE, width = 9, height = 6,
               horizontal = FALSE, paper = "special", colormodel = "cmyk")
    print(on_target_boxplot)
    dev.off()
  }

  for (plot_number in seq_along(plot_list)) {
    group <- levels(all_indels$group_name)[plot_number]
    file_name <- paste(cmd_line_args$options[["basename"]],
                       paste("group", group, sep = "_"), "eps", sep = ".")
    postscript(file = file_name, onefile = FALSE, width = 9, height = 6,
               horizontal = FALSE, paper = "special", colormodel = "cmyk")
    print(plot_list[[group]])
    dev.off()
  }
}
