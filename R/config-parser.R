#' Read and parse pipeline YAML configuration
#'
#' @param config_path Path to pipeline.yml file
#'
#' @return List with keys: name, description, sources, transforms, outputs
#'
#' @keywords internal
read_pipeline_config <- function(config_path) {
  if (!file.exists(config_path)) {
    targets::tar_throw_validate(
      paste("Config file not found:", config_path)
    )
  }
  cfg <- yaml::read_yaml(config_path)
  targets::tar_assert_list(cfg, "Pipeline config must be a YAML list/object")
  cfg
}

#' Validate pipeline configuration against schema
#'
#' @param config Parsed pipeline configuration (list)
#'
#' @return Invisibly TRUE if valid; raises error otherwise
#'
#' @keywords internal
validate_pipeline_config <- function(config) {
  errors <- character(0)

  if (is.null(config$sources)) {
    errors <- c(errors, "Missing required key: 'sources'")
  }

  if (is.null(config$transforms)) {
    errors <- c(errors, "Missing required key: 'transforms'")
  }

  if (!is.null(config$sources)) {
    targets::tar_assert_list(config$sources, "'sources' must be a list of objects")
    for (i in seq_along(config$sources)) {
      src <- config$sources[[i]]
      if (is.null(src$name)) {
        errors <- c(errors, sprintf("sources[%d]: missing 'name'", i))
      }
      if (is.null(src$type)) {
        errors <- c(errors, sprintf("sources[%d]: missing 'type'", i))
      }
      if (is.null(src$path)) {
        errors <- c(errors, sprintf("sources[%d]: missing 'path'", i))
      }
      valid_types <- c("csv", "parquet", "rds")
      if (!is.null(src$type)) {
        targets::tar_assert_in(src$type, valid_types,
          sprintf("sources[%d]: type '%s' not supported (use: %s)", i, src$type, paste(valid_types, collapse = ", ")))
      }
    }
  }

  if (!is.null(config$transforms)) {
    targets::tar_assert_list(config$transforms, "'transforms' must be a list of objects")
    for (i in seq_along(config$transforms)) {
      trn <- config$transforms[[i]]
      if (is.null(trn$name)) {
        errors <- c(errors, sprintf("transforms[%d]: missing 'name'", i))
      }
      if (is.null(trn$input)) {
        errors <- c(errors, sprintf("transforms[%d]: missing 'input'", i))
      }
      if (is.null(trn$`function`)) {
        errors <- c(errors, sprintf("transforms[%d]: missing 'function'", i))
      }
    }

    transform_names <- vapply(config$transforms, function(x) x$name, character(1))
    targets::tar_assert_unique(transform_names,
      sprintf("Duplicate transform name: %s", paste(unique(transform_names[duplicated(transform_names)]), collapse = ", ")))
  }

  if (!is.null(config$outputs)) {
    targets::tar_assert_list(config$outputs, "'outputs' must be a list of objects")
    for (i in seq_along(config$outputs)) {
      out <- config$outputs[[i]]
      if (is.null(out$name)) {
        errors <- c(errors, sprintf("outputs[%d]: missing 'name'", i))
      }
      if (is.null(out$format)) {
        errors <- c(errors, sprintf("outputs[%d]: missing 'format'", i))
      }
      if (is.null(out$path)) {
        errors <- c(errors, sprintf("outputs[%d]: missing 'path'", i))
      }
      valid_formats <- c("csv", "parquet", "rds")
      if (!is.null(out$format)) {
        targets::tar_assert_in(out$format, valid_formats,
          sprintf("outputs[%d]: format '%s' not supported (use: %s)", i, out$format, paste(valid_formats, collapse = ", ")))
      }
    }
  }

  if (length(errors) > 0) {
    error_msg <- paste(c("Invalid pipeline configuration:", errors), collapse = "\n  ")
    targets::tar_throw_validate(error_msg)
  }

  invisible(TRUE)
}
