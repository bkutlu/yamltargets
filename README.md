# yamltargets

Define `{targets}` target definitions in YAML, then use a minimal `_targets.R` file to run them.

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

For outputs, `path` is the output directory. The file name is generated as `<name>.<format>`, so this example writes `results/cleaned_data.parquet`.

### 2. Create `_targets.R`

Create a `_targets.R` file in the project root. Load packages, define or source your transform functions, then make the final expression call `create_pipeline_from_yaml()`.

**`_targets.R`:**
```r
library(targets)
library(yamltargets)

tar_option_set(format = "parquet")

clean_data <- function(df) {
  df |>
    dplyr::filter(!is.na(id)) |>
    dplyr::mutate(across(where(is.character), tolower))
}

create_pipeline_from_yaml("pipeline.yml")
```

For larger projects, put transform functions in a separate file and source it:
```r
library(targets)
library(yamltargets)

source("R/functions.R")

create_pipeline_from_yaml("pipeline.yml")
```

### 3. Run the pipeline

Run this from the project root:

```r
targets::tar_make()
```

## Why yamltargets?

- **Declarative**: Target definitions are in YAML, not buried in R code
- **Simple**: No complex R syntax; focus on domain logic in a modular fashion
- **Targets-native**: Generates `{targets}` target objects; no hidden magic

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

## Learn More

- [targetopia](https://wlandau.github.io/targetopia/) — Other targets extensions

## License

MIT
