library(yamltargets)

config <- read_pipeline_config("inst/examples/simple-etl/pipeline.yml")

cat("=== Debugging Config Parsing ===\n\n")

cat("Sources:\n")
for (src in config$sources) {
  cat(sprintf("  name: '%s' (class: %s, length: %d)\n", src$name, class(src$name), nchar(src$name)))
  cat(sprintf("    raw bytes: %s\n", paste(charToRaw(src$name), collapse = " "))  )
  cat(sprintf("    is valid symbol: %s\n", rlang::is_symbol(rlang::sym(src$name))))
}

cat("\nTransforms:\n")
for (trn in config$transforms) {
  cat(sprintf("  name: '%s' (class: %s, length: %d)\n", trn$name, class(trn$name), nchar(trn$name)))
}

cat("\nOutputs:\n")
for (out in config$outputs) {
  cat(sprintf("  name: '%s' (class: %s, length: %d)\n", out$name, class(out$name), nchar(out$name)))
}
