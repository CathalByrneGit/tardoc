# R/generate_llm_content.R
# Uses ellmer for provider-agnostic LLM access.
# Providers: openai, anthropic, ollama, openai_compatible (llama.cpp, vLLM)
# Called only when document_targets(llm = TRUE).

#' Generate LLM content for undescribed targets and all functions
#'
#' Fills in descriptions for targets that have none and adds a plain-language
#' explanation to each function page. Requires the `ellmer` package.
#'
#' @param targets_data   Output of [load_targets_data()].
#' @param function_names Character vector of function names to explain.
#' @param cfg            A site config list.
#' @param llm_chat       An existing `ellmer` Chat object. When supplied,
#'   `provider`, `model`, `api_key` and `base_url` are ignored.
#' @param provider       Character. One of `"openai"`, `"anthropic"`,
#'   `"ollama"`, or `"openai_compatible"`. Default `"openai"`.
#' @param model          Character. Model name. Defaults to the provider's own
#'   default when `NULL`.
#' @param api_key        Character. API key. When `NULL` the provider's
#'   standard environment variable is used.
#' @param base_url       Character. Base URL for `"ollama"` and
#'   `"openai_compatible"` providers.
#' @param refresh        Logical. Regenerate everything. By default a target
#'   that already has a description on its page is left alone, and a function
#'   is explained again only when its source or docs changed -- a run used to
#'   pay for every function every time.
#'
#' @return Invisibly `NULL`; called for its side effect of rewriting the
#'   generated blocks of the target and function markdown pages.
#' @export
generate_llm_content <- function(targets_data, function_names, cfg,
                                  llm_chat = NULL, provider = "openai",
                                  model = NULL, api_key = NULL, base_url = NULL,
                                  refresh = FALSE) {
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
    if (.has_description(row)) return(FALSE)
    # Already described on its page by an earlier run: keep it, unless asked.
    isTRUE(refresh) || is.na(.page_description(file.path(cfg$targets_dir, paste0(tn, ".md"))))
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

  r_files <- .function_r_files(cfg)
  message("  Generating function explanations (", length(function_names), ")...")
  ch_fn <- make_chat("You write 2-3 sentence plain-English explanations for R functions: what it does, key inputs, what it returns.")
  explained <- 0L
  reused    <- 0L
  cache     <- .read_llm_cache(cfg)
  for (fn in function_names) {
    src <- .find_function_file(fn, r_files)
    if (is.null(src)) next
    # The verbatim source, comments included -- deparse() discards every
    # comment, which are often the best explanation of what a function is for,
    # and sourcing the file executed the user's top-level code to get at it.
    code <- .file_functions(src)[[fn]]$text
    if (is.null(code)) next
    docs <- suppressWarnings(get_fn_docs(fn, src))
    page <- file.path(cfg$functions_dir, paste0(fn, ".md"))
    key  <- .explanation_key(code, docs)

    # The page's generated block is rewritten on every run, which discards an
    # explanation -- so the text is kept in a cache beside the docs and put
    # back for free while the function is unchanged.
    expl <- if (isTRUE(refresh)) NULL else cache[[key]]
    fresh <- is.null(expl)
    if (fresh) {
      expl <- tryCatch(trimws(ch_fn$chat(.fn_explanation_prompt(fn, code, docs), echo = FALSE)),
                       error = function(e) { message("    [skip] ", fn, ": ", conditionMessage(e)); NULL })
    }
    if (!is.null(expl) && nchar(expl) > 0) {
      cache[[key]] <- expl
      .inject_explanation(page, expl)
      explained <- explained + 1L
      reused <- reused + !fresh
      message("    ", fn, if (!fresh) " (cached)" else "")
    }
  }
  .write_llm_cache(cfg, cache)
  message("Done. Descriptions: ", length(undescribed), "  Explanations: ", explained,
          if (reused) paste0(" (", reused, " from cache)") else "")
  invisible(NULL)
}

.llm_cache_path <- function(cfg) file.path(cfg$site_path, "llm_cache.json")

.read_llm_cache <- function(cfg) {
  p <- .llm_cache_path(cfg)
  if (!file.exists(p)) return(list())
  tryCatch(jsonlite::fromJSON(p, simplifyVector = FALSE), error = function(e) list())
}

