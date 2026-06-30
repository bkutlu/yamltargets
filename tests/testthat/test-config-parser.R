test_that("read_pipeline_config handles missing file", {
  expect_error(
    read_pipeline_config("nonexistent.yml"),
    "not found"
  )
})

test_that("read_pipeline_config requires a scalar path", {
  expect_error(
    read_pipeline_config(c("a.yml", "b.yml")),
    "single file path"
  )
})

test_that("read_pipeline_config wraps YAML parse errors", {
  yaml_file <- withr::local_file(tempfile(fileext = ".yml"))
  writeLines("sources: [", yaml_file)

  expect_error(
    read_pipeline_config(yaml_file),
    "Could not parse config file"
  )
})

test_that("validate_pipeline_config detects missing sources", {
  config <- list(transforms = list())
  expect_error(
    validate_pipeline_config(config),
    "Missing required key.*sources"
  )
})

test_that("validate_pipeline_config allows source-only pipelines", {
  config <- list(
    sources = list(list(
      name = "raw",
      type = "csv",
      path = "data.csv"
    ))
  )

  expect_no_error(validate_pipeline_config(config))
})

test_that("validate_pipeline_config requires section records", {
  config <- list(sources = list("not-an-object"))

  expect_error(
    validate_pipeline_config(config),
    "sources\\[1\\] must be an object"
  )
})

test_that("validate_pipeline_config detects missing source name", {
  config <- list(
    sources = list(list(
      type = "csv",
      path = "data.csv"
    )),
    transforms = list()
  )

  expect_error(
    validate_pipeline_config(config),
    "sources\\[1\\]: missing 'name'"
  )
})

test_that("validate_pipeline_config detects missing transform name", {
  config <- list(
    sources = list(list(
      name = "raw",
      type = "csv",
      path = "data.csv"
    )),
    transforms = list(list(
      input = "raw",
      `function` = "clean_data"
    ))
  )

  expect_error(
    validate_pipeline_config(config),
    "transforms\\[1\\]: missing 'name'"
  )
})

test_that("validate_pipeline_config detects missing output name", {
  config <- list(
    sources = list(list(
      name = "raw",
      type = "csv",
      path = "data.csv"
    )),
    transforms = list(),
    outputs = list(list(
      format = "csv",
      path = "results/"
    ))
  )

  expect_error(
    validate_pipeline_config(config),
    "outputs\\[1\\]: missing 'name'"
  )
})

test_that("validate_pipeline_config detects invalid source type", {
  config <- list(
    sources = list(list(
      name = "test",
      type = "invalid",
      path = "test.txt"
    )),
    transforms = list()
  )

  expect_error(
    validate_pipeline_config(config),
    "not supported"
  )
})

test_that("validate_pipeline_config rejects non-scalar choices", {
  config <- list(
    sources = list(list(
      name = "test",
      type = c("csv", "rds"),
      path = "test.txt"
    ))
  )

  expect_error(
    validate_pipeline_config(config),
    "type must be a single"
  )
})

test_that("validate_pipeline_config detects undefined transform input", {
  config <- list(
    sources = list(list(
      name = "raw",
      type = "csv",
      path = "data.csv"
    )),
    transforms = list(list(
      name = "cleaned",
      input = "undefined",
      `function` = "clean_data"
    ))
  )

  expect_error(
    validate_pipeline_config(config),
    "input 'undefined' not defined"
  )
})

test_that("validate_pipeline_config detects undefined output name", {
  config <- list(
    sources = list(list(
      name = "raw",
      type = "csv",
      path = "data.csv"
    )),
    transforms = list(list(
      name = "cleaned",
      input = "raw",
      `function` = "clean_data"
    )),
    outputs = list(list(
      name = "undefined",
      format = "csv",
      path = "results/"
    ))
  )

  expect_error(
    validate_pipeline_config(config),
    "name 'undefined' not defined"
  )
})

test_that("validate_pipeline_config accepts valid cross-references", {
  config <- list(
    sources = list(list(
      name = "raw",
      type = "csv",
      path = "data.csv"
    )),
    transforms = list(list(
      name = "cleaned",
      input = "raw",
      `function` = "clean_data"
    )),
    outputs = list(list(
      name = "cleaned",
      format = "csv",
      path = "results/"
    ))
  )

  expect_no_error(validate_pipeline_config(config))
})

test_that("validate_pipeline_config detects missing format for file_read", {
  config <- list(
    sources = list(list(
      name = "raw",
      type = "file_read",
      path = "data.csv"
    )),
    transforms = list()
  )

  expect_error(
    validate_pipeline_config(config),
    "missing 'format'"
  )
})

test_that("validate_pipeline_config detects invalid format for file_read", {
  config <- list(
    sources = list(list(
      name = "raw",
      type = "file_read",
      format = "json",
      path = "data.csv"
    )),
    transforms = list()
  )

  expect_error(
    validate_pipeline_config(config),
    "format 'json' not supported"
  )
})

test_that("validate_pipeline_config accepts valid file_read with format", {
  config <- list(
    sources = list(list(
      name = "raw",
      type = "file_read",
      format = "csv",
      path = "data.csv"
    )),
    transforms = list()
  )

  expect_no_error(validate_pipeline_config(config))
})

test_that("validate_pipeline_config detects duplicate source names", {
  config <- list(
    sources = list(
      list(name = "raw", type = "csv", path = "a.csv"),
      list(name = " raw ", type = "rds", path = "b.rds")
    )
  )

  expect_error(
    validate_pipeline_config(config),
    "Duplicate source name: raw"
  )
})

test_that("validate_pipeline_config detects source and transform collisions", {
  config <- list(
    sources = list(list(
      name = "raw",
      type = "csv",
      path = "data.csv"
    )),
    transforms = list(list(
      name = "raw",
      input = "raw",
      `function` = "clean_data"
    ))
  )

  expect_error(
    validate_pipeline_config(config),
    "Duplicate target name: raw"
  )
})

test_that("validate_pipeline_config detects generated save target collisions", {
  config <- list(
    sources = list(
      list(name = "raw", type = "csv", path = "data.csv"),
      list(name = "save_raw", type = "rds", path = "data.rds")
    ),
    outputs = list(list(
      name = "raw",
      format = "csv",
      path = "results/"
    ))
  )

  expect_error(
    validate_pipeline_config(config),
    "Duplicate target name: save_raw"
  )
})

test_that("validate_pipeline_config detects generated file target collisions", {
  config <- list(
    sources = list(
      list(name = "raw", type = "file_read", format = "csv", path = "data.csv"),
      list(name = "raw_file", type = "rds", path = "data.rds")
    )
  )

  expect_error(
    validate_pipeline_config(config),
    "Duplicate generated target name: raw_file"
  )
})

test_that("validate_pipeline_config detects invalid target names", {
  config <- list(
    sources = list(list(
      name = "raw-data",
      type = "csv",
      path = "data.csv"
    ))
  )

  expect_error(
    validate_pipeline_config(config),
    "Invalid target name: raw-data"
  )
})

test_that("validate_pipeline_config validates options and params as named lists", {
  config <- list(
    sources = list(list(
      name = "raw",
      type = "csv",
      path = "data.csv",
      options = list("NA")
    )),
    transforms = list(list(
      name = "cleaned",
      input = "raw",
      `function` = "clean_data",
      params = list(TRUE)
    ))
  )

  expect_error(
    validate_pipeline_config(config),
    "must be a named list"
  )
})
