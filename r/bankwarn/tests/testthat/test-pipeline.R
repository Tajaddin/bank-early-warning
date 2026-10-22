synthetic_panel <- function(banks = 400, seed = 11) {
  set.seed(seed)
  dates <- seq(as.Date("2007-01-01"), as.Date("2013-01-01"), by = "quarter") - 1 # 2006-12-31 .. 2012-12-31
  # a fifth of the banks fail between mid-2008 and 2013; their capital and earnings slide first
  failing <- stats::runif(banks) < 0.2
  offsets <- sample(0:1800, banks, replace = TRUE)
  fail_at <- as.Date("2008-06-01") + ifelse(failing, offsets, NA)
  rows <- lapply(seq_len(banks), function(cert) {
    fail <- fail_at[cert]
    alive <- if (is.na(fail)) dates else dates[dates < fail - 30]
    stress <- if (is.na(fail)) 0 else pmax(0, 1 - as.numeric(fail - alive) / 900)
    n <- length(alive)
    # every ratio is noisy and the effects are moderate: perfectly separable data would not converge
    noise <- function(sd) stats::rnorm(n, 0, sd)
    data.frame(
      CERT = cert,
      REPDTE = alive,
      ASSET = 1e5 * exp(cumsum(stats::rnorm(n, 0.01, 0.02))),
      DEP = 8e4,
      BRO = 4e3 * (1 + stress) * exp(noise(0.3)),
      EQV = 11 - 4 * stress + noise(1.5),
      RBC1AAJ = 10 - 3 * stress + noise(1.2),
      NCLNLSR = 1 + 4 * stress + abs(noise(1.5)),
      LNATRESR = 1.5 + stress + abs(noise(0.5)),
      ELNATRY = 0.3 + stress + noise(0.4),
      ROA = 1 - 2 * stress + noise(0.6),
      NIMY = 3.6 - 0.5 * stress + noise(0.3),
      EEFFR = 65 + 15 * stress + noise(8),
      LNLSDEPR = 80 + noise(5)
    )
  })
  list(
    financials = do.call(rbind, rows),
    failures = data.frame(CERT = which(failing), FAILDATE = fail_at[failing])
  )
}

test_that("the pipeline fits, evaluates out of time and writes everything the SQL side needs", {
  panel <- synthetic_panel()
  raw <- file.path(tempdir(), "raw")
  out <- file.path(tempdir(), "out")
  dir.create(raw, showWarnings = FALSE)
  arrow::write_parquet(panel$financials, file.path(raw, "financials.parquet"))
  arrow::write_parquet(panel$failures, file.path(raw, "failures.parquet"))

  report <- run_pipeline(raw, out, k = 20)

  outputs <- c("model.json", "test_scores.parquet", "test_scores_all.parquet", "report.json")
  expect_true(all(file.exists(file.path(out, outputs))))
  expect_gt(report$data$train$failed_banks, 5)
  expect_gt(report$data$test$failed_banks, 5)
  expect_gt(report$model$auc, 0.8) # the synthetic failures are strongly signalled
  expect_lt(report$model$auc_95ci[1], report$model$auc)
  expect_gt(report$model$auc_95ci[2], report$model$auc)
  all_scores <- arrow::read_parquet(file.path(out, "test_scores_all.parquet"))
  labelled <- arrow::read_parquet(file.path(out, "test_scores.parquet"))
  expect_gte(nrow(all_scores), nrow(labelled)) # labelling only ever drops rows
  in_test <- all_scores$REPDTE >= as.Date("2011-03-31") & all_scores$REPDTE <= as.Date("2012-12-31")
  expect_true(all(in_test))
  doc <- jsonlite::fromJSON(file.path(out, "model.json"))
  expect_equal(doc$features$feature, FEATURES)
})
