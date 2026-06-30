# How yamltargets Works: A Detailed Guide

This document explains yamltargets step-by-step, with rationale for every design decision.

---

## Part 1: The Problem We're Solving

### Without yamltargets

```r
# _targets.R — hand-written, verbose
list(
  targets::tar_target_raw("raw_data", read_csv("data/input.csv", na = "NA")),
  targets::tar_target_raw("cleaned", clean_data(raw_data)),
  targets::tar_target_raw("save_cleaned", write_parquet(cleaned, "results/cleaned.parquet"))
)
```

### With yamltargets

```yaml
# pipeline.yml — declarative, readable
sources:
  - name: raw_data
    type: csv
    path: data/input.csv
    options:
      na: "NA"

transforms:
  - name: cleaned
    input: raw_data
    function: clean_data

outputs:
  - name: cleaned
    format: parquet
    path: results/
```

### Why This Matters

Non-technical users (data analysts, domain experts) can define pipelines in YAML without knowing R or targets internals. They declare *what* they want (load CSV, clean it, save result), not *how* (tar_target_raw syntax, symbol dependencies).

---

## Part 2: The Data Flow Pipeline

The package transforms YAML into a `{targets}` pipeline through four conceptual stages:

```
YAML File
    ↓
[1. read_pipeline_config()]  — Parse YAML into R list
    ↓
Raw R list (unvalidated)
    ↓
[2. validate_pipeline_config()]  — Check YAML schema + cross-references
    ↓
Validated R list
    ↓
[3. build_targets()]  — Generate tar_target_raw() objects
    ↓
Generated target list
    ↓
[4. validate_targets_pipeline()]  — Check target objects + DAG integrity
    ↓
targets-compatible list (for _targets.R)
```

`create_pipeline_from_yaml()` is the public API that orchestrates these stages. YAML validation happens before target construction. `{targets}` pipeline validation happens after target construction, when there are actual `tar_target` objects to inspect.

---

## Part 3: Stage 1 — Parsing YAML

**File:** `R/config-parser.R:read_pipeline_config()`

```r
read_pipeline_config <- function(config_path) {
  if (!is_scalar_character(config_path)) {
    targets::tar_throw_validate("'config_path' must be a single file path")
  }

  if (!file_test("-f", config_path)) {
    targets::tar_throw_validate(
      paste("Config file not found:", config_path)
    )
  }

  cfg <- tryCatch(
    yaml::read_yaml(config_path),
    error = function(error) {
      targets::tar_throw_validate(
        paste0(
          "Could not parse config file '",
          config_path,
          "': ",
          conditionMessage(error)
        )
      )
    }
  )

  targets::tar_assert_list(cfg, "Pipeline config must be a YAML list/object")
  cfg
}
```

### What Happens

1. Check that `config_path` is a single character value.
2. Check that it points to a file, not just any existing path.
3. Read YAML file using `yaml::read_yaml()` — converts YAML syntax to R lists/vectors.
4. Wrap YAML parser errors in a config-specific validation message.
5. Assert the result is a list (not scalar, vector, etc.).
6. Return the raw, unvalidated list.

### Rationale for Separate Validation

Parsing and validation are distinct concerns:
- **Parsing** handles syntax: Is it valid YAML?
- **Validation** handles semantics: Does it match our schema?

Keeping them separate makes the code easier to reason about and test.

### Example

Input YAML:
```yaml
sources:
  - name: raw_data
    type: csv
    path: data/input.csv
```

Becomes R list:
```r
list(
  sources = list(
    list(
      name = "raw_data",
      type = "csv",
      path = "data/input.csv"
    )
  )
)
```

---

## Part 4: Stage 2 — Validation

**File:** `R/config-parser.R:validate_pipeline_config()`

This stage checks that the parsed YAML has the expected structure and that references between sources, transforms, and outputs are valid. The main function is intentionally small: it delegates most checks to helper functions and then reports any accumulated errors together.

### Check 2a: Required Sections

The pipeline requires a top-level `sources` section. `validate_required_sections()` checks for that key and returns messages such as:

```text
Missing required key: 'sources'
```

`transforms` and `outputs` are optional, so source-only pipelines are valid.

**Rationale:** A pipeline must define input data, but not every pipeline needs transform or output steps. Required-section errors are collected with the rest of the validation errors so the user can fix multiple issues at once.

### Check 2b: Per-Item Validation

