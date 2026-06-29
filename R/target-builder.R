#' Build tar_target() calls from YAML configuration
#'
#' Generates target definition objects for sources (loaders), transforms, and
#' outputs. Returns a list suitable for use in `_targets.R`.
#'
#' @param config Parsed pipeline configuration
#'
#' @return Named list of target definition objects. Names are target names
#'   (e.g., source name, transform name, "save_<output_name>").
#'
#' @keywords internal
build_targets <- function(config) {
  targets_list <- list()

  if (!is.null(config$sources)) {
    for (src in config$sources) {
      target <- build_source_target(src)
      targets_list[[src$name]] <- target
    }
  }

  if (!is.null(config$transforms)) {
    for (trn in config$transforms) {
      target <- build_transform_target(trn)
      targets_list[[trn$name]] <- target
    }
  }

  if (!is.null(config$outputs)) {
    for (out in config$outputs) {
      target <- build_output_target(out)
      targets_list[[paste0("save_", out$name)]] <- target
    }
  }

  targets_list
}

#' Build a source (loader) target
#'
#' @param source Source config (list with name, type, path, options)
#'
#' @return tar_target() call
#'
#' @keywords internal
build_source_target <- function(source) {
  targets::tar_assert_list(source)
  targets::tar_assert_chr(source$name)
  targets::tar_assert_chr(source$type)

  loader_fn <- get_loader_function(source$type)
  call_expr <- build_loader_call(loader_fn, source)

  name_to_use <- trimws(source$name)

  targets::tar_target_raw(
    name = name_to_use,
    command = call_expr
  )
}

#' Build a transform target
#'
#' @param transform Transform config (list with name, input, function, params)
#'
#' @return tar_target() call
#'
#' @keywords internal
build_transform_target <- function(transform) {
  targets::tar_assert_list(transform)
  targets::tar_assert_chr(transform$name)
  targets::tar_assert_chr(transform$`function`)

  fn_name <- transform$`function`
  input_names <- trimws(as.character(transform$input))

  # Build call with inputs as positional arguments
  call_args <- lapply(input_names, rlang::sym)

  if (!is.null(transform$params)) {
    call_args <- c(call_args, transform$params)
  }

  call_expr <- rlang::call2(fn_name, !!!call_args)
  name_to_use <- trimws(as.character(transform$name))

  targets::tar_target_raw(
    name = name_to_use,
    command = call_expr
  )
}

#' Build an output (save) target
#'
#' @param output Output config (list with name, format, path)
#'
#' @return tar_target() call
#'
#' @keywords internal
build_output_target <- function(output) {
  targets::tar_assert_list(output)
  targets::tar_assert_chr(output$name)
  targets::tar_assert_chr(output$format)

  save_fn <- get_save_function(output$format)
  output_name <- trimws(output$name)
  filename <- paste0(output_name, ".", tolower(output$format))
  output_path <- file.path(output$path, filename)

  call_expr <- rlang::call2(
    save_fn,
    x = as.symbol(output_name),
    file = output_path
  )

  target_name <- paste0("save_", output_name)
  target <- targets::tar_target_raw(
    name = target_name,
    command = call_expr
  )

  # Log target command for debugging
  if (Sys.getenv("YAMLTARGETS_DEBUG") == "true") {
    message(sprintf("%s <- %s", target_name, targets::tar_deparse_language(call_expr)))
  }

  target
}

#' Get appropriate loader function name based on file type
#'
#' @param type File type (csv, parquet, rds)
#'
#' @return Function name as string
#'
#' @keywords internal
get_loader_function <- function(type) {
  switch(type,
    csv = "read_csv",
    parquet = "read_parquet",
    rds = "read_rds",
    cli::cli_abort(sprintf("Unknown loader type: %s", type))
  )
}

#' Get appropriate save function name based on format
#'
#' @param format Output format (csv, parquet, rds)
#'
#' @return Function name as string
#'
#' @keywords internal
get_save_function <- function(format) {
  switch(format,
    csv = "write_csv",
    parquet = "write_parquet",
    rds = "save_rds",
    cli::cli_abort(sprintf("Unknown save format: %s", format))
  )
}

#' Build a loader function call
#'
#' @param loader_fn Loader function name (string)
#' @param source Source config
#'
#' @return unevaluated function call
#'
#' @keywords internal
build_loader_call <- function(loader_fn, source) {
  call_args <- list(file = source$path)

  if (!is.null(source$options)) {
    call_args <- c(call_args, source$options)
  }

  rlang::call2(loader_fn, !!!call_args)
}
