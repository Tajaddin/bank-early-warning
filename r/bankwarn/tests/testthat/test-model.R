synthetic <- function(n = 4000, seed = 7) {
  set.seed(seed)
  x <- as.data.frame(matrix(stats::rnorm(n * length(FEATURES)), ncol = length(FEATURES)))
  names(x) <- FEATURES
  logit <- -3 + 1.5 * x$ncl - 1.2 * x$eqv - 0.8 * x$roa
  x$failed <- stats::runif(n) < 1 / (1 + exp(-logit))
  x$CERT <- seq_len(n)
  x$REPDTE <- as.Date("2009-12-31")
  x
}

test_that("the fit recovers the signs of a known model", {
  m <- fit_warning_model(synthetic(), clip = c(0, 1))
  expect_gt(m$coefficients[["ncl"]], 1)
  expect_lt(m$coefficients[["eqv"]], -0.8)
  expect_lt(m$coefficients[["roa"]], -0.4)
  expect_s3_class(m, "bankwarn_model")
})

test_that("score() is exactly the dot product the SQL engines compute", {
  d <- synthetic()
  m <- fit_warning_model(d)
  bounds <- Map(c, m$lower, m$upper)
  manual <- vapply(seq_len(20), function(i) {
    z <- m$intercept
    for (f in m$features) z <- z + m$coefficients[[f]] * min(max(d[[f]][i], bounds[[f]][1]), bounds[[f]][2])
    1 / (1 + exp(-z))
  }, numeric(1))
  expect_equal(score(m, d[1:20, ]), manual, tolerance = 1e-12)
  # without clipping (bounds wider than the data) it matches glm's own prediction
  wide <- fit_warning_model(d, clip = c(0, 1))
  expect_equal(score(wide, d), unname(stats::predict(wide$fit, type = "response")), tolerance = 1e-10)
})

test_that("clipping uses the training quantiles", {
  d <- synthetic()
  d$eff[1] <- 1e6
  m <- fit_warning_model(d)
  expect_equal(m$upper[["eff"]], unname(stats::quantile(d$eff, 0.99)))
  expect_lt(max(clip_features(d, "eff", list(eff = c(m$lower[["eff"]], m$upper[["eff"]])))$eff), 1e6)
})

test_that("the exported model round-trips every digit", {
  m <- fit_warning_model(synthetic())
  path <- tempfile(fileext = ".json")
  export_model(m, path)
  doc <- jsonlite::fromJSON(path)
  expect_identical(doc$intercept, m$intercept)
  expect_identical(doc$features$coefficient, unname(m$coefficients[m$features]))
  expect_identical(doc$features$upper, unname(m$upper))
  expect_output(print(m), "14 features")
})

test_that("a training set without failures is refused", {
  d <- synthetic()
  d$failed <- FALSE
  expect_error(fit_warning_model(d), "no failures")
})