When present, each section must be a list of objects. Each object has required fields:

| Section | Required fields |
|---|---|
| `sources` | `name`, `type`, `path` |
| `transforms` | `name`, `input`, `function` |
| `outputs` | `name`, `format`, `path` |

The validator also checks that scalar fields such as `name`, `type`, `path`, `format`, and `function` are character values, that target names are syntactically valid, and that `options` and `params` are named lists when supplied.

The shared helper `validate_required_fields()` generates indexed messages like:

```text
sources[1]: missing 'name'
transforms[2]: missing 'function'
outputs[1]: missing 'path'
```

**Rationale for detailed error messages:** Each error includes the section and item index, so users know exactly which YAML entry needs attention.

### Check 2c: Supported Types and Formats

Source `type` values are validated against:

```text
csv, parquet, rds, file_read
```

File formats are validated against:

```text
csv, parquet, rds
```

The helper `validate_choice()` returns messages like:

```text
sources[1]: type 'json' not supported (use: csv, parquet, rds, file_read)
outputs[1]: format 'xlsx' not supported (use: csv, parquet, rds)
```

For `type: file_read`, the source must also include a `format` field so the package knows how to read the tracked file after `{targets}` detects changes.

### Check 2d: Duplicate and Invalid Target Names

The validator checks names at several levels:

```text
Duplicate source name: raw_data
Duplicate transform name: cleaned_data
Duplicate target name: save_cleaned
Duplicate generated target name: raw_data_file
Invalid target name: raw-data
```

Target names are normalized with `trimws()` before duplicate checks. This means `"raw"` and `" raw "` are treated as the same name.

**Rationale:** Duplicate or invalid names would create ambiguous target definitions or invalid dependency expressions. The generated names matter too: `type: file_read` creates a `<name>_file` target, and each output creates a `save_<name>` target.

### Check 2e: Cross-Reference Validation

The validator builds a set of defined names from source names and transform names using `extract_scalar_field()`. Missing, non-character, or non-scalar names are represented internally as `NA` and removed before reference checks.

Transform inputs must refer to a defined source or transform:

```text
transforms[1]: input 'raw_dta' not defined
```

Outputs must name a defined source or transform:

```text
outputs[1]: name 'cleaned_dta' not defined
```

**Rationale:** This catches typos *before* `tar_make()` runs. Without this validation, a misspelled input name would only fail when `{targets}` tries to evaluate the generated pipeline.

**Current behavior:** The defined-name set includes all sources and all transforms before reference checks. That means validation currently allows a transform to reference a transform listed later in the YAML. The generated target graph may still be valid because `{targets}` resolves dependencies from the generated expressions, but if the intended design is strictly sequential YAML, this validation could be tightened later.

### Final Step: Collect and Report All Errors

After all checks run, `throw_config_errors()` reports accumulated errors with `targets::tar_throw_validate()`:

```text
Invalid pipeline configuration:
  sources[1]: missing 'name'
  sources[1]: type 'json' not supported (use: csv, parquet, rds, file_read)
```

**Rationale for `tar_throw_validate()`:** This is the idiomatic `{targets}` way to report validation errors. It signals to users that the problem is a configuration issue, not a runtime failure.

---

## Part 5: Stage 3 — Target Building

**File:** `R/target-builder.R:build_targets()`

This is where YAML becomes executable R code.

### Entry Point

```r
build_targets <- function(config, validate_targets = TRUE) {
  targets_list <- list()

  # Process sources, transforms, outputs in order
  # Each produces 1+ targets

  if (isTRUE(validate_targets)) {
    validate_targets_pipeline(targets_list)
  }

  targets_list
}
```

