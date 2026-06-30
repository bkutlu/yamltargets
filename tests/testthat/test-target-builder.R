test_that("build_source_target creates correct target", {
  source <- list(
    name = "raw_data",
    type = "csv",
    path = "data/input.csv",
    options = list(na = "NULL")
  )

  target <- build_source_target(source)

  expect_type(target, "list")
  expect_named(target, "raw_data")
  expect_s3_class(target[[1]], "tar_target")
})

test_that("get_loader_function returns correct function names", {
  expect_equal(get_loader_function("csv"), "read_csv")
  expect_equal(get_loader_function("parquet"), "read_parquet")
  expect_equal(get_loader_function("rds"), "read_rds")
})

test_that("get_loader_function raises error for unknown type", {
  expect_error(
    get_loader_function("unknown"),
    "Unknown loader type"
  )
})

test_that("get_save_function returns correct function names", {
  expect_equal(get_save_function("csv"), "write_csv")
  expect_equal(get_save_function("parquet"), "write_parquet")
  expect_equal(get_save_function("rds"), "save_rds")
})

test_that("get_save_function raises error for unknown format", {
  expect_error(
    get_save_function("unknown"),
    "Unknown save format"
  )
})

test_that("build_output_path treats path as an output directory", {
  expect_equal(
    build_output_path(path = "results", name = "cleaned", format = "csv"),
    file.path("results", "cleaned.csv")
  )
  expect_equal(
    build_output_path(path = "results/", name = "cleaned", format = "parquet"),
    file.path("results", "cleaned.parquet")
  )
})

test_that("build_output_target writes to generated file under output directory", {
  target <- build_output_target(list(
    name = "cleaned",
    format = "csv",
    path = "results/"
  ))

  expect_s3_class(target, "tar_target")
  expect_equal(target$name, "save_cleaned")
  expect_equal(target$settings$format, "file")
  expect_equal(
    get("expr", envir = target$command),
    expression(write_csv(x = cleaned, file = "results/cleaned.csv"))
  )
})

test_that("build_source_target with type=file_read creates two targets", {
  source <- list(
    name = "raw_data",
    type = "file_read",
    format = "csv",
    path = "data/input.csv"
  )

  result <- build_source_target(source)

  # Check we get a list of 2 targets
  expect_true(is.list(result) && !inherits(result, "tar_target"))
  expect_equal(length(result), 2)
  expect_true(inherits(result[[1]], "tar_target"))
  expect_true(inherits(result[[2]], "tar_target"))

  # Check names
  expect_equal(names(result), c("raw_data_file", "raw_data"))

  # Check file target has format="file"
  expect_equal(result[[1]]$settings$format, "file")
})

test_that("build_source_target with standard type creates single named target", {
  source <- list(
    name = "raw_data",
    type = "csv",
    path = "data/input.csv"
  )

  target <- build_source_target(source)

  expect_type(target, "list")
  expect_named(target, "raw_data")
  expect_s3_class(target[[1]], "tar_target")
})

test_that("build_transform_target creates correct target", {
  transform <- list(
    name = "cleaned",
    input = "raw_data",
    `function` = "clean_data",
    params = list(remove_na = TRUE)
  )

  target <- build_transform_target(transform)

  # Check it's a tar_target object
  expect_s3_class(target, "tar_target")
})

test_that("validate_targets_pipeline accepts generated targets", {
  config <- list(
    sources = list(list(
      name = "raw_data",
      type = "csv",
      path = "data/input.csv"
    )),
    transforms = list(list(
      name = "cleaned",
      input = "raw_data",
      `function` = "clean_data"
    )),
    outputs = list(list(
      name = "cleaned",
      format = "csv",
      path = "results"
    ))
  )

  targets <- build_targets(config, validate_targets = FALSE)

  expect_true(validate_targets_pipeline(targets))
})
