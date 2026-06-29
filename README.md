# yamltargets

<!-- badges: start -->
<!-- badges: end -->

Define `targets` data pipelines in YAML instead of hand-writing `_targets.R`.

Part of the [targetopia](https://wlandau.github.io/targetopia/packages.html) family.

## Installation

```r
# Install from GitHub
remotes::install_github("bkutlu/yamltargets")
```

## Quick Start

### 1. Write a pipeline configuration in YAML

**`pipeline.yml`:**
```yaml
name: "My Data Pipeline"

sources:
  - name: raw_data
    type: csv
    path: data/input.csv

transforms:
  - name: cleaned_data
    input: raw_data
    function: clean_data

outputs:
  - name: cleaned_data
    format: parquet
    path: results/
```

### 2. Define your transform functions

Write your transform functions and load them before calling `create_pipeline_from_yaml()`.

**`_targets.R`:**
```r
library(targets)
library(yamltargets)

tar_option_set(format = "parquet")

# Define or source your transform functions
clean_data <- function(df) {
  df |>
    dplyr::filter(!is.na(id)) |>
    dplyr::mutate(across(where(is.character), tolower))
}

# Generate pipeline from YAML
create_pipeline_from_yaml("pipeline.yml")
```

Or source functions from a separate file:
```r
# In _targets.R
source("functions.R")  # Contains clean_data, enrich_data, etc.
create_pipeline_from_yaml("pipeline.yml")
```

### 3. Run the pipeline

```r
tar_make()
```

## Why yamltargets?

- **Declarative**: Pipeline structure is in YAML, not buried in R code
- **Auditable**: Version-control friendly; easy to see what changed
- **Simple**: No complex R syntax; focus on domain logic
- **Targets-native**: Generates plain `tar_target()` calls; no hidden magic

## Supported File Types

| Type | Read | Write |
|------|------|-------|
| CSV | ✓ | ✓ |
| Parquet | ✓ | ✓ |
| RDS | ✓ | ✓ |

## API

### Main Functions

- `create_pipeline_from_yaml(config_path)` — Parse YAML and generate target definition objects
- `validate_pipeline(config_path)` — Validate YAML configuration without building targets

## Example Projects

See `inst/examples/` for working examples:
- `simple-etl/` — Load CSV, clean it, save as Parquet

## Learn More

- [YAML Configuration Reference](inst/schema/pipeline.json)
- [targetopia](https://wlandau.github.io/targetopia/) — Other targets extensions

## License

MIT
