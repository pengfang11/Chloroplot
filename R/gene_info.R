#' Generate gene table from parsed gb file
#'
#' @param gb A list containing parsed GB file information. It is generated by
#' function \code{\link[genbankr]{parseGenBank}}
#' @param genome a DNAstring object. It contains the genome sequence.
#'
#' @return a data frame. It contains information of genes.
#' @importFrom magrittr %>%
#' @import dplyr
#' @export

geneTableParsed <- function(gb, genome){
  feature <- vector(mode = "list", length = length(gb$FEATURES))
  names(feature) <- names(gb$FEATURES)
  for (i in names(feature)){
    feature[[i]] <- as.data.frame(gb$FEATURES[[i]])
  }
  type <- lapply(feature, "[[", "type")
  cols <- c("start", "end", "strand",
            "type", "gene", "pseudo", "product")
  info <- NULL
  for(i in 1:length(feature)){
    tmp <- feature[[i]]
    miscol <- cols[!cols %in% colnames(tmp)]
    df <- data.frame(matrix(rep(NA, length(miscol) * nrow(tmp)),
                            nrow = nrow(tmp), ncol = length(miscol)),
                     stringsAsFactors = FALSE)
    colnames(df) <- miscol
    tmp <- cbind.data.frame(tmp, df)
    tmp <- tmp[, which(colnames(tmp) %in% cols)]
    info <- rbind.data.frame(info, tmp)
  }


  # gene
  info$gene[is.na(info$gene)] <- info$product[is.na(info$gene)]
  info$pseudo[is.na(info$pseudo)] <- FALSE

  info$gene[grepl(".*([0-9\\.]+)S.*", info$gene)] <-
    rrnFixer(info$gene[grepl(".*([0-9\\.]+)S.*", info$gene)])
  info$gene[grepl("^trn.*", info$gene, ignore.case=TRUE)] <-
    trnFixer(info$gene[grepl("^trn.*", info$gene, ignore.case=TRUE)])


  gene_table <- info %>%
    dplyr::filter(type %in% c("gene", "tRNA", "rRNA")) %>%
    dplyr::select(start, end, strand, gene, pseudo) %>%
    stats::na.omit() %>%
    unique() %>%
    dplyr::mutate(chr = rep("chr1", n()))
  # for (i in 1:nrow(gene_table)){
  #   if (gene_table$strand[i] == "-" ){
  #     tmp <- gene_table$start[i]
  #     gene_table$start[i] <- gene_table$end[i]
  #     gene_table$end[i] <- tmp
  #   }
  # }
  # gene_table <- select(gene_table, chr, start, end, gene)

  # remove duplicated tRNA and rRNA
  gene_table <- gene_table[order(gene_table[, "start"], -gene_table[, "end"]), ]
  gene_table <- gene_table[!duplicated(gene_table[, c("start", "strand", "gene")]),]
  gene_table <- gene_table[!duplicated(gene_table[, c("end", "strand", "gene")]),]

  # codon usage
  cds <- info[which(info$type == "CDS"),]
  cds_cu <- codonUsage(cds, genome)
  gene_table <- dplyr::left_join(gene_table, cds_cu, by = c("gene", "strand",
                                                            "start"))

  # gc content per gene
  gene_table <- gc_count_gene(genome, gene_table)
  return(gene_table)
}

#' Generate gene table from GenBankRecord
#'
#' @param gb Formalclass GenBankRecord. It is generated by function
#' \code{\link[genbankr]{readGenBank}}
#' @param genome a DNAstring object. It contains the genome sequence.
#'
#' @return a data frame. It contains information of genes.
#' @importFrom magrittr %>%
#' @import dplyr
#' @export

geneTableRead <- function(gb, genome){
  genes <- as.data.frame(genbankr::genes(gb))

  genes$gene[is.na(genes$gene)] <- genes$gene_id[is.na(genes$gene)]

  if (!"pseudo" %in% colnames(genes)){
    genes$pseudo <- rep(FALSE, nrow(genes))
  }
  features <- as.data.frame(genbankr::otherFeatures(gb))

  features <- features %>%
    dplyr::mutate(pseudo = rep(FALSE, n())) %>%
    dplyr::filter(type %in% c("rRNA", "tRNA")) %>%
    dplyr::filter(!gene %in% genes$gene)

  features$gene[is.na(features$gene)] <- features$product[is.na(features$gene)]

  if (nrow(features) != 0){
    gene_table <- genes %>%
      select(start, end, gene, strand, pseudo) %>%
      rbind.data.frame(select(features, start, end, gene, strand, pseudo)) %>%
      mutate(chr = rep("chr1", n())) %>%
      stats::na.omit() %>%
      select(chr, start, end, gene, strand, pseudo) %>%
      unique()
  } else {
    gene_table <- genes %>%
      select(start, end, gene, strand, pseudo) %>%
      mutate(chr = rep("chr1", n())) %>%
      stats::na.omit() %>%
      select(chr, start, end, gene, strand, pseudo) %>%
      unique()
  }

  gene_table$gene[grepl(".*([0-9\\.]+)S.*", gene_table$gene)] <-
    rrnFixer(gene_table$gene[grepl(".*([0-9\\.]+)S.*", gene_table$gene)])
  gene_table$gene[grepl("^trn.*", gene_table$gene, ignore.case=TRUE)] <-
    trnFixer(gene_table$gene[grepl("^trn.*", gene_table$gene, ignore.case=TRUE)])

  # codon usage
  cds <- as.data.frame(genbankr::cds(gb))
  cds_cu <- codonUsage(cds, genome)
  if (is.null(cds_cu)){
    gene_table$cu_bias <- rep(NA, nrow(gene_table))
  } else {
    gene_table <- dplyr::left_join(gene_table, cds_cu,
                                   by = c("gene", "strand", "start"))
  }

  # gc content per gene
  gene_table <- gc_count_gene(genome, gene_table)
  return(gene_table)
}

