# tests/testthat/test-hardening.R
#
# The local analytics server answers chat requests with the user's LLM
# credentials and serves files from the docs folder, so what it will serve, to
# whom, and where it listens are tested directly.

# ---- which files it will serve ---------------------------------------------

test_that(".safe_site_file serves files inside the docs folder", {
  site <- withr::local_tempdir(); dir.create(file.path(site, "targets"))
  expect_identical(.safe_site_file(site, "/viewer.html"),
                   file.path(normalizePath(site, winslash = "/"), "viewer.html"))
  expect_match(.safe_site_file(site, "/targets/a.md"), "/targets/a.md$")
})

test_that(".safe_site_file refuses paths that climb out, plain or encoded", {
  site <- withr::local_tempdir()
  for (p in c("/../secret", "/../../etc/passwd", "/targets/../../x",
              "/%2e%2e/secret", "/..%2fsecret", "/%2e%2e%2f%2e%2e%2fetc/passwd",
              "/..\\secret")) {
    expect_null(.safe_site_file(site, p), info = p)
  }
})

test_that(".safe_site_file refuses a symlink that leaves the folder", {
  skip_on_os("windows")
  site <- withr::local_tempdir(); outside <- withr::local_tempdir()
  writeLines("secret", file.path(outside, "s.txt"))
  file.symlink(outside, file.path(site, "link"))
  expect_null(.safe_site_file(site, "/link/s.txt"))
})

test_that(".safe_site_file refuses the folder itself and empty paths", {
  site <- withr::local_tempdir()
  expect_null(.safe_site_file(site, "/"))
  expect_null(.safe_site_file(site, ""))
  expect_null(.safe_site_file(site, "/."))
})

# ---- who may talk to it ------------------------------------------------------

test_that(".origin_allowed accepts only this server's own origins", {
  expect_true(.origin_allowed("http://localhost:9000", 9000))
  expect_true(.origin_allowed("http://127.0.0.1:9000", 9000))
  expect_false(.origin_allowed("http://localhost:9001", 9000))
  expect_false(.origin_allowed("https://evil.example", 9000))
  expect_false(.origin_allowed("http://localhost:9000.evil.example", 9000))
  expect_false(.origin_allowed("null", 9000))
})

test_that("the server listens on localhost unless told otherwise", {
  src <- paste(deparse(view_tardoc_db), collapse = "\n")
  expect_match(src, 'host = "127.0.0.1"', fixed = TRUE)
  expect_match(src, "httpuv::runServer(host, port, app)", fixed = TRUE)
  expect_no_match(src, "0.0.0.0", fixed = TRUE)
  mcp <- paste(deparse(serve_tardoc_mcp), collapse = "\n")
  expect_match(mcp, 'host = "127.0.0.1"', fixed = TRUE)
  expect_no_match(mcp, "'0.0.0.0'", fixed = TRUE)
})

test_that("no wildcard CORS header is sent", {
  src <- paste(deparse(view_tardoc_db), deparse(.json_resp), collapse = "\n")
  expect_no_match(src, '"Access-Control-Allow-Origin" = "*"', fixed = TRUE)
})

# The handler is called directly with a made-up request: no network involved.
local_app <- function(env = parent.frame(), llm = FALSE) {
  site <- withr::local_tempdir(.local_envir = env)
  writeLines("<html>ok</html>", file.path(site, "viewer.html"))
  secret <- file.path(dirname(site), "outside-secret.txt")
  writeLines("secret", secret); withr::defer(unlink(secret), envir = env)
  session <- file.path(site, "_session_analytics.html"); writeLines("session", session)
  chat <- if (llm) list(chat = function(...) "answered", set_turns = function(...) NULL)
  log <- new.env(); log$calls <- list()
  list(app = .analytics_app(site, session, 9000, chat, log), site = site)
}
req <- function(path, method = "GET", origin = NULL, body = "{}") {
  r <- list(PATH_INFO = path, REQUEST_METHOD = method,
            rook.input = list(read = function() charToRaw(body)))
  if (!is.null(origin)) r$HTTP_ORIGIN <- origin
  r
}

