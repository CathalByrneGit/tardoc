# R/generate_llm_content.R
# Uses ellmer for provider-agnostic LLM access.
# Providers: openai, anthropic, ollama, openai_compatible (llama.cpp, vLLM)
# Called only when document_targets(llm = TRUE).

#' Generate LLM content for undescribed targets and all functions
#' @export
generate_llm_content <- function(targets_data, function_names, cfg,
                                  llm_chat = NULL, provider = "openai",
                                  model = NULL, api_key = NULL, base_url = NULL) {
  if (!requireNamespace("ellmer", quietly = TRUE))
    stop("'ellmer' is required: install.packages('ellmer')")

  make_chat <- if (!is.null(llm_chat)) {
    function(system = NULL) {
      llm_chat$set_turns(list())
      if (!is.null(system))
        llm_chat$chat(paste0("[SYSTEM CONTEXT]\n", system,
                             "\nReply 'understood' and wait for tasks."), echo = FALSE)
      llm_chat
    }
  } else {
    function(system = NULL) .make_ellmer_chat(provider, model, api_key, base_url, system)
  }

  message("\nGenerating LLM content (", if (!is.null(llm_chat)) class(llm_chat)[1] else provider, ")...")

  undescribed <- Filter(function(tn) {
    row <- dplyr::filter(targets_data$manifest, .data$name == tn)
    !.has_description(row)
  }, targets_data$target_names)

  message("  Targets without descriptions: ", length(undescribed))
  if (length(undescribed) > 0) {
    ch <- make_chat("You write one-sentence descriptions for R targets pipeline targets. Start with a verb, describe the output, max 20 words.")
    for (tn in undescribed) {
      row <- dplyr::filter(targets_data$manifest, .data$name == tn)
      dep <- get_target_network_dependencies(tn, targets_data$network, max_depth_up = 1, max_depth_down = 1)
      cmd <- dplyr::pull(row, "command")
      desc <- tryCatch(trimws(ch$chat(.target_desc_prompt(tn, cmd, dep$upstream, dep$downstream), echo = FALSE)),
                       error = function(e) { message("    [skip] ", tn, ": ", conditionMessage(e)); NULL })
      if (!is.null(desc) && nchar(desc) > 0) {
        .inject_description(file.path(cfg$targets_dir, paste0(tn, ".md")), tn, desc)
        message("    ", tn)
      }
    }
  }

  r_files <- list.files(cfg$r_scripts_dir, pattern = "\\.R$", full.names = TRUE)
  message("  Generating function explanations (", length(function_names), ")...")
  ch_fn <- make_chat("You write 2-3 sentence plain-English explanations for R functions: what it does, key inputs, what it returns.")
  explained <- 0L
  for (fn in function_names) {
    src <- .find_fn_file(fn, r_files)
    if (is.null(src)) next
    env <- new.env(parent = globalenv())
    tryCatch(source(src, local = env), error = function(e) NULL)
    if (!fn %in% ls(env)) next
    code <- paste(deparse(get(fn, env)), collapse = "\n")
    docs <- suppressWarnings(get_fn_docs(fn, src))
    expl <- tryCatch(trimws(ch_fn$chat(.fn_explanation_prompt(fn, code, docs), echo = FALSE)),
                     error = function(e) { message("    [skip] ", fn, ": ", conditionMessage(e)); NULL })
    if (!is.null(expl) && nchar(expl) > 0) {
      .inject_explanation(file.path(cfg$functions_dir, paste0(fn, ".md")), expl)
      explained <- explained + 1L
      message("    ", fn)
    }
  }
  message("Done. Descriptions: ", length(undescribed), "  Explanations: ", explained)
  invisible(NULL)
}

.make_ellmer_chat <- function(provider, model, api_key, base_url, system_prompt = NULL) {
  args <- list()
  if (!is.null(model))         args$model         <- model
  if (!is.null(system_prompt)) args$system_prompt <- system_prompt
  switch(provider,
    openai    = { if (!is.null(api_key)) args$api_key <- api_key; do.call(ellmer::chat_openai, args) },
    anthropic = { if (!is.null(api_key)) args$api_key <- api_key; do.call(ellmer::chat_anthropic, args) },
    ollama    = do.call(ellmer::chat_ollama, args),
    openai_compatible = {
      if (is.null(base_url)) stop("base_url required for openai_compatible")
      args$base_url <- base_url
      if (!is.null(api_key)) args$api_key <- api_key
      do.call(ellmer::chat_openai_compatible, args)
    },
    stop("Unknown provider: ", provider)
  )
}

.target_desc_prompt <- function(name, command, upstream, downstream) {
  paste0("Write ONE sentence (max 20 words) for target '", name, "'.\n",
         "Command: ", command, "\nDepends on: ", paste(upstream %||% "none", collapse = ", "),
         "\nUsed by: ", paste(downstream %||% "none", collapse = ", "),
         "\nStart with a verb. Output only the sentence.")
}

.fn_explanation_prompt <- function(name, code, docs) {
  docs_part <- if (!is.null(docs) && nchar(trimws(docs)) > 0)
    paste0("Roxygen docs:\n", docs, "\n\n") else ""
  paste0("Explain R function '", name, "' in 2-3 sentences.\n\n", docs_part,
         "Source:\n```r\n", code, "\n```\n\nOutput the explanation only.")
}

.inject_description <- function(path, name, desc) {
  if (!file.exists(path)) return(invisible(NULL))
  content <- paste(readLines(path, warn = FALSE), collapse = "\n")
  if (!grepl(paste0("# Target: ", name), content, fixed = TRUE)) return(invisible(NULL))
  content <- gsub("\n> [^\n]+\n", "\n", content)
  content <- sub(paste0("(# Target: ", name, "\n)"),
                 paste0("\\1\n> ", desc, "\n"), content)
  writeLines(content, path)
}

.inject_explanation <- function(path, explanation) {
  if (!file.exists(path)) return(invisible(NULL))
  content <- paste(readLines(path, warn = FALSE), collapse = "\n")
  block <- paste0("\n## LLM Explanation\n\n_Auto-generated._\n\n", explanation, "\n")
  if (grepl("## LLM Explanation", content, fixed = TRUE)) {
    content <- sub("(\n## LLM Explanation\n).*?(\n##|\n<!-- tardoc:end -->)",
                   paste0(block, "\\2"), content, perl = TRUE)
  } else {
    content <- sub("(<!-- tardoc:end -->)", paste0(block, "\\1"), content, fixed = TRUE)
  }
  writeLines(content, path)
}

.has_description <- function(r) {
  if (!"description" %in% names(r)) return(FALSE)
  v <- dplyr::pull(r, "description")
  length(v) > 0 && !is.na(v) && nchar(trimws(v)) > 0
}

.find_fn_file <- function(fn, r_files) {
  for (f in r_files) {
    e <- new.env(parent = globalenv())
    tryCatch(source(f, local = e), error = function(e) NULL)
    if (fn %in% ls(e)) return(f)
  }
  NULL
}

`%||%` <- function(x, y) if (is.null(x)) y else x
