# yamltargets: YAML-Driven Data Pipelines for targets

## Overview

`yamltargets` is a lightweight R package that extends `targets` with **declarative YAML configuration**, allowing users to define data pipelines without writing `_targets.R` by hand.

Part of the [targetopia](https://wlandau.github.io/targetopia/packages.html) family of targetopia packages.

**Core idea:** Separate pipeline structure (YAML) from domain logic (R functions). Users spend time on domain problems, not on targets plumbing.

**Audience:** Anyone using targets for multi-stage data pipelines (ETL, analysis, preprocessing).

---

## Problem It Solves

### Status Quo: targets requires hand-written code

Users write `_targets.R` by hand, which is:
- **Verbose** — 50+ lines for simple 5-step pipelines
- **Error-prone** — easy to typo target names, miss dependencies
- **Hard to audit** — pipeline structure is buried in R code
- **Repetitive** — similar patterns (load → clean → merge) repeated across projects

### Example: Simple 3-stage pipeline

**Current targets approach (_targets.R):**
```r
library(targets)
tar_option_set(format = "parquet")

list(
  tar_target(
    raw_data,
    read_csv("data/input.csv")
  ),
  tar_target(
    cleaned,
    clean_data(raw_data)
  ),
  tar_target(
    enriched,
    enrich_data(cleaned)
  ),
  tar_target(
    results,
    write_parquet(enriched, "results/final.parquet")
  )
)
```

**Equivalent configtargets approach (pipeline.yml):**
```yaml
name: "My Data Pipeline"

sources:
  - name: raw_data
    type: csv
    path: data/input.csv

transforms:
  - name: cleaned
    input: raw_data
    function: clean_data
    
  - name: enriched
    input: cleaned
    function: enrich_data

outputs:
  - name: enriched
    format: parquet
    path: results/final.parquet
```

**R code (_targets.R):**
```r
library(targets)
library(yamltargets)

tar_option_set(format = "parquet")
create_pipeline_from_yaml("pipeline.yml")
```

Benefits:
- ✅ YAML is self-documenting (structure is clear)
- ✅ Easy to modify (no R syntax needed)
- ✅ Auditable (version-control friendly)
- ✅ Testable (validate YAML before pipeline runs)

---

## Target Audience & Use Cases

### Who should use configtargets?

1. **Data analysts/scientists** — Define pipelines in a familiar config format
2. **Teams collaborating** — Non-coders can read and suggest changes
3. **Reproducible research** — Config + functions are all you need
4. **Multi-project patterns** — Reusable pipeline templates

### Example use cases

- **ETL workflows:** load CSV → clean → validate → export
- **Analysis pipelines:** load data → filter → summarize → plot
- **Data preprocessing:** raw data → harmonize → enrich → store
- **Batch processing:** iterate over files → process → merge results

### Who should NOT use configtargets

- Single, one-off analysis (targets is already simple enough)
- Complex custom orchestration (drop down to hand-written targets)
- Real-time pipelines (targets isn't designed for this)

---

## Package Vision: v1.0 (Minimal MVP)

Focus: **Make 80% of simple pipelines easy to configure; defer the last 20% to Phase 2.**

### Core Features (v1.0)

1. **YAML configuration** — Define sources, transforms, outputs declaratively
2. **Auto-generation** — Parse YAML and emit `tar_target()` calls
3. **Built-in loaders** — CSV, Parquet, RDS
4. **Dependency inference** — Automatically track input→output connections
5. **Schema validation** — Validate YAML structure before running pipeline

### NOT in v1.0 (defer to Phase 2)

- ❌ Custom loaders (loader_function with config-driven parameters)
- ❌ Target factories / looping (for_each)
- ❌ Conditional logic
- ❌ Parallel execution config
- ❌ Advanced templates
- ❌ Custom output formats (stick to parquet, csv, rds for v1)

### Why this scope?

**Target factories are NOT core to v1.0.** They're nice-to-have for advanced users, but not essential for a minimum viable package. Most users have **static pipelines** (fixed number of steps), not dynamic ones (iterate over N studies).

This makes v1.0:
- Simple to understand
- Easy to publish (fewer edge cases)
- Useful for 80% of users
- Foundation for Phase 2 factories

---

## Package Structure

```
yamltargets/
├── DESCRIPTION
├── NAMESPACE
├── R/
│   ├── create-pipeline.R        # Main API: create_pipeline_from_yaml()
│   ├── yaml-parser.R            # read_config(), validate_schema()
│   ├── target-builder.R         # Build tar_target() calls from config
│   ├── loaders.R                # load_csv(), load_parquet(), load_rds()
│   ├── utils.R                  # Helpers (dependency resolution, etc.)
│   └── zzz.R                    # .onLoad() for defaults
├── inst/
│   ├── schema/
│   │   └── pipeline.json        # JSON schema for config validation
│   └── examples/
│       ├── simple-etl/          # Minimal: load → clean → save
│       ├── analysis/            # Typical: load → filter → summarize → export
│       └── multi-source/        # Join two CSV files
├── vignettes/
│   ├── 01-quickstart.md         # "Define your first pipeline"
│   ├── 02-yaml-reference.md     # "Config syntax guide"
│   ├── 03-custom-functions.md   # "Add your own transform functions"
│   └── 04-troubleshooting.md    # Common errors and fixes
├── tests/testthat/
│   ├── test-yaml-parser.R
│   ├── test-target-builder.R
│   └── test-examples.R
└── README.md
```

---

## YAML Config Reference (v1.0)

### Structure

```yaml
# Metadata
name: "Pipeline Name"
description: "What this pipeline does"

# Data sources
sources:
  - name: <name>              # How to refer to this source in transforms
    type: csv | parquet | rds # File type
    path: <path>              # File or directory path
    # Optional:
    options:                  # Pass to read_csv(), read_parquet(), etc.
      na: "NA"
      encoding: "UTF-8"

# Transformation steps
transforms:
  - name: <name>              # Unique step name
    input: <name>             # Output from a source or previous transform
    function: <function_name> # R function to call
    params:                   # Function parameters (optional)
      arg1: value1
      arg2: value2

# Output targets
outputs:
  - name: <name>              # Which transform output to save
    format: parquet | csv | rds
    path: <directory>         # Where to save
    # Optional:
    options:                  # Format-specific options
      compression: "snappy"   # For parquet
```

### Example: Load → Clean → Save

```yaml
name: "Data Cleaning Pipeline"

sources:
  - name: raw_sales
    type: csv
    path: data/sales_2024.csv
    options:
      na: "NULL"

transforms:
  - name: clean_sales
    input: raw_sales
    function: clean_data
    params:
      remove_duplicates: true
      na_action: "drop"

outputs:
  - name: clean_sales
    format: parquet
    path: results/
```

---

## Key Exported Functions

```r
# Load YAML config and create tar_target() calls
create_pipeline_from_yaml(config_path, functions_env = parent.frame())

# Validate YAML without running
validate_pipeline(config_path)

# Export generated targets as _targets.R (for inspection)
export_targets_r(config_path, output_file = "_targets.R")

# List available loaders
list_loaders()
```

---

## Minimal Example

**File: `pipeline.yml`**
```yaml
name: "Sales Analysis"

sources:
  - name: sales_data
    type: csv
    path: data/sales.csv

transforms:
  - name: filtered_sales
    input: sales_data
    function: filter_recent_sales
    params: {days: 30}
  
  - name: summary
    input: filtered_sales
    function: summarize_by_region

outputs:
  - name: summary
    format: csv
    path: results/
```

**File: `_targets.R`**
```r
library(targets)
library(yamltargets)

tar_option_set(format = "parquet")
create_pipeline_from_yaml("pipeline.yml")
```

**File: `R/functions.R`**
```r
filter_recent_sales <- function(df, days) {
  df |> filter(date >= Sys.Date() - days)
}

summarize_by_region <- function(df) {
  df |>
    group_by(region) |>
    summarize(total_sales = sum(sales))
}
```

**Run it:**
```r
tar_make()
```

---

## Implementation Path

### Phase 1: MVP (2–3 weeks)

**Goal:** Prove the concept with static pipelines using built-in file loaders.

- [ ] YAML parser + validator (jsonschema)
  - Support `type: csv | parquet | rds`
- [ ] Target builder (emit tar_target() calls)
  - Generate loader targets from YAML sources
  - Connect transforms via input/output references
- [ ] Built-in loaders
  - `load_csv()`, `load_parquet()`, `load_rds()` with options
- [ ] Dependency resolution (input → output tracking)
- [ ] 3 example pipelines (CSV, Parquet, mixed)
- [ ] Unit tests + vignettes

**Deliverable:** Users can define and run simple 3–5 step pipelines in YAML with built-in file loaders.

### Phase 2: Advanced Features (1–2 months)

**Once v1.0 is stable and published:**

- [ ] **Custom loaders** — User-defined functions with config-driven parameters (e.g., `load_trt` with `trt_adam.yml`)
- [ ] **Target factories** — `for_each` loops for multi-file or multi-group processing
- [ ] **Conditional logic** — `if/then` based on config values
- [ ] **More loaders** — SQL, cloud storage (S3, GCS), APIs
- [ ] **Better error messages** — Validate pipeline at parse time
- [ ] **Pipeline merging** — Compose pipelines from multiple YAMLs

### Phase 3: Ecosystem (Future)

- [ ] Templates library (common pipeline patterns)
- [ ] Visualization (DAG rendering in browser)
- [ ] Integration with `renv` for environment tracking
- [ ] CLI tool for scaffolding new pipelines

---

## Design Principles

1. **Convention over configuration** — Default behaviors that work for 80% of cases
2. **Minimal magic** — Easy to drop down to hand-written targets if needed
3. **Explicit dependencies** — No implicit global state; DAG is always clear
4. **Targets-native** — Generates plain `tar_target()` calls; doesn't hide targets internals
5. **One way to do it** — Simple structure; avoid giving users too many options

---

## Why NOT Support Factories in v1.0?

Target factories (iterating over multiple items to create multiple targets) are powerful but add significant complexity:

- ✅ **Pro:** Solve the "process each file" problem elegantly
- ✅ **Pro:** Reduce repetition for multi-study pipelines
- ❌ **Con:** Require template engine ({{ variable }} substitution)
- ❌ **Con:** Require dependency graph expansion at parse time
- ❌ **Con:** Make error messages harder to understand
- ❌ **Con:** Add ~2 weeks to implementation time

**Alternative for users who need factories:**
- Use Phase 1 as a stepping stone
- If factories become essential, add them in Phase 2
- In the meantime, users can hand-write the factory code (targets already supports this)

**Example:** If you have 12 studies and need to generate 12 ADSL targets, you can:
- v1.0: Hand-write one factory function (20 lines), then move on
- v2.0: Define it in YAML with `for_each`

This keeps v1.0 simple and publishable.

---

## Success Criteria

1. ✅ **Usable** — A user with no targets experience can define a 3–5 step pipeline in YAML in < 10 minutes
2. ✅ **Transparent** — Users understand what targets are being generated (can inspect the DAG)
3. ✅ **Publishable** — Package passes CRAN checks; has good test coverage; minimal dependencies
4. ✅ **Extensible** — Users can add custom functions and loaders without patching the package
5. ✅ **Debuggable** — When YAML config has errors, error messages are clear

---

## Dependencies (Minimal)

- `targets` (≥ 1.0)
- `yaml` (for config parsing)
- `jsonschema` (for validation)
- `rlang` (for metaprogramming)
- `cli` (for pretty error messages)

**No heavy dependencies:** Easy to install, fast to load.

---

## Implementation Plan

### Phase 1: MVP (In Progress)

**Status:** Code structure complete. Core functions written and tested.

**What's done:**
- ✅ YAML parser + comprehensive validator
- ✅ Target builder (sources, transforms, outputs)
- ✅ Built-in file loaders (CSV, Parquet, RDS)
- ✅ Public API (`create_pipeline_from_yaml`, `validate_pipeline`)
- ✅ Test suite (config parsing, target building, validation)
- ✅ Idiomatic R code (reference packages reviewed, refactored)

**Remaining for Phase 1:**
- [ ] Documentation & examples (3–5 days)
- [ ] Edge case testing & fixes (2–3 days)
- [ ] README + quick-start guide (1–2 days)

**Estimate:** Phase 1 complete by end of July 2026.

### Phase 2: Custom Loaders (Planned)

**Start:** August 2026 (after Phase 1 stabilizes)

**Features:**
- Custom loader functions with config-driven parameters
- Schema evolution: `type: csv` → `loader: function_name` with `params`
- Validation of loader function names and parameters
- Support for API-based sources (e.g., `load_harmonized_codes` from pins)

**Estimate:** 3–4 weeks (depends on parallelization with Phase 1 testing).

### Phase 3: Factories & Advanced Features (Later)

**Deferred to post-CRAN:** Target factories, looping, conditional logic.

## Next Steps

1. ✅ **Vision locked** — Scope defined
2. ✅ **Code written** — Phase 1 MVP complete
3. **Testing & examples** — Build vignettes, edge cases
4. **Phase 1 release** — Publish to GitHub, ready for local use
5. **Gather feedback** — Users test with real pipelines
6. **Phase 2 design** — Custom loaders based on feedback
7. **CRAN submission** — Once Phase 1 stable

---

*Document created: 2026-06-28*
*Last updated: 2026-06-29*
