# tests/testthat/test-await_quack.R
#
# .await_quack() replaced a fixed Sys.sleep(1.5) followed by is_alive().
# That check was a race with a genuine bug: quack_serve() returns as soon as
# the listener is bound, so the callr process used to fall off the end of its
# function and exit about 1.3s in -- occasionally still "alive" at the moment
# it was sampled, always dead before the browser attached.
#
# These tests pin the three outcomes without needing DuckDB or the quack
# extension: a process that binds the port, one that dies, and one that never
# binds.

skip_if_no_callr <- function() skip_if_not_installed("callr")

# A stand-in server: binds the port and parks, exactly as the real one does
# once quack_serve() has returned.
bg_listener <- function(port, env = parent.frame()) {
  p <- callr::r_bg(
    func = function(port) {
      s <- serverSocket(port)
      on.exit(close(s), add = TRUE)
      repeat Sys.sleep(3600)
    },
    args = list(port), supervise = TRUE
  )
  withr::defer(try(p$kill(), silent = TRUE), envir = env)
  p
}

test_that("a NULL process passes straight through", {
  expect_null(tardoc:::.await_quack(NULL, 9990))
})

test_that("a process that binds the port is returned", {
  skip_if_no_callr()
  port <- tardoc:::.find_free_port(9700)
  p    <- bg_listener(port)
  expect_identical(tardoc:::.await_quack(p, port, timeout = 30), p)
  expect_true(p$is_alive())
})

test_that("a process that exits is reported with the reason, not silently", {
  skip_if_no_callr()
  p <- callr::r_bg(func = function() stop("boom: extension missing"),
                   supervise = TRUE)
  expect_message(
    res <- tardoc:::.await_quack(p, tardoc:::.find_free_port(9750), timeout = 30),
    "Quack exited early"
  )
  expect_null(res)
})

test_that("a process that never binds the port times out and is killed", {
  skip_if_no_callr()
  # Alive, but listening on nothing -- the case a liveness check cannot catch.
  p <- callr::r_bg(func = function() Sys.sleep(3600), supervise = TRUE)
  withr::defer(try(p$kill(), silent = TRUE))
  expect_message(
    res <- tardoc:::.await_quack(p, tardoc:::.find_free_port(9780), timeout = 2),
    "did not accept connections"
  )
  expect_null(res)
  expect_false(p$is_alive())
})

test_that("view_tardoc_db installs quack from the core repository", {
  # quack has been core since DuckDB 1.5.3, and nightly-extensions.duckdb.org
  # returns 403 for it on every platform and engine version. INSTALL ... FROM
  # core_nightly here means the server never starts and the viewer silently
  # serves the JSON snapshot instead.
  src <- paste(deparse(body(view_tardoc_db)), collapse = "\n")
  expect_match(src, "INSTALL quack;")
  expect_false(grepl("core_nightly", src, fixed = TRUE))
})

test_that("the background server parks instead of returning", {
  # Without the park the function returns, callr exits the process, and the
  # server dies about a second after it started.
  src <- paste(deparse(body(view_tardoc_db)), collapse = "\n")
  expect_match(src, "repeat Sys.sleep", fixed = TRUE)
})

test_that("the analytics template attaches Quack from the core repository", {
  tpl <- readLines(
    system.file("templates", "analytics.html", package = "tardoc"),
    warn = FALSE
  )
  installs <- grep("INSTALL quack", tpl, value = TRUE)
  expect_true(length(installs) > 0)
  expect_false(any(grepl("core_nightly", installs, fixed = TRUE)))
  # A failed attach must say why rather than looking like a plain snapshot.
  expect_true(any(grepl("Quack attach failed", tpl, fixed = TRUE)))
})
