#' Read and parse pipeline YAML configuration
#'
#' @param config_path Path to pipeline.yml file
#'
#' @return List with keys: name, description, sources, transforms, outputs
#'
#' @keywords internal
read_pipeline_config <- function(config_path) {
  if (!file.exists(config_path)) {
    cli::cli_abort(
      "Config file not found: {.file {config_path}}"
    )
  }

  cfg <- yaml::read_yaml(config_path)

  if (!is.list(cfg)) {
    cli::cli_abort(
      "Pipeline config must be a YAML list/object"
    )
  }

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
    if (!is.list(config$sources)) {
      errors <- c(errors, "'sources' must be a list of objects")
    } else {
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
        if (!is.null(src$type) && !(src$type %in% valid_types)) {
          errors <- c(
            errors,
            sprintf("sources[%d]: type '%s' not supported (use: %s)", i, src$type, paste(valid_types, collapse = ", "))
          )
        }
      }
    }
  }

  if (!is.null(config$transforms)) {
    if (!is.list(config$transforms)) {
      errors <- c(errors, "'transforms' must be a list of objects")
    } else {
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
      dups <- transform_names[duplicated(transform_names)]
      if (length(dups) > 0) {
        errors <- c(errors, sprintf("Duplicate transform name: %s", paste(dups, collapse = ", ")))
      }
    }
  }

  if (!is.null(config$outputs)) {
    if (!is.list(config$outputs)) {
      errors <- c(errors, "'outputs' must be a list of objects")
    } else {
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
        if (!is.null(out$format) && !(out$format %in% valid_formats)) {
          errors <- c(
            errors,
            sprintf("outputs[%d]: format '%s' not supported (use: %s)", i, out$format, paste(valid_formats, collapse = ", "))
          )
        }
      }
    }
  }

  if (length(errors) > 0) {
    error_msg <- paste(errors, collapse = "\n  ")
    cli::cli_abort(
      c(
        "Invalid pipeline configuration:",
        "x" = error_msg
      )
    )
  }

  invisible(TRUE)
}
