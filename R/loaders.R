#' Read CSV file
#'
#' @param file Path to CSV file
#' @param ... Additional arguments passed to readr::read_csv()
#'
#' @return Data frame
#'
#' @export
read_csv <- function(file, ...) {
  readr::read_csv(file, ..., show_col_types = FALSE)
}

#' Read Parquet file
#'
#' @param file Path to Parquet file
#' @param ... Additional arguments passed to arrow::read_parquet()
#'
#' @return Data frame
#'
#' @export
read_parquet <- function(file, ...) {
  arrow::read_parquet(file, ...)
}

#' Read RDS file
#'
#' @param file Path to RDS file
#' @param ... Additional arguments passed to readRDS()
#'
#' @return Object restored from RDS file
#'
#' @export
read_rds <- function(file, ...) {
  readRDS(file, ...)
}
