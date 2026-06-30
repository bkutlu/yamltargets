read_pipeline_config <- function(config_path) {
  if (!is_scalar_character(config_path)) {
    targets::tar_throw_validate("'config_path' must be a single file path")
  }

  if (!file_test("-f", config_path)) {
    targets::tar_throw_validate(
      paste("Config file not found:", config_path)
    )
  }

  cfg <- tryCatch(
    yaml::read_yaml(config_path),
    error = function(error) {
      targets::tar_throw_validate(
        paste0(
          "Could not parse config file '",
          config_path,
          "': ",
          conditionMessage(error)
        )
      )
    }
  )

  targets::tar_assert_list(cfg, "Pipeline config must be a YAML list/object")
  cfg
}

validate_pipeline_config <- function(config) {
  errors <- validate_required_sections(config)

  sources <- config$sources
  transforms <- config$transforms
  outputs <- config$outputs

  if (!is.null(sources)) {
    errors <- c(errors, validate_record_list(sources, "sources"))
    if (is_record_list(sources)) {
      errors <- c(errors, validate_sources(sources))
    }
  }

  if (!is.null(transforms)) {
    errors <- c(errors, validate_record_list(transforms, "transforms"))
    if (is_record_list(transforms)) {
      errors <- c(errors, validate_transforms(transforms))
    }
  }

  if (!is.null(outputs)) {
    errors <- c(errors, validate_record_list(outputs, "outputs"))
    if (is_record_list(outputs)) {
      errors <- c(errors, validate_outputs(outputs))
    }
  }

  source_names <- extract_scalar_field(sources, "name")
  transform_names <- extract_scalar_field(transforms, "name")
  defined_names <- c(source_names, transform_names)
  defined_names <- defined_names[!is.na(defined_names)]

  errors <- c(
    errors,
    validate_all_target_names(sources, transforms, outputs),
    validate_transform_inputs(transforms, defined_names),
    validate_output_references(outputs, defined_names)
  )

  throw_config_errors(errors)
  invisible(TRUE)
}

.file_formats <- list(
  csv = list(loader = "read_csv", writer = "write_csv"),
  parquet = list(loader = "read_parquet", writer = "write_parquet"),
  rds = list(loader = "read_rds", writer = "save_rds")
)
.valid_file_formats <- names(.file_formats)
.valid_source_types <- c(.valid_file_formats, "file_read")

validate_required_sections <- function(config) {
  required_fields <- "sources"
  missing_fields <- required_fields[vapply(
    required_fields,
    function(field) {
      is.null(config[[field]])
    },
    logical(1)
  )]

  if (length(missing_fields) == 0) {
    return(character(0))
  }

  sprintf("Missing required key: '%s'", missing_fields)
}

validate_record_list <- function(items, label) {
  if (!is.list(items)) {
    return(sprintf("'%s' must be a list of objects", label))
  }

  invalid <- which(!vapply(items, is.list, logical(1)))
  if (length(invalid) == 0) {
    return(character(0))
  }

  sprintf("%s[%d] must be an object", label, invalid)
}

is_record_list <- function(items) {
  is.list(items) && all(vapply(items, is.list, logical(1)))
}

validate_sources <- function(sources) {
  errors <- validate_required_fields(
    sources,
    fields = c("name", "type", "path"),
    label = "sources"
  )

  source_names <- extract_scalar_field(sources, "name")
  errors <- c(
    errors,
    validate_unique_names(source_names, "Duplicate source name")
  )

  for (i in seq_along(sources)) {
    source <- sources[[i]]

    errors <- c(
      errors,
      validate_character_field(source, "name", sprintf("sources[%d]: name", i)),
      validate_character_field(source, "type", sprintf("sources[%d]: type", i)),
      validate_character_field(source, "path", sprintf("sources[%d]: path", i)),
      validate_named_list_field(
        source,
        "options",
        sprintf("sources[%d]: options", i)
      ),
      validate_choice(
        source$type,
        choices = .valid_source_types,
        label = sprintf("sources[%d]: type", i)
      )
    )

    if (identical(source$type, "file_read")) {
      if (is.null(source$format)) {
        errors <- c(
          errors,
          sprintf(
            "sources[%d]: missing 'format' (required for type='file_read')",
            i
          )
        )
      } else {
        errors <- c(
          errors,
          validate_character_field(
            source,
            "format",
            sprintf("sources[%d]: format", i)
          ),
          validate_choice(
            source$format,
            choices = .valid_file_formats,
            label = sprintf("sources[%d]: format", i)
          )
        )
      }
    }
  }

  errors
}

