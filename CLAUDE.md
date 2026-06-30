# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

**yamltargets** is an R package that extends `targets` with declarative YAML configuration. Users define pipelines in YAML rather than hand-writing `_targets.R`. The package is part of the targetopia ecosystem and aims to be published to CRAN.

See `PACKAGE_VISION.md` for the full roadmap, scope, and design philosophy.

---

## Development Workflow

### Common Commands

```r
# Load package for interactive development
devtools::load_all()

# Install locally (needed for tar_make() subprocess to pick up changes)
devtools::install()

# Rebuild documentation from roxygen2 comments
devtools::document()

# Run all tests
devtools::test()

# Run a single test file
devtools::test_file("tests/testthat/test-api.R")

# Run tests matching a pattern
devtools::test_coverage()

# Check package for issues
devtools::check()
```

### Working with YAML Pipelines

```r
# In R console (after devtools::load_all()):
config <- read_pipeline_config("pipeline.yml")
validate_pipeline_config(config)

# Or use the public API:
validate_pipeline("pipeline.yml")
```

---

## Code Architecture

The package follows a clear data flow from YAML to executable targets:

```
YAML file
    ↓
[config-parser.R] — read_pipeline_config(), validate_pipeline_config()
    ↓
Validated config (list)
    ↓
[target-builder.R] — build_targets(), build_source_target(), build_transform_target(), etc.
    ↓
tar_target_raw() objects (list)
    ↓
[api.R] — create_pipeline_from_yaml() — returns list of targets for _targets.R
```

### Module Responsibilities

**`api.R`** — Public API
- `create_pipeline_from_yaml()` — Main entry point; orchestrates parsing, validation, and building
- `validate_pipeline()` — Public validation function (used before running tar_make)

**`config-parser.R`** — YAML parsing and validation
- `read_pipeline_config()` — Reads YAML and parses into R list (using yaml::read_yaml)
- `validate_pipeline_config()` — Schema validation (checks required fields, types, duplicates)
- Trims whitespace from names to prevent symbol creation errors

**`target-builder.R`** — Generates tar_target() calls
- `build_targets()` — Main orchestrator; iterates through sources, transforms, outputs
- `build_source_target()` — Creates loader targets (e.g., tar_target_raw("raw_data", read_csv(...)))
- `build_transform_target()` — Creates transform targets (passes inputs as positional args)
- `build_output_target()` — Creates save targets (e.g., tar_target_raw("save_cleaned_data", ...))
- **Key detail:** Uses `tar_target_raw(name = string, command = expr)` not `tar_target(name = symbol)` because names come from external data (YAML)

**`loaders.R`** — Built-in file I/O functions
- `read_csv()`, `read_parquet()`, `read_rds()` — Loaders (call readr, arrow, base R functions)
- `write_csv()`, `write_parquet()`, `save_rds()` — Writers (exported; users can call them or reference in YAML)
- All writers call `ensure_dir()` to create output directories

**`utils.R`** — Helpers
- `is_valid_symbol()` — Validates R symbol names (letters, numbers, dots, underscores; starts with letter/dot)
- `sanitize_name()` — Trims whitespace from YAML-parsed names
- `ensure_dir()` — Creates directories as needed for output files

---

## Key Design Decisions

### 1. Using `tar_target_raw()` Instead of `tar_target()`

Target names come from YAML strings. Using `tar_target(name = as.symbol(name_string))` failed because `rlang::sym()` has strict validation when called with externally-sourced strings. 

**Solution:** Use `tar_target_raw(name = name_string, command = expr)`, which accepts strings directly. This is cleaner for programmatic target generation.

### 2. Transform Function Arguments as Positional, Not Named

When a transform has `input: raw_data` and calls `function: clean_data`, we generate:
```r
tar_target_raw("cleaned", clean_data(raw_data))  # positional arg
```

Not:
```r
tar_target_raw("cleaned", clean_data(raw_data = raw_data))  # named arg
```

This is flexible: `clean_data(df)` receives the first positional argument. YAML doesn't specify parameter names, so named args would require schema changes (Phase 2).

### 3. Name Sanitization at Parse Time

