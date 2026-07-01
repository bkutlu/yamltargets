test_that("validate_pipeline detects errors", {
  # Create a temporary invalid YAML file
  yaml_content <- "
sources:
  - name: data1
    # missing type
    path: test.csv
transforms: []
"
  yaml_file <- withr::local_file(tempfile(fileext = ".yml"))
  writeLines(yaml_content, yaml_file)

  expect_error(
    validate_pipeline(yaml_file),
    "missing 'type'"
  )
})

test_that("create_pipeline_from_yaml validates config", {
  yaml_content <- "
transforms: []
# missing sources
"
  yaml_file <- withr::local_file(tempfile(fileext = ".yml"))
  writeLines(yaml_content, yaml_file)

  expect_error(
    create_pipeline_from_yaml(yaml_file),
    "Missing required key.*sources"
  )
})

test_that("create_pipeline_from_yaml can skip post-build targets validation", {
  yaml_content <- "
sources:
  - name: raw_data
    type: csv
    path: data/input.csv
"
  yaml_file <- withr::local_file(tempfile(fileext = ".yml"))
  writeLines(yaml_content, yaml_file)

  targets <- create_pipeline_from_yaml(yaml_file, validate_targets = FALSE)

  expect_named(targets, "raw_data")
})

test_that("create_pipeline_from_yaml catches cyclic target graphs", {
  yaml_content <- "
sources:
  - name: raw_data
    type: csv
    path: data/input.csv
transforms:
  - name: step_a
    input: step_b
    function: transform_a
  - name: step_b
    input: step_a
    function: transform_b
"
  yaml_file <- withr::local_file(tempfile(fileext = ".yml"))
  writeLines(yaml_content, yaml_file)

  expect_snapshot(
    create_pipeline_from_yaml(yaml_file),
    error = TRUE
  )
})
