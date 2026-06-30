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

The package transforms data through five stages:

```
YAML File
    ↓
[1. read_pipeline_config()]  — Parse YAML into R list
    ↓
Raw R list (unvalidated)
    ↓
[2. validate_pipeline_config()]  — Check schema + cross-references
    ↓
Validated R list
    ↓
[3. build_targets()]  — Generate tar_target_raw() objects
    ↓
List of tar_target objects
    ↓
[4. create_pipeline_from_yaml()]  — Public API orchestrator
    ↓
targets-compatible list (for _targets.R)
```

---

## Part 3: Stage 1 — Parsing YAML

**File:** `R/config-parser.R:read_pipeline_config()`

```r
read_pipeline_config <- function(config_path) {
  if (!file.exists(config_path)) {
    targets::tar_throw_validate(
      paste("Config file not found:", config_path)
    )
  }
  cfg <- yaml::read_yaml(config_path)
  targets::tar_assert_list(cfg, "Pipeline config must be a YAML list/object")
  cfg
}
```

### What Happens

1. Read YAML file using `yaml::read_yaml()` — converts YAML syntax to R lists/vectors
2. Assert the result is a list (not scalar, vector, etc.)
3. Return the raw, unvalidated list

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

This function does **three types of checks**:

### Check 2a: Required Sections

```r
if (is.null(config$sources)) {
  errors <- c(errors, "Missing required key: 'sources'")
}
if (is.null(config$transforms)) {
  errors <- c(errors, "Missing required key: 'transforms'")
}
```

**Rationale:** A pipeline must have at least sources (input data) and transforms (what to do with it). If missing, fail fast with a clear error.

### Check 2b: Per-Item Validation

For each source:
```r
for (i in seq_along(config$sources)) {
  src <- config$sources[[i]]
  if (is.null(src$name)) {
    errors <- c(errors, sprintf("sources[%d]: missing 'name'", i))
  }
  if (is.null(src$type)) {
    errors <- c(errors, sprintf("sources[%d]: missing 'type'", i))
  }
  valid_types <- c("csv", "parquet", "rds", "file_read")
  if (!is.null(src$type)) {
    targets::tar_assert_in(src$type, valid_types, ...)
  }
  
  # file_read requires format field
  if (!is.null(src$type) && src$type == "file_read") {
    if (is.null(src$format)) {
      errors <- c(errors, 
        sprintf("sources[%d]: missing 'format'", i))
    } else {
      valid_formats <- c("csv", "parquet", "rds")
      targets::tar_assert_in(src$format, valid_formats, ...)
    }
  }
}
```

**Rationale for detailed error messages:** Each error includes the item index (`sources[1]`) so users know exactly which item in their YAML is wrong.

**Rationale for nesting the file_read check:** Only check for `format` if `type` is present. This prevents null-pointer-like errors.

### Check 2c: Cross-Reference Validation

```r
# Build set of defined names (sources, then transforms in order)
defined_names <- character(0)
if (!is.null(config$sources)) {
  defined_names <- c(defined_names,
    vapply(config$sources, function(x) x$name %||% "", character(1)))
}
if (!is.null(config$transforms)) {
  defined_names <- c(defined_names,
    vapply(config$transforms, function(x) x$name %||% "", character(1)))
}

# Check transform inputs reference defined targets
if (!is.null(config$transforms)) {
  for (i in seq_along(config$transforms)) {
    trn <- config$transforms[[i]]
    if (!is.null(trn$input)) {
      for (inp in as.character(trn$input)) {
        if (!inp %in% defined_names) {
          errors <- c(errors,
            sprintf("transforms[%d]: input '%s' not defined", i, inp))
        }
      }
    }
  }
}

# Check output names reference defined targets
if (!is.null(config$outputs)) {
  for (i in seq_along(config$outputs)) {
    out <- config$outputs[[i]]
    if (!is.null(out$name) && !out$name %in% defined_names) {
      errors <- c(errors,
        sprintf("outputs[%d]: name '%s' not defined", i, out$name))
    }
  }
}
```

**Rationale:** This catches typos *before* tar_make() runs. Without this validation, a user writes:

```yaml
transforms:
  - name: cleaned
    input: raw_dta  # typo!
    function: clean_data
```

The error only surfaces when tar_make() runs and can't find `raw_dta`. By validating upfront, we give immediate feedback.

**Why build `defined_names` by order?** A transform can reference:
- Sources (defined first)
- Earlier transforms (defined in order)

So we accumulate names as we go. Transform 2 can reference Transform 1, but Transform 1 cannot reference Transform 2.

### Final Step: Collect and Report All Errors

```r
if (length(errors) > 0) {
  error_msg <- paste(c("Invalid pipeline configuration:", errors), 
    collapse = "\n  ")
  targets::tar_throw_validate(error_msg)
}
invisible(TRUE)
```

**Rationale for `tar_throw_validate()`:** This is the idiomatic targets way to report validation errors. It signals to users "this is a configuration error, not a runtime error."

---

## Part 5: Stage 3 — Target Building

**File:** `R/target-builder.R:build_targets()`

This is where YAML becomes executable R code.

### Entry Point

```r
build_targets <- function(config) {
  targets_list <- list()
  
  # Process sources, transforms, outputs in order
  # Each produces 1+ targets
  
  targets_list
}
```