validate_transforms <- function(transforms) {
  errors <- validate_required_fields(
    transforms,
    fields = c("name", "input", "function"),
    label = "transforms"
  )

  transform_names <- extract_scalar_field(transforms, "name")
  errors <- c(
    errors,
    validate_unique_names(transform_names, "Duplicate transform name")
  )

  for (i in seq_along(transforms)) {
    transform <- transforms[[i]]

    errors <- c(
      errors,
      validate_character_field(
        transform,
        "name",
        sprintf("transforms[%d]: name", i)
      ),
      validate_character_field(
        transform,
        "input",
        sprintf("transforms[%d]: input", i),
        allow_vector = TRUE
      ),
      validate_character_field(
        transform,
        "function",
        sprintf("transforms[%d]: function", i)
      ),
      validate_named_list_field(
        transform,
        "params",
        sprintf("transforms[%d]: params", i)
      )
    )
  }

  errors
}

validate_outputs <- function(outputs) {
  errors <- validate_required_fields(
    outputs,
    fields = c("name", "format", "path"),
    label = "outputs"
  )

  for (i in seq_along(outputs)) {
    output <- outputs[[i]]
    errors <- c(
      errors,
      validate_character_field(output, "name", sprintf("outputs[%d]: name", i)),
      validate_character_field(
        output,
        "format",
        sprintf("outputs[%d]: format", i)
      ),
      validate_character_field(output, "path", sprintf("outputs[%d]: path", i)),
      validate_choice(
        output$format,
        choices = .valid_file_formats,
        label = sprintf("outputs[%d]: format", i)
      )
    )
  }

  errors
}

validate_required_fields <- function(items, fields, label) {
  errors <- character(0)

  for (i in seq_along(items)) {
    item <- items[[i]]
    missing_fields <- fields[vapply(
      fields,
      function(field) {
        is.null(item[[field]])
      },
      logical(1)
    )]

    if (length(missing_fields) > 0) {
      errors <- c(
        errors,
        sprintf("%s[%d]: missing '%s'", label, i, missing_fields)
      )
    }
  }

  errors
}

validate_character_field <- function(item, field, label, allow_vector = FALSE) {
  value <- item[[field]]

  if (is.null(value)) {
    return(character(0))
  }

  if (!is.character(value)) {
    return(sprintf("%s must be character", label))
  }

  if (!allow_vector && length(value) != 1L) {
    return(sprintf("%s must be a single value", label))
  }

  if (length(value) == 0L || any(is.na(value)) || any(!nzchar(trimws(value)))) {
    return(sprintf("%s must not be missing or empty", label))
  }

  character(0)
}

validate_named_list_field <- function(item, field, label) {
  value <- item[[field]]

  if (is.null(value)) {
    return(character(0))
  }

  if (!is.list(value)) {
    return(sprintf("%s must be a list", label))
  }

  names_value <- names(value)
  if (is.null(names_value) || any(!nzchar(names_value))) {
    return(sprintf("%s must be a named list", label))
  }

  character(0)
}

validate_choice <- function(value, choices, label) {
  if (is.null(value)) {
    return(character(0))
  }

  if (!is_scalar_character(value)) {
    return(sprintf("%s must be a single character value", label))
  }

  if (value %in% choices) {
    return(character(0))
  }

  sprintf(
    "%s '%s' not supported (use: %s)",
    label,
    value,
    paste(choices, collapse = ", ")
  )
}

