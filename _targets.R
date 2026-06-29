library(targets)
library(yamltargets)

tar_option_set(format = "parquet")

# Define your transform functions
clean_data <- function(df) {
  df |>
    dplyr::filter(!is.na(id)) |>
    dplyr::mutate(across(where(is.character), tolower))
}

# Generate pipeline from YAML
create_pipeline_from_yaml("inst/examples/simple-etl/pipeline.yml")