test_that("the handler serves a docs file and the session page", {
  a <- local_app()
  expect_identical(a$app$call(req("/viewer.html"))$status, 200L)
  expect_identical(a$app$call(req("/"))$status, 200L)
})

test_that("the handler will not serve a file outside the docs folder", {
  a <- local_app()
  for (p in c("/../outside-secret.txt", "/%2e%2e/outside-secret.txt", "/..%2foutside-secret.txt")) {
    expect_identical(a$app$call(req(p))$status, 404L, info = p)
  }
})

test_that("the handler does not serve a directory", {
  a <- local_app(); dir.create(file.path(a$site, "targets"))
  expect_identical(a$app$call(req("/targets"))$status, 404L)
})

test_that("/chat refuses a foreign Origin before reaching the model", {
  a <- local_app(llm = TRUE)
  r <- a$app$call(req("/chat", "POST", origin = "https://evil.example", body = '{"message":"hi"}'))
  expect_identical(r$status, 403L)
})

test_that("/chat answers its own page, and a request with no Origin", {
  a <- local_app(llm = TRUE)
  own <- a$app$call(req("/chat", "POST", origin = "http://localhost:9000", body = '{"message":"hi"}'))
  expect_identical(own$status, 200L)
  expect_match(as.character(own$body), "answered")
  expect_identical(a$app$call(req("/chat", "POST", body = '{"message":"hi"}'))$status, 200L)
})

test_that("CORS names the caller's own origin and never a wildcard", {
  a <- local_app()
  own <- a$app$call(req("/viewer.html", origin = "http://localhost:9000"))
  expect_identical(own$headers[["Access-Control-Allow-Origin"]], "http://localhost:9000")
  foreign <- a$app$call(req("/viewer.html", origin = "https://evil.example"))
  expect_null(foreign$headers[["Access-Control-Allow-Origin"]])
  pre <- a$app$call(req("/chat", "OPTIONS", origin = "https://evil.example"))
  expect_null(pre$headers[["Access-Control-Allow-Origin"]])
})

# ---- tokens and ports --------------------------------------------------------

test_that(".session_token is 32 hex characters and ignores set.seed()", {
  set.seed(1); a <- .session_token()
  set.seed(1); b <- .session_token()
  expect_match(a, "^[0-9a-f]{32}$")
  skip_if_not(file.exists("/dev/urandom"))
  expect_false(identical(a, b))
})

test_that(".find_free_port can be told to avoid a port", {
  p <- .find_free_port(40100)
  q <- .find_free_port(p, avoid = p)
  expect_false(identical(p, q))
})

# ---- a stale database --------------------------------------------------------

test_that(".db_is_stale compares the database with the docs it was built from", {
  site <- withr::local_tempdir()
  db <- file.path(site, "tardoc.duckdb"); idx <- file.path(site, "search_index.json")
  expect_false(.db_is_stale(site, db))            # no database: not stale, absent
  writeLines("x", db); writeLines("{}", idx)
  Sys.setFileTime(db,  Sys.time() - 120)
  Sys.setFileTime(idx, Sys.time())
  expect_true(.db_is_stale(site, db))
  Sys.setFileTime(db, Sys.time() + 60)
  expect_false(.db_is_stale(site, db))
})

test_that("view_tardoc_db rebuilds a stale database", {
  src <- paste(deparse(view_tardoc_db), collapse = "\n")
  expect_match(src, ".db_is_stale(site_path, db_path)", fixed = TRUE)
  expect_match(src, ".db_had_extensions(db_path)", fixed = TRUE)
})

# ---- the chat's system prompt ------------------------------------------------

test_that("the system prompt goes through the public setter when there is one", {
  got <- NULL
  chat <- list(set_system_prompt = function(x) got <<- x)
  expect_true(.configure_chat_for_analytics(chat, NULL))
  expect_match(got, "run_sql", fixed = TRUE)
})

test_that("a failing setter is reported, not swallowed", {
  chat <- list(set_system_prompt = function(x) stop("boom"))
  expect_message(ok <- .configure_chat_for_analytics(chat, NULL), "system prompt")
  expect_false(ok)
})