**Why process in order?**
- Sources must come first (they're inputs)
- Transforms depend on sources/earlier transforms
- Outputs depend on transforms
- This matches the logical flow of data through the pipeline

### Building Source Targets

```r
if (!is.null(config$sources)) {
  for (src in config$sources) {
    target <- build_source_target(src)
    
    # Handle tracked sources that return a list of 2 targets
    if (is.list(target) && !inherits(target, "tar_target")) {
      targets_list <- c(targets_list, target)  # Flatten list
    } else {
      targets_list[[src$name]] <- target  # Single target
    }
  }
}
```

**Rationale for the if/else:**
- Normal sources (csv, parquet, rds) return 1 tar_target object
- file_read sources return a list of 2 tar_target objects (file tracker + reader)
- We need to handle both cases, so we check `!inherits(target, "tar_target")`

---

### Deep Dive: build_source_target()

This is where the magic happens.

#### For Standard Types (csv, parquet, rds)

```r
if (source$type != "file_read") {
  loader_fn <- get_loader_function(source$type)
  call_expr <- build_loader_call(loader_fn, source)
  
  targets::tar_target_raw(
    name = name_to_use,
    command = call_expr
  )
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
if (source$type == "file_read") {
  name_file <- paste0(name_to_use, "_file")
  loader_fn <- get_loader_function(source$format)
  
  # TARGET 1: Track file changes
  file_target <- targets::tar_target_raw(
    name = name_file,
    command = rlang::call2("identity", source$path),
    format = "file"
  )
  
  # TARGET 2: Read file
  read_args <- list(file = rlang::sym(name_file))
  if (!is.null(source$options)) {
    read_args <- c(read_args, source$options)
  }
  read_target <- targets::tar_target_raw(
    name = name_to_use,
    command = rlang::call2(loader_fn, !!!read_args)
  )
  
  result <- list(file_target, read_target)
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
  for (out in config$outputs) {
    target <- build_output_target(out)
    targets_list[[paste0("save_", out$name)]] <- target
  }
}
```

```r
build_output_target <- function(output) {
  save_fn <- get_save_function(output$format)
  output_name <- trimws(output$name)
  filename <- paste0(output_name, ".", tolower(output$format))
  output_path <- file.path(output$path, filename)
  
  call_expr <- rlang::call2(
    save_fn,
    x = as.symbol(output_name),
    file = output_path
  )
  
  targets::tar_target_raw(
    name = paste0("save_", output_name),
    command = call_expr
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
  command = write_parquet(x = cleaned_data, 
    file = "results/cleaned_data.parquet")
)
```

#### Rationale for `save_` Prefix

Distinguishes output targets from data targets:
- `cleaned_data` — the actual cleaned data (created by transform)
- `save_cleaned_data` — the action of saving it (depends on `cleaned_data`)

This makes the pipeline DAG clear: transforms produce data, output targets consume that data.

---

## Part 6: Stage 4 — Public API

**File:** `R/api.R`

```r
create_pipeline_from_yaml <- function(yaml_path) {
  config <- read_pipeline_config(yaml_path)
  validate_pipeline_config(config)
  build_targets(config)
}

validate_pipeline <- function(yaml_path) {
  config <- read_pipeline_config(yaml_path)
  validate_pipeline_config(config)
  invisible(TRUE)
}
```

### Rationale

Two entry points for different use cases:
- `validate_pipeline("pipeline.yml")` — Check if YAML is valid (no building)
- `create_pipeline_from_yaml("pipeline.yml")` — Build targets for _targets.R

### Usage in _targets.R

```r
library(targets)
library(yamltargets)

source("R/functions.R")

list(
  yamltargets::create_pipeline_from_yaml("pipeline.yml")
)
```

This gives users a one-liner in _targets.R. The complexity is hidden in the pipeline.yml config.

---

## Part 7: Key Design Principles

### 1. Validation is Separate from Generation

If validation fails, we never attempt to build targets. This prevents partial/incorrect pipelines from being created.

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

### 5. Two-Target Pattern for File Tracking

The file_read pattern uses targets' native `format="file"` instead of reimplementing change detection. This is robust and follows targets best practices.

---

## Part 8: Example Walkthrough

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
# - sources, transforms present? ✓
# - type=file_read has format? ✓ (format="csv")
# - transform input="raw_data" defined? ✓ (source raw_data exists)
# - output name="cleaned" defined? ✓ (transform cleaned exists)
```

### Step 3: Build

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
- name="cleaned" → x=as.symbol("cleaned")
- format="parquet" → write_parquet
- Generates: tar_target_raw("save_cleaned", write_parquet(x=cleaned, file="results/cleaned.parquet"))

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
4. **Adopt targets' native patterns** — format="file" for file tracking, not custom reimplementation
5. **Two-target pattern enables proper change tracking** — Separates concerns (file monitoring vs. data reading)
6. **Validate cross-references upfront** — Give immediate feedback, catch typos before tar_make()
7. **Include context in error messages** — Array indices and field names help users fix problems fast

---

## File Organization

- **`R/api.R`** — Public entry points (create_pipeline_from_yaml, validate_pipeline)
- **`R/config-parser.R`** — Parse YAML and validate schema + cross-references
- **`R/target-builder.R`** — Generate tar_target_raw objects from validated config
- **`R/loaders.R`** — Built-in read/write functions for CSV, Parquet, RDS
- **`R/utils.R`** — Helper functions (name validation, directory creation)

---

## Testing Strategy

Each layer has corresponding tests:
- `test-api.R` — Public API behavior
- `test-config-parser.R` — YAML parsing, validation, cross-references
- `test-target-builder.R` — Target generation for each source/transform/output type

This makes it easy to understand what each layer does and verify it works correctly.
