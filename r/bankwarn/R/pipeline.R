#' Run the whole analysis on the fetched data
#'
#' Reads `financials.parquet` and `failures.parquet`, builds features and labels,
#' fits on the training report dates, evaluates on the test report dates against
#' a one-ratio baseline (lowest equity-to-assets first), and writes the model, the
#' test scores and a report.
#'
#' @param raw Folder with the fetched Parquet files.
#' @param out Folder for the results.
#' @param train,test Inclusive report-date ranges, as two `"YYYY-MM-DD"` strings.
#' @param k Watch-list size per quarter.
#' @return The report as a list, invisibly.
#' @export
run_pipeline <- function(raw, out,
                         train = c("2007-12-31", "2009-12-31"),
                         test = c("2011-03-31", "2012-12-31"),
                         k = 100) {
  dir.create(out, showWarnings = FALSE, recursive = TRUE)
  financials <- as.data.frame(arrow::read_parquet(file.path(raw, "financials.parquet")))
  failures <- as.data.frame(arrow::read_parquet(file.path(raw, "failures.parquet")))
  features <- build_features(financials)
  labelled <- label_failures(features, failures)
  tr <- period(labelled, train[1], train[2])
  te <- period(labelled, test[1], test[2])

  model <- fit_warning_model(tr)
  te$score <- score(model, te)
  te$baseline <- -te$eqv  # the one-ratio rule: thinnest capital first

  export_model(model, file.path(out, "model.json"))
  arrow::write_parquet(te[, c("CERT", "REPDTE", "score", "failed")], file.path(out, "test_scores.parquet"))
  # every bank-quarter of the test period, before labelling drops any: what each SQL engine must reproduce
  all_test <- period(features, test[1], test[2])
  all_test$score <- score(model, all_test)
  arrow::write_parquet(all_test[, c("CERT", "REPDTE", "score")], file.path(out, "test_scores_all.parquet"))

  report <- list(
    data = list(
      bank_quarters = nrow(labelled),
      train = list(from = train[1], to = train[2], rows = nrow(tr), failed_rows = sum(tr$failed),
                   failed_banks = length(unique(tr$CERT[tr$failed]))),
      test = list(from = test[1], to = test[2], rows = nrow(te), failed_rows = sum(te$failed),
                  failed_banks = length(unique(te$CERT[te$failed])))
    ),
    model = list(
      auc = auc(te$score, te$failed),
      auc_95ci = auc_interval(te$score, te$failed, te$CERT),
      brier = brier(te$score, te$failed),
      watch_list_recall = attr(watch_list(te, "score", k), "recall"),
      watch_list_precision = attr(watch_list(te, "score", k), "precision")
    ),
    baseline_lowest_equity = list(
      auc = auc(te$baseline, te$failed),
      auc_95ci = auc_interval(te$baseline, te$failed, te$CERT),
      watch_list_recall = attr(watch_list(te, "baseline", k), "recall"),
      watch_list_precision = attr(watch_list(te, "baseline", k), "precision")
    ),
    watch_list_k = k,
    coefficients = as.list(model$coefficients),
    r_version = R.version.string
  )
  writeLines(jsonlite::toJSON(report, digits = 6, auto_unbox = TRUE, pretty = TRUE), file.path(out, "report.json"))
  invisible(report)
}
