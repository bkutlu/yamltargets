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
      valid_types <- c("csv", "parquet", "rds", "file_read")
      if (!is.null(src$type)) {
        targets::tar_assert_in(src$type, valid_types,
          sprintf("sources[%d]: type '%s' not supported (use: %s)", i, src$type, paste(valid_types, collapse = ", ")))

        if (src$type == "file_read") {
          if (is.null(src$format)) {
            errors <- c(errors, sprintf("sources[%d]: missing 'format' (required for type='file_read')", i))
          } else {
            valid_formats <- c("csv", "parquet", "rds")
            targets::tar_assert_in(src$format, valid_formats,
              sprintf("sources[%d]: format '%s' not supported (use: %s)", i, src$format, paste(valid_formats, collapse = ", ")))
          }
        }
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

  # Cross-reference validation: check that inputs and outputs reference defined targets
  defined_names <- character(0)

  # Build set of defined target names (sources first, then transforms in order)
  if (!is.null(config$sources)) {
    defined_names <- c(defined_names,
      vapply(config$sources, function(x) x$name %||% "", character(1)))
  }
  if (!is.null(config$transforms)) {
    defined_names <- c(defined_names,
      vapply(config$transforms, function(x) x$name %||% "", character(1)))
  }

  # Check that transform inputs reference defined targets
  if (!is.null(config$transforms)) {
    for (i in seq_along(config$transforms)) {
      trn <- config$transforms[[i]]
      if (!is.null(trn$input)) {
        for (inp in as.character(trn$input)) {
          if (!inp %in% defined_names) {
            errors <- c(errors,
              sprintf("transforms[%d]: input '%s' not defined", i, inp))
          }
        }
      }
    }
  }

  # Check that output names reference defined targets
  if (!is.null(config$outputs)) {
    for (i in seq_along(config$outputs)) {
      out <- config$outputs[[i]]
      if (!is.null(out$name) && !out$name %in% defined_names) {
        errors <- c(errors,
          sprintf("outputs[%d]: name '%s' not defined", i, out$name))
      }
    }
  }

  if (length(errors) > 0) {
    error_msg <- paste(c("Invalid pipeline configuration:", errors), collapse = "\n  ")
    targets::tar_throw_validate(error_msg)
  }

  invisible(TRUE)
}