.write_llm_cache <- function(cfg, cache) {
  .write_lines_utf8(jsonlite::toJSON(cache, auto_unbox = TRUE, pretty = TRUE), .llm_cache_path(cfg))
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
  lines <- .read_lines_utf8(path)
  title <- which(lines == paste0("# Target: ", name))
  if (!length(title)) return(invisible(NULL))
  title <- title[1]

  # Only the header is ours to rewrite: the lines between the title and the
  # first marker. The old version removed every blockquote in the file, which
  # deleted quotations the user had written in their own notes below.
  marker <- which(lines == "<!-- tardoc:generated -->")
  stop_at <- if (length(marker)) marker[1] - 1L else length(lines)
  head <- seq_len(stop_at)
  head <- head[head > title]
  old  <- head[startsWith(lines[head], "> ")]
  drop <- c(old, old + 1L)               # the quote and the blank line after it
  drop <- drop[drop <= stop_at & !(drop %in% seq_len(title))]
  if (length(drop)) lines <- lines[-drop]

  lines <- append(lines, c("", paste0("> ", gsub("[[:space:]]+", " ", desc))),
                  after = title)
  .write_lines_utf8(lines, path)
}

.inject_explanation <- function(path, explanation) {
  if (!file.exists(path)) return(invisible(NULL))
  lines   <- .read_lines_utf8(path)
  end_tag <- "<!-- tardoc:end -->"

  # Drop any previous block first, so re-running replaces it instead of
  # stacking a second one: from the heading up to the next heading or the end
  # marker, whichever comes first.
  start <- which(lines == "## LLM Explanation")
  if (length(start) > 0) {
    s     <- start[1]
    after <- seq_along(lines)[-seq_len(s)]
    stops <- after[grepl("^## |^<!-- tardoc:end -->$", lines[after])]
    e     <- if (length(stops) > 0) stops[1] - 1L else length(lines)
    lines <- lines[-seq.int(s, e)]
  }

  # Build the block as lines rather than substituting it into a regex: the
  # explanation is model output and may contain backslashes or backreference
  # syntax, which sub() would interpret.
  block <- c("## LLM Explanation", "", "_Auto-generated._",
             "", explanation, "")
  at    <- which(lines == end_tag)
  lines <- if (length(at) > 0) {
    append(lines, block, after = at[1] - 1L)
  } else {
    c(lines, block)
  }
  .write_lines_utf8(lines, path)
}

.has_description <- function(r) {
  if (!"description" %in% names(r)) return(FALSE)
  v <- dplyr::pull(r, "description")
  length(v) > 0 && !is.na(v) && nchar(trimws(v)) > 0
}


`%||%` <- function(x, y) if (is.null(x)) y else x

#' What a function's explanation was generated from
#'
#' The explanation is cached under this key (`llm_cache.json`, beside the
#' docs), so an unchanged function is not paid for again on the next run. Provider and model are deliberately not
#' part of it: switching them is not a reason to regenerate everything, and
#' `refresh = TRUE` exists for when it is.
#'
#' @param code The function's verbatim source.
#' @param docs Its rendered roxygen docs, or `NULL`.
#' @return A short string.
#' @keywords internal
.explanation_key <- function(code, docs) {
  substr(rlang::hash(list(code, docs)), 1L, 16L)
}

#' The description a target's page carries under its title
#'
#' @param path Target page.
#' @return The text, or `NA_character_` when there is none.
#' @keywords internal
.page_description <- function(path) {
  if (!file.exists(path)) return(NA_character_)
  lines <- .read_lines_utf8(path)
  marker <- which(lines == "<!-- tardoc:generated -->")
  top <- lines[seq_len(if (length(marker)) marker[1] - 1L else min(length(lines), 4L))]
  q <- top[startsWith(top, "> ")]
  if (length(q)) sub("^> ", "", q[1]) else NA_character_
}

#' Fold descriptions already on the pages back into the pipeline data
#'
#' A description written by `llm = TRUE` lives on the target's page, but the
#' search index, the graph panel, `llms.txt` and the analytics tables all read
#' the manifest -- so they said "no description" for exactly the targets the
#' model had just described, and on every later run without `llm = TRUE`. This
#' fills the gaps from the pages, once, before any of them are built. A
#' description in `_targets.R` always wins.
#'
#' @param targets_data Output of [load_targets_data()].
#' @param cfg A site config list.
#' @return `targets_data` with `manifest$description` completed.
#' @keywords internal
.merge_page_descriptions <- function(targets_data, cfg) {
  m <- targets_data$manifest
  if (!"description" %in% names(m)) m$description <- NA_character_
  m$description <- as.character(m$description)
  for (i in seq_len(nrow(m))) {
    if (!is.na(m$description[i]) && nzchar(trimws(m$description[i]))) next
    d <- .page_description(file.path(cfg$targets_dir, paste0(m$name[i], ".md")))
    if (!is.na(d)) m$description[i] <- d
  }
  targets_data$manifest <- m
  targets_data
}
