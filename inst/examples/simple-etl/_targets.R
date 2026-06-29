library(targets)
library(yamltargets)

# Set default target format
tar_option_set(format = "parquet")

# Define your custom transform functions
clean_data <- function(df) {
  df |>
    dplyr::filter(!is.na(id)) |>
    dplyr::mutate(across(where(is.character), tolower))
}

# Generate pipeline from YAML
create_pipeline_from_yaml("pipeline.yml")