**Why process in order?**
- Sources must come first (they're inputs)
- Transforms depend on sources/earlier transforms
- Outputs depend on transforms
- This matches the logical flow of data through the pipeline

The `validate_targets` argument controls post-build `{targets}` validation. It is enabled by default in `create_pipeline_from_yaml()` so the generated target list is checked before being returned to `_targets.R`.

### Building Source Targets

```r
if (!is.null(config$sources)) {
  source_targets <- lapply(config$sources, build_source_target)
  targets_list <- c(targets_list, unlist(source_targets, recursive = FALSE))
}
```

**Rationale for consistent list returns:**
- Normal sources (`csv`, `parquet`, `rds`) return a named list containing one target.
- `file_read` sources return a named list containing two targets: file tracker + reader.
- Because every source builder returns a list, `build_targets()` can flatten source targets uniformly instead of checking object classes.

---

### Deep Dive: build_source_target()

This is where the magic happens.

#### For Standard Types (csv, parquet, rds)

```r
if (!identical(source$type, "file_read")) {
  loader_fn <- get_loader_function(source$type)
  result <- list(targets::tar_target_raw(
    name = name_to_use,
    command = build_loader_call(loader_fn, source)
  ))
  names(result) <- name_to_use
  result
}
```

#### Example with Concrete Input

```yaml
sources:
  - name: raw_data
    type: csv
    path: data/input.csv
    options:
      na: "NA"
```

**Step 1: Get loader function**
```r
loader_fn <- get_loader_function("csv")
# Returns: "read_csv"
```

**Step 2: Build the call expression**
```r
call_expr <- build_loader_call("read_csv", source)
# Inside build_loader_call:
call_args <- list(file = "data/input.csv")
if (!is.null(source$options)) {
  call_args <- c(call_args, list(na = "NA"))
}
rlang::call2("read_csv", !!!call_args)
# Returns unevaluated call: read_csv(file = "data/input.csv", na = "NA")
```

#### Why Use `rlang::call2()` and `!!!` (Splice)?

Instead of:
```r
# DON'T DO THIS:
expr <- quote(read_csv(file = "data/input.csv", na = "NA"))
```

We do:
```r
# DO THIS:
call_args <- list(file = "data/input.csv", na = "NA")
rlang::call2("read_csv", !!!call_args)
```

**Rationale:** In YAML, we don't know how many options users will specify. Using `call2()` + `!!!` lets us dynamically build the call with any number of arguments. `!!!` (splice) unpacks the list into function arguments.

**Step 3: Create target**
```r
targets::tar_target_raw(
  name = "raw_data",
  command = read_csv(file = "data/input.csv", na = "NA")
)
```

#### Why `tar_target_raw()` Instead of `tar_target()`?

The target name comes from YAML (a string). If we use `tar_target()`:
```r
# DON'T DO THIS:
tar_target(name = rlang::sym("raw_data"), command = read_csv(...))
# Error: rlang::sym() doesn't accept externally-sourced strings safely
```

But `tar_target_raw()` accepts strings directly:
```r
# DO THIS:
tar_target_raw(name = "raw_data", command = read_csv(...))
```

**Rationale:** 
- `tar_target()` is for interactive use (you write the name as a symbol)
- `tar_target_raw()` is for programmatic generation (name is a string from external data)

---

### Deep Dive: file_read Type (Two-Target Pattern)

```r
if (identical(source$type, "file_read")) {
  name_file <- paste0(name_to_use, "_file")
  loader_fn <- get_loader_function(source$format)
  read_args <- append_call_args(
    list(file = rlang::sym(name_file)),
    source$options
  )

  result <- list(
    targets::tar_target_raw(
      name = name_file,
      command = rlang::call2(base::identity, source$path),
      format = "file"
    ),
    targets::tar_target_raw(
      name = name_to_use,
      command = rlang::call2(loader_fn, !!!read_args)
    )
  )
  names(result) <- c(name_file, name_to_use)
  return(result)
}
```

#### Example with YAML

```yaml
sources:
  - name: raw_data
    type: file_read
    format: csv
    path: data/input.csv
```

#### Generates

**Target 1 (file tracker):**
```r
tar_target_raw(
  name = "raw_data_file",
  command = identity("data/input.csv"),
  format = "file"
)
```

**What is `format = "file"`?** This tells targets to:
1. Expect the command to return a file path
2. Monitor that file for changes (using content hash)
3. If the file changes, mark downstream targets as outdated

**Target 2 (reader):**
```r
tar_target_raw(
  name = "raw_data",
  command = read_csv(file = raw_data_file)
)
```

#### The Key Detail

`rlang::sym(name_file)` creates a symbol reference to `raw_data_file`. This tells targets: "This target depends on raw_data_file." targets sees this through static code analysis.

#### Why Two Targets?

**Without separation:**
```r
tar_target_raw("raw_data", read_csv("data/input.csv"))
```
If the file changes, targets has no way to know. It only checks if dependencies (other targets) change.

**With separation:**
```r
# Target 1: Watches the file
tar_target_raw("raw_data_file", identity("data/input.csv"), format = "file")

# Target 2: Depends on Target 1
tar_target_raw("raw_data", read_csv(file = raw_data_file))
```

If the file changes:
1. Target 1 detects it (format="file" monitors the file)
2. Target 1 becomes outdated
3. Target 2 depends on Target 1, so it also becomes outdated
4. Both re-run

---

### Building Transform Targets

```r
if (!is.null(config$transforms)) {
  for (trn in config$transforms) {
    target <- build_transform_target(trn)
    targets_list[[trn$name]] <- target
  }
}
```

```r
build_transform_target <- function(transform) {
  fn_name <- transform$`function`  # backticks because "function" is reserved
  input_names <- trimws(as.character(transform$input))
  
  # Build positional arguments
  call_args <- lapply(input_names, rlang::sym)
  
  if (!is.null(transform$params)) {
    call_args <- c(call_args, transform$params)
  }
  
  call_expr <- rlang::call2(fn_name, !!!call_args)
  
  targets::tar_target_raw(
    name = trimws(as.character(transform$name)),
    command = call_expr
  )
}
```

#### Example

```yaml
transforms:
  - name: cleaned
    input: raw_data
    function: clean_data
    params:
      remove_na: true
```

**Step by step:**
1. `fn_name` = "clean_data"
2. `input_names` = c("raw_data")
3. `call_args` = list(rlang::sym("raw_data")) = list of 1 symbol
4. Add params: `call_args` = list(rlang::sym("raw_data"), remove_na = TRUE)
5. Build call: `rlang::call2("clean_data", !!!call_args)`
   - Expands to: `clean_data(raw_data, remove_na = TRUE)`
6. Create target:
   ```r
   tar_target_raw("cleaned", clean_data(raw_data, remove_na = TRUE))
   ```

#### Rationale for Positional Arguments

YAML doesn't know parameter names. So we pass inputs as positional args and let the R function receive them as its first argument(s):

```r
# YAML:
transforms:
  - input: raw_data
    function: clean_data

# Generates:
clean_data(raw_data)

# R function:
clean_data <- function(df, remove_na = FALSE) { ... }
# df receives raw_data
```

---

### Building Output Targets

```r
if (!is.null(config$outputs)) {
  output_targets <- lapply(config$outputs, build_output_target)
  names(output_targets) <- vapply(config$outputs, function(output) {
    paste0("save_", normalize_name(output$name))
  }, character(1))
  targets_list <- c(targets_list, output_targets)
}
```

```r
build_output_target <- function(output) {
  save_fn <- get_save_function(output$format)
  output_name <- normalize_name(output$name)
  output_path <- build_output_path(
    path = output$path,
    name = output_name,
    format = output$format
  )

  call_expr <- rlang::call2(
    save_fn,
    x = rlang::sym(output_name),
    file = output_path
  )

  targets::tar_target_raw(
    name = paste0("save_", output_name),
    command = call_expr,
    format = "file"
  )
}
```

#### Example

```yaml
outputs:
  - name: cleaned_data
    format: parquet
    path: results/
```

**Generates:**
```r
tar_target_raw(
  name = "save_cleaned_data",
  command = write_parquet(
    x = cleaned_data,
    file = "results/cleaned_data.parquet"
  ),
  format = "file"
)
```

#### Rationale for `save_` Prefix

Distinguishes output targets from data targets:
- `cleaned_data` — the actual cleaned data (created by transform)
- `save_cleaned_data` — the action of saving it (depends on `cleaned_data`)

This makes the pipeline DAG clear: transforms produce data, output targets consume that data and return the written file path. Because output targets use `format = "file"`, `{targets}` tracks the output artifact itself.

---

## Part 6: Stage 4 — Post-Build `{targets}` Validation

**File:** `R/target-builder.R:validate_targets_pipeline()`

After `build_targets()` constructs the list of `tar_target` objects, `validate_targets_pipeline()` asks `{targets}` to validate the generated pipeline structure.

```r
validate_targets_pipeline <- function(targets_list) {
  pipeline_from_list <- get(
    "pipeline_from_list",
    envir = asNamespace("targets")
  )
  pipeline_validate <- get("pipeline_validate", envir = asNamespace("targets"))

  tryCatch(
    {
      pipeline <- pipeline_from_list(targets_list)
      pipeline_validate(pipeline)
    },
    error = function(error) {
      targets::tar_throw_validate(
        paste0(
          "Generated targets pipeline failed {targets} validation: ",
          conditionMessage(error)
        )
      )
    }
  )

  invisible(TRUE)
}
```

### What This Checks

This step delegates target-level integrity checks to `{targets}`, including target object validity, target settings, name conflicts, dependency graph structure, and DAG validity.

### Why This Is Separate From YAML Validation

`validate_pipeline_config()` validates the declarative YAML contract: required fields, supported source/output formats, `file_read` requirements, named `options`/`params`, cross-references, and generated names such as `save_<name>` and `<name>_file`.

`validate_targets_pipeline()` validates the constructed `{targets}` pipeline after that YAML has been translated into target objects. It should not replace YAML validation because `{targets}` does not know the `yamltargets` schema or naming conventions.

### Why Use an Isolated Helper

The public `{targets}` validation function, `targets::tar_validate()`, validates a target script such as `_targets.R`. `yamltargets` builds an in-memory list of targets, so direct post-build validation uses lower-level `{targets}` functions obtained from the namespace. Keeping this logic in one helper isolates that dependency and makes future changes easier if `{targets}` exposes a public list-based validator.

---

## Part 7: Public API

**File:** `R/api.R`

```r
create_pipeline_from_yaml <- function(config_path, validate_targets = TRUE) {
  config <- read_pipeline_config(config_path)
  validate_pipeline_config(config)
  build_targets(config, validate_targets = validate_targets)
}

validate_pipeline <- function(config_path) {
  config <- read_pipeline_config(config_path)
  validate_pipeline_config(config)
  invisible(TRUE)
}
```

### Rationale

Two entry points for different use cases:
- `validate_pipeline("pipeline.yml")` — Check if YAML is valid (no building)
- `create_pipeline_from_yaml("pipeline.yml")` — Validate YAML, build targets, then validate the generated `{targets}` pipeline
- `create_pipeline_from_yaml("pipeline.yml", validate_targets = FALSE)` — Build targets without the post-build `{targets}` validation step

### Usage in _targets.R

```r
library(targets)
library(yamltargets)

source("R/functions.R")

yamltargets::create_pipeline_from_yaml("pipeline.yml")
```

This gives users a one-liner in _targets.R. The function already returns a list of target objects, so it should be the return value of the script rather than wrapped in another `list()`. The complexity is hidden in the pipeline.yml config. For script-based workflows, users can still run `targets::tar_validate()` on `_targets.R`; the internal post-build validation exists so `yamltargets` can check the generated in-memory target list before returning it.

---

## Part 8: Key Design Principles

### 1. YAML Validation is Separate from Target Generation

If YAML validation fails, we never attempt to build targets. This prevents partial/incorrect pipelines from being created.

Post-build `{targets}` validation is a separate layer: it runs after target generation and checks whether the generated target objects form a valid `{targets}` pipeline.

### 2. Errors Include Context

```
Invalid pipeline configuration:
  sources[1]: missing 'type'
  transforms[2]: input 'raw_dta' not defined
```

Not:
```
Invalid pipeline configuration
```

**Rationale:** Users need to find and fix the problem. Including item indices (1-based, R convention) and field names makes it actionable.

### 3. Names Are Strings, Not Symbols

We use `tar_target_raw(name = "string", ...)` because names come from YAML (external data). This is safer than trying to convert strings to symbols.

### 4. Dependencies Are Explicit Symbols

In transform commands, we use `rlang::sym()` to reference other targets:
```r
tar_target_raw("cleaned", clean_data(raw_data))
```

Not:
```r
tar_target_raw("cleaned", clean_data("raw_data"))  # String, not symbol!
```

**Rationale:** targets performs static code analysis to find dependencies. It looks for symbol references, not string literals. `raw_data` (symbol) tells targets about the dependency. `"raw_data"` (string) is just data.

### 5. Native File Tracking

The `file_read` pattern uses `{targets}` native `format = "file"` instead of reimplementing change detection. Output save targets also use `format = "file"` and writer helpers return the written path, so generated artifacts are tracked as files.

---

## Part 9: Example Walkthrough

Let's trace a complete pipeline:

```yaml
# pipeline.yml
sources:
  - name: raw_data
    type: file_read
    format: csv
    path: data/input.csv

transforms:
  - name: cleaned
    input: raw_data
    function: clean_data

outputs:
  - name: cleaned
    format: parquet
    path: results/
```

### Step 1: Parse

```r
config <- read_pipeline_config("pipeline.yml")
# Returns:
# list(
#   sources = list(list(
#     name = "raw_data",
#     type = "file_read",
#     format = "csv",
#     path = "data/input.csv"
#   )),
#   transforms = list(list(
#     name = "cleaned",
#     input = "raw_data",
#     `function` = "clean_data"
#   )),
#   outputs = list(list(
#     name = "cleaned",
#     format = "parquet",
#     path = "results/"
#   ))
# )
```

### Step 2: Validate

```r
validate_pipeline_config(config)
# Checks:
# - sources present? ✓
# - sources, transforms, and outputs are lists of objects? ✓
# - target names are valid and unique? ✓
# - type=file_read has format? ✓ (format="csv")
# - transform input="raw_data" defined? ✓ (source raw_data exists)
# - output name="cleaned" defined? ✓ (transform cleaned exists)
```

### Step 3: Build and Validate Generated Targets

```r
targets_list <- build_targets(config)
```

**Processing sources:**
- `type="file_read"` → returns 2 targets
  1. `raw_data_file` = tar_target_raw("raw_data_file", identity("data/input.csv"), format="file")
  2. `raw_data` = tar_target_raw("raw_data", read_csv(file=raw_data_file))

**Processing transforms:**
- input="raw_data" → `rlang::sym("raw_data")`
- function="clean_data" → fn_name
- Generates: tar_target_raw("cleaned", clean_data(raw_data))

**Processing outputs:**
- name="cleaned" → `x = rlang::sym("cleaned")`
- format="parquet" → `write_parquet`
- output writer returns the file path invisibly
- Generates: `tar_target_raw("save_cleaned", write_parquet(x = cleaned, file = "results/cleaned.parquet"), format = "file")`

**Post-build validation:**
- Converts the generated list to a `{targets}` pipeline object
- Delegates target object and DAG checks to `{targets}`
- Returns the target list only if `{targets}` accepts the generated structure

### Step 4: Result

```r
list(
  raw_data_file = tar_target(...),
  raw_data = tar_target(...),
  cleaned = tar_target(...),
  save_cleaned = tar_target(...)
)
```

### Dependency Graph

```
raw_data_file (watches data/input.csv)
       ↓
    raw_data (reads using raw_data_file)
       ↓
    cleaned (transforms raw_data)
       ↓
 save_cleaned (saves cleaned)
```

When data/input.csv changes:
1. raw_data_file detects change (format="file")
2. raw_data becomes outdated (depends on raw_data_file)
3. cleaned becomes outdated (depends on raw_data)
4. save_cleaned becomes outdated (depends on cleaned)
5. Next tar_make() reruns all four targets

---

## Summary

### The Elegance of yamltargets

- Users describe *what* (YAML)
- Package figures out *how* (targets internals)
- No targets knowledge required

### Key Architectural Insights

1. **Separate parsing from validation** — Syntax errors vs. semantic errors are different problems
2. **Use `tar_target_raw()` for programmatic generation** — Safer than trying to convert external strings to symbols
3. **Use symbols for dependencies, strings for names** — targets does static analysis looking for symbols
4. **Adopt targets' native patterns** — Use `format = "file"` for tracked input and output files
5. **Two-target pattern enables input file tracking** — Separates concerns (file monitoring vs. data reading)
6. **Validate cross-references upfront** — Give immediate feedback, catch typos before tar_make()
7. **Validate target names upfront** — Catch duplicate, generated, and syntactically invalid names before target construction
8. **Delegate target-level validation to `{targets}`** — Use `{targets}` after construction to check target objects and DAG integrity
9. **Include context in error messages** — Array indices and field names help users fix problems fast

---

## File Organization

- **`R/api.R`** — Public entry points (create_pipeline_from_yaml, validate_pipeline)
- **`R/config-parser.R`** — Parse YAML and validate schema + cross-references
- **`R/target-builder.R`** — Generate tar_target_raw objects from validated config and run post-build `{targets}` validation
- **`R/loaders.R`** — Built-in reader functions for CSV, Parquet, RDS
- **`R/utils.R`** — Writer functions and output-directory creation

---

## Testing Strategy

Each layer has corresponding tests:
- `test-api.R` — Public API behavior
- `test-config-parser.R` — YAML parsing, validation, cross-references
- `test-target-builder.R` — Target generation for each source/transform/output type and post-build `{targets}` validation

This makes it easy to understand what each layer does and verify it works correctly.
