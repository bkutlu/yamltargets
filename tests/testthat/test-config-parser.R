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