YAML parsers sometimes preserve whitespace (e.g., "raw_data " with trailing space). To prevent "not a valid symbol" errors, `read_pipeline_config()` sanitizes names via `trimws()` before validation.

### 4. Convention: Input Dependencies Are Single Values or Lists

In the YAML, `input: raw_data` is converted to a character vector by the YAML parser. The config parser normalizes this to ensure consistency. Transforms are designed to accept ordered positional arguments matching the order of inputs in the YAML.

### 5. File Tracking: Two-Target Pattern from tarchetypes

Sources with `type: file_read` generate two targets following the tarchetypes `tar_file_read()` pattern:

```yaml
sources:
  - name: raw_data
    type: file_read
    format: csv
    path: data/input.csv
```

Generates:
```r
# Target 1: tracks file changes via format="file"
tar_target_raw("raw_data_file", identity("data/input.csv"), format = "file")

# Target 2: reads file using path from Target 1
tar_target_raw("raw_data", read_csv(file = raw_data_file))
```

**Why this approach?**
- Uses targets' built-in `format="file"` mechanism for automatic file change detection
- Two-target separation ensures proper invalidation of downstream targets
- Symbol reference (`raw_data_file`) creates dependency automatically
- Rest of pipeline uses `input: raw_data` unchanged (the second target name)
- No external dependencies — purely targets' native functionality

---

## Testing

Tests are organized by module:

- `test-api.R` — Public API (create_pipeline_from_yaml, validate_pipeline)
- `test-config-parser.R` — YAML parsing and validation
- `test-target-builder.R` — Target generation logic
- `setup.R` — Shared test utilities

**Run a single test file:**
```r
devtools::test_file("tests/testthat/test-config-parser.R")
```

**Example test pattern:**
```r
test_that("describe what should happen", {
  # Create temp YAML
  yaml_file <- withr::local_file(tempfile(fileext = ".yml"))
  writeLines(yaml_content, yaml_file)
  
  # Test behavior
  expect_error(validate_pipeline(yaml_file), "expected message")
  # or
  expect_no_error(create_pipeline_from_yaml(yaml_file))
})
```

Use `withr::local_file()` for test cleanup (file auto-deletes after test).

---

## Example Pipelines

Working examples in `inst/examples/simple-etl/`:
- `pipeline.yml` — Basic YAML config (CSV → clean → Parquet)
- `pipeline-tracked.yml` — File tracking example (`type=file_read` detects file changes)
- `_targets.R` — Minimal _targets.R file
- `data/input.csv` — Sample data
- `R/functions.R` — Transform functions

To test locally:
```bash
cd inst/examples/simple-etl
R
> devtools::load_all("../../..")  # Load yamltargets from repo root
> tar_make()                      # Uses pipeline.yml by default
```

For file tracking example:
```bash
cd inst/examples/simple-etl
R
> devtools::load_all("../../..")
> tar_make(targets_file = "_targets_tracked.R")  # Or rename pipeline-tracked.yml → pipeline.yml
```

---

## Documentation

Roxygen2 comments (in R files) generate:
- Function documentation (man/*.Rd)
- NAMESPACE imports/exports

**Rebuild docs:**
```r
devtools::document()
```

**Convention:** Exported functions (@export) have user-facing docs. Internal functions (@keywords internal) are brief.

---

## Phase 1 Scope (v1.0)

**Complete:**
- ✅ YAML parsing and validation
- ✅ Target generation (sources, transforms, outputs)
- ✅ Built-in loaders (CSV, Parquet, RDS)
- ✅ Public API
- ✅ Test suite
- ✅ File tracking (`type: file_read`) — automatic file change detection via targets' format="file"
- ✅ Cross-reference validation — catches undefined transform inputs and output names

**Remaining for v1.0 release:**
- Documentation improvements
- Edge case testing

See PACKAGE_VISION.md for Phase 2+ features (custom loaders, factories, etc.).

---

## Important Files

- `DESCRIPTION` — Package metadata, dependencies
- `NAMESPACE` — Exported functions and imports
- `PACKAGE_VISION.md` — Full roadmap and design philosophy
- `README.md` — User-facing quickstart
- `inst/examples/simple-etl/` — Minimal working example