validate_unique_names <- function(target_names, label) {
  target_names <- normalize_names(target_names[!is.na(target_names)])
  duplicated_names <- unique(target_names[duplicated(target_names)])

  if (length(duplicated_names) == 0) {
    return(character(0))
  }

  sprintf("%s: %s", label, paste(duplicated_names, collapse = ", "))
}

validate_all_target_names <- function(sources, transforms, outputs) {
  source_names <- extract_scalar_field(sources, "name")
  transform_names <- extract_scalar_field(transforms, "name")
  output_names <- extract_scalar_field(outputs, "name")
  save_names <- paste0("save_", output_names[!is.na(output_names)])

  all_names <- c(source_names, transform_names, save_names)
  all_names <- all_names[!is.na(all_names)]

  errors <- c(
    validate_target_name_syntax(all_names),
    validate_unique_names(all_names, "Duplicate target name")
  )

  source_records <- if (is_record_list(sources)) {
    sources
  } else {
    list()
  }

  file_read_names <- vapply(
    source_records,
    function(source) {
      if (
        identical(source$type, "file_read") && is_scalar_character(source$name)
      ) {
        return(paste0(normalize_name(source$name), "_file"))
      }
      NA_character_
    },
    character(1)
  )
  file_read_names <- file_read_names[!is.na(file_read_names)]

  errors <- c(
    errors,
    validate_unique_names(
      c(all_names, file_read_names),
      "Duplicate generated target name"
    )
  )

  errors
}

validate_target_name_syntax <- function(target_names) {
  target_names <- normalize_names(target_names)
  invalid <- target_names[!grepl("^[A-Za-z.][A-Za-z0-9_.]*$", target_names)]
  invalid <- invalid[invalid != "."]
  invalid <- unique(invalid)

  if (length(invalid) == 0) {
    return(character(0))
  }

  sprintf("Invalid target name: %s", paste(invalid, collapse = ", "))
}

validate_transform_inputs <- function(transforms, defined_names) {
  if (is.null(transforms) || !is_record_list(transforms)) {
    return(character(0))
  }

  defined_names <- normalize_names(defined_names)
  errors <- character(0)

  for (i in seq_along(transforms)) {
    transform <- transforms[[i]]

    if (is.null(transform$input) || !is.character(transform$input)) {
      next
    }

    for (input in normalize_names(transform$input)) {
      if (!input %in% defined_names) {
        errors <- c(
          errors,
          sprintf("transforms[%d]: input '%s' not defined", i, input)
        )
      }
    }
  }

  errors
}

validate_output_references <- function(outputs, defined_names) {
  if (is.null(outputs) || !is_record_list(outputs)) {
    return(character(0))
  }

  defined_names <- normalize_names(defined_names)
  errors <- character(0)

  for (i in seq_along(outputs)) {
    output <- outputs[[i]]

    if (
      is_scalar_character(output$name) &&
        !normalize_name(output$name) %in% defined_names
    ) {
      errors <- c(
        errors,
        sprintf(
          "outputs[%d]: name '%s' not defined",
          i,
          normalize_name(output$name)
        )
      )
    }
  }

  errors
}

extract_scalar_field <- function(items, field) {
  if (is.null(items) || !is_record_list(items)) {
    return(character(0))
  }

  vapply(
    items,
    function(item) {
      value <- item[[field]]

      if (is_scalar_character(value)) {
        value
      } else {
        NA_character_
      }
    },
    character(1)
  )
}

normalize_name <- function(name) {
  trimws(name)
}

normalize_names <- function(names) {
  trimws(names)
}

is_scalar_character <- function(x) {
  is.character(x) && length(x) == 1L && !is.na(x)
}

`%||%` <- function(x, y) {
  if (is.null(x)) {
    y
  } else {
    x
  }
}

throw_config_errors <- function(errors) {
  if (length(errors) == 0) {
    return(invisible(NULL))
  }

  targets::tar_throw_validate(
    paste(c("Invalid pipeline configuration:", errors), collapse = "\n  ")
  )
}
