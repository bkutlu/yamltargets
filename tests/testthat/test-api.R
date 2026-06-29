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
