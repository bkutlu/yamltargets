test_that("read_pipeline_config handles missing file", {
  expect_error(
    read_pipeline_config("nonexistent.yml"),
    "not found"
  )
})

test_that("validate_pipeline_config detects missing sources", {
  config <- list(transforms = list())
  expect_error(
    validate_pipeline_config(config),
    "Missing required key.*sources"
  )
})

test_that("validate_pipeline_config detects missing transforms", {
  config <- list(sources = list())
  expect_error(
    validate_pipeline_config(config),
    "Missing required key.*transforms"
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
