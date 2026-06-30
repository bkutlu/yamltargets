build_targets <- function(config, validate_targets = TRUE) {
  targets_list <- list()

  if (!is.null(config$sources)) {
    source_targets <- lapply(config$sources, build_source_target)
    targets_list <- c(targets_list, unlist(source_targets, recursive = FALSE))
  }

  if (!is.null(config$transforms)) {
    transform_targets <- lapply(config$transforms, build_transform_target)
    names(transform_targets) <- vapply(
      config$transforms,
      function(transform) {
        normalize_name(transform$name)
      },
      character(1)
    )
    targets_list <- c(targets_list, transform_targets)
  }

  if (!is.null(config$outputs)) {
    output_targets <- lapply(config$outputs, build_output_target)
    names(output_targets) <- vapply(
      config$outputs,
      function(output) {
        paste0("save_", normalize_name(output$name))
      },
      character(1)
    )
    targets_list <- c(targets_list, output_targets)
  }

  if (isTRUE(validate_targets)) {
    validate_targets_pipeline(targets_list)
  }

  targets_list
}

build_source_target <- function(source) {
  name_to_use <- normalize_name(source$name)

  if (identical(source$type, "file_read")) {
    name_file <- paste0(name_to_use, "_file")
    loader_fn <- get_loader_function(source$format)
    read_args <- append_call_args(
      list(file = rlang::sym(name_file)),
      source$options
    )

    result <- list(
      targets::tar_target_raw(
        name = name_file,
        command = rlang::call2(base::identity, source$path),
        format = "file"
      ),
      targets::tar_target_raw(
        name = name_to_use,
        command = rlang::call2(loader_fn, !!!read_args)
      )
    )
    names(result) <- c(name_file, name_to_use)
    return(result)
  }

  loader_fn <- get_loader_function(source$type)
  result <- list(targets::tar_target_raw(
    name = name_to_use,
    command = build_loader_call(loader_fn, source)
  ))
  names(result) <- name_to_use
  result
}

build_transform_target <- function(transform) {
  fn_name <- transform$`function`
  input_names <- normalize_names(transform$input)
  call_args <- lapply(input_names, rlang::sym)
  call_args <- append_call_args(call_args, transform$params)
  name_to_use <- normalize_name(transform$name)

  targets::tar_target_raw(
    name = name_to_use,
    command = rlang::call2(fn_name, !!!call_args)
  )
}

build_output_target <- function(output) {
  save_fn <- get_save_function(output$format)
  output_name <- normalize_name(output$name)
  output_path <- build_output_path(
    path = output$path,
    name = output_name,
    format = output$format
  )

  call_expr <- rlang::call2(
    save_fn,
    x = rlang::sym(output_name),
    file = output_path
  )

  targets::tar_target_raw(
    name = paste0("save_", output_name),
    command = call_expr,
    format = "file"
  )
}

build_output_path <- function(path, name, format) {
  filename <- paste0(name, ".", tolower(format))
  output_dir <- sub("[/\\\\]+$", "", trimws(path))

  file.path(output_dir, filename)
}

validate_targets_pipeline <- function(targets_list) {
  pipeline_from_list <- get(
    "pipeline_from_list",
    envir = asNamespace("targets")
  )
  pipeline_validate <- get("pipeline_validate", envir = asNamespace("targets"))

  tryCatch(
    {
      pipeline <- pipeline_from_list(targets_list)
      pipeline_validate(pipeline)
    },
    error = function(error) {
      targets::tar_throw_validate(
        paste0(
          "Generated targets pipeline failed {targets} validation: ",
          conditionMessage(error)
        )
      )
    }
  )

  invisible(TRUE)
}

get_loader_function <- function(type) {
  format_info <- .file_formats[[type]]

  if (is.null(format_info)) {
    cli::cli_abort("Unknown loader type: {type}")
  }

  format_info$loader
}

get_save_function <- function(format) {
  format_info <- .file_formats[[format]]

  if (is.null(format_info)) {
    cli::cli_abort("Unknown save format: {format}")
  }

  format_info$writer
}

build_loader_call <- function(loader_fn, source) {
  call_args <- append_call_args(
    list(file = source$path),
    source$options
  )

  rlang::call2(loader_fn, !!!call_args)
}

append_call_args <- function(call_args, extra_args) {
  if (is.null(extra_args)) {
    return(call_args)
  }

  c(call_args, extra_args)
}
