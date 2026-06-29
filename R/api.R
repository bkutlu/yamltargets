#' Create a targets pipeline from YAML configuration
#'
#' Parses a YAML configuration file and generates target definition objects.
#' Transform functions referenced in the YAML must be available in the
#' package namespace when targets evaluates the pipeline.
#'
#' @param config_path Path to pipeline.yml configuration file.
#'
#' @return A list of target definition objects. Call this function as the
#'   entire return value of your `_targets.R` script.
#'
#' @examples
#' \dontrun{
#'   # _targets.R
#'   library(targets)
#'   tar_option_set(format = "parquet")
#'   create_pipeline_from_yaml("pipeline.yml")
#' }
#'
#' @export
create_pipeline_from_yaml <- function(config_path) {
  config <- read_pipeline_config(config_path)
  validate_pipeline_config(config)
  build_targets(config)
}

#' Validate a pipeline configuration without running
#'
#' Checks that the YAML configuration is well-formed and meets schema
#' requirements. Raises an error if validation fails.
#'
#' @param config_path Path to pipeline.yml
#'
#' @return Invisibly returns `TRUE` if valid. Raises an error otherwise.
#'
#' @export
validate_pipeline <- function(config_path) {
  config <- read_pipeline_config(config_path)
  validate_pipeline_config(config)
  invisible(TRUE)
}
