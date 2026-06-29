test_that("build_source_target creates correct target", {
  source <- list(
    name = "raw_data",
    type = "csv",
    path = "data/input.csv",
    options = list(na = "NULL")
  )

  target <- build_source_target(source)

  # Check it's a tar_target object
  expect_s3_class(target, "tar_target")
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
