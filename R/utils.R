ensure_dir <- function(file) {
  dir_path <- dirname(file)

  if (identical(dir_path, ".") || dir.exists(dir_path)) {
    return(invisible(NULL))
  }

  dir.create(dir_path, recursive = TRUE, showWarnings = FALSE)

  if (!dir.exists(dir_path)) {
    cli::cli_abort("Could not create output directory: {dir_path}")
  }

  invisible(NULL)
}

#' Write CSV file
#'
#' Write data to a CSV file, creating parent directories as needed.
#'
#' @param x Data frame to save
#' @param file Output file path
#' @param ... Additional arguments passed to readr::write_csv()
#'
#' @return Invisibly returns `x`.
#'
#' @export
write_csv <- function(x, file, ...) {
  ensure_dir(file)
  readr::write_csv(x, file, ...)
  invisible(x)
}

#' Write Parquet file
#'
#' Write data to a Parquet file, creating parent directories as needed.
#'
#' @param x Data frame to save
#' @param file Output file path
#' @param ... Additional arguments passed to arrow::write_parquet()
#'
#' @return Invisibly returns `x`.
#'
#' @export
write_parquet <- function(x, file, ...) {
  ensure_dir(file)
  arrow::write_parquet(x, file, ...)
  invisible(x)
}

#' Save RDS file
#'
#' Save an object to an RDS file, creating parent directories as needed.
#'
#' @param x Object to save
#' @param file Output file path
#' @param ... Additional arguments passed to saveRDS()
#'
#' @return Invisibly returns `x`.
#'
#' @export
save_rds <- function(x, file, ...) {
  ensure_dir(file)
  base::saveRDS(x, file = file, ...)
  invisible(x)
}