rrnFixer <- function(rRNA){
  rRNA <- sub("[a-zA-Z]*([0-9\\.]*)S.*", "\\1", rRNA)
  rRNA <- paste("rrn", rRNA, sep = "")
}


trnFixer <- function(tRNA) {
  #tRNA <- gene_table$gene[grepl("^trn.*", gene_table$gene, ignore.case=TRUE)]
  tRNA <- sub("-", "", tRNA)
  tRNA <- sub("^tRNA", "trn", tRNA)
  aa_table <- rbind(c("Ala", "Arg", "Asn", "Asp", "Cys", "Glu",
                      "Gln", "Gly", "His", "He", "Leu", "Lys",
                      "Met", "Phe", "Pro", "Ser", "Thr", "Trp",
                      "Tyr", "Val"),
                    c("A", "R", "N", "D", "C", "E", "Q", "G", "H",
                      "I", "L", "K", "M", "F", "P", "S", "T", "W",
                      "Y", "V"))

  for (i in 1:ncol(aa_table)){
    tRNA <- sub(aa_table[1, i], aa_table[2, i], tRNA)
  }
  tRNA <- sub("(trnf*[A-Z]).*", "\\1", tRNA)
  #gene_table$gene[grepl("^trn.*", gene_table$gene, ignore.case=TRUE)] <- tRNA
  #return(gene_table)
  return(tRNA)
}

codonUsage <- function(cds, genome){
  # Forward strand
  cds_cu_f <- NULL
  cds_f <- cds[which(cds$strand == "+"),]
  tmp <- cds_f
  if (nrow(tmp) != 0){
    cds_seq_f <- Biostrings::DNAStringSet(genome, start = cds_f$start[1],
                                          end = cds_f$end[1])
    if (nrow(tmp) > 1){
      i <- 2
      repeat{
        if (tmp$gene[i] == tmp$gene[i - 1]) {
          cds_seq_f[[i - 1]] <- c(cds_seq_f[[i - 1]],
                                  Biostrings::subseq(genome,
                                                     start = cds_f$start[i],
                                                     end = cds_f$end[i]))
          t <- tmp[i, ]
          tmp <- tmp[-i, ]
        } else {
          cds_seq_f <- append(cds_seq_f, Biostrings::DNAStringSet(genome,
                                                                  start = cds_f$start[i],
                                                                  end = cds_f$end[i]))
          t <- tmp[i, ]
          i <- i + 1
        }
        if (identical(t, cds_f[nrow(cds_f),])) {
          break()
        } else {
          t <- NULL
        }
      }
    }

    names(cds_seq_f) <- tmp$gene
    cds_cu_f <- coRdon::codonTable(cds_seq_f)
    cds_cu_f <- as.vector(coRdon::MILC(cds_cu_f))
    cds_cu_f <- data.frame(cu_bias = cds_cu_f, gene = tmp$gene,
                           start = tmp$start,
                           strand = rep("+", nrow(tmp)),
                           stringsAsFactors = FALSE)
  }


  # Reverse strand
  cds_cu_r <- NULL
  cds_r <- cds[which(cds$strand == "-"),]
  tmp <- cds_r
  if (nrow(tmp) != 0){
    cds_seq_r <- Biostrings::DNAStringSet(genome, start = cds_r$start[1],
                                          end = cds_r$end[1])
    if (nrow(tmp) > 1){
      i <- 2
      repeat{
        if (tmp$gene[i] == tmp$gene[i - 1]) {
          cds_seq_r[[i - 1]] <- c(cds_seq_r[[i - 1]],
                                  Biostrings::subseq(genome,
                                                     start = cds_r$start[i],
                                                     end = cds_r$end[i]))
          t <- tmp[i, ]
          tmp <- tmp[-i, ]
        } else {
          cds_seq_r <- append(cds_seq_r, Biostrings::DNAStringSet(genome,
                                                                  start = cds_r$start[i],
                                                                  end = cds_r$end[i]))
          t <- tmp[i, ]
          i <- i + 1
        }
        if (identical(t, cds_r[nrow(cds_r),])) {
          break()
        } else {
          t <- NULL
        }
      }
    }
    names(cds_seq_r) <- tmp$gene
    cds_seq_r <- Biostrings::reverseComplement(cds_seq_r)
    cds_cu_r <- coRdon::codonTable(cds_seq_r)
    cds_cu_r <- as.vector(coRdon::MILC(cds_cu_r))
    cds_cu_r <- data.frame(cu_bias = cds_cu_r, gene = tmp$gene,
                           start = tmp$start,
                           strand = rep("-", nrow(tmp)),
                           stringsAsFactors = FALSE)
  }

  if (!is.null(cds_cu_f) & !is.null(cds_cu_r)){
    cds_cu <- rbind.data.frame(cds_cu_f, cds_cu_r)
    colnames(cds_cu) <- c("cu_bias", "gene", "start", "strand")
  } else if(!is.null(cds_cu_f)){
    cds_cu <- cds_cu_f
    colnames(cds_cu) <- c("cu_bias", "gene", "start", "strand")
  } else if(!is.null(cds_cu_r)){
    cds_cu <- cds_cu_r
    colnames(cds_cu) <- c("cu_bias", "gene", "start", "strand")
  } else {
    cds_cu <- NULL
  }

  return(cds_cu)
}

