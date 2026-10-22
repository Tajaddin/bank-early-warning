#' Area under the ROC curve
#'
#' The Mann-Whitney form: the probability that a random failed bank-quarter
#' scores above a random surviving one, ties counting half.
#'
#' @param score Numeric scores.
#' @param label Logical labels.
#' @return The AUC.
#' @export
auc <- function(score, label) {
  label <- as.logical(label)
  n1 <- sum(label)
  n0 <- sum(!label)
  if (n1 == 0 || n0 == 0) return(NA_real_)
  r <- rank(score)
  (sum(r[label]) - n1 * (n1 + 1) / 2) / (n1 * n0)
}

#' Bootstrap interval for the AUC, resampling banks
#'
#' Quarters of one bank are not independent, so whole banks are resampled.
#'
#' @param score,label,bank Scores, labels and bank ids of the same rows.
#' @param n Resamples.
#' @param seed Random seed.
#' @return A length-2 numeric vector: the 2.5% and 97.5% quantiles.
#' @export
auc_interval <- function(score, label, bank, n = 1000, seed = 1) {
  set.seed(seed)
  rows <- split(seq_along(bank), bank)
  ids <- names(rows)
  stats <- vapply(seq_len(n), function(i) {
    take <- unlist(rows[sample(ids, length(ids), replace = TRUE)], use.names = FALSE)
    auc(score[take], label[take])
  }, numeric(1))
  unname(stats::quantile(stats, c(0.025, 0.975), na.rm = TRUE))
}

#' The watch list: how many failures the top-k banks of each quarter contain
#'
#' A supervisor can examine k banks a quarter. Per report date, the k highest
#' scores are the watch list; recall is the share of that quarter's failing banks
#' on it, precision the share of the list that fails.
#'
#' @param data Rows with `REPDTE`, `failed` and the score column.
#' @param score_column Name of the score column.
#' @param k Banks on the list per quarter.
#' @return A data frame per quarter, plus overall totals as attributes.
#' @export
watch_list <- function(data, score_column = "score", k = 100) {
  per <- lapply(split(data, data$REPDTE), function(q) {
    top <- q[order(-q[[score_column]], q$CERT), ][seq_len(min(k, nrow(q))), ]
    data.frame(
      REPDTE = q$REPDTE[1],
      banks = nrow(q),
      failing = sum(q$failed),
      caught = sum(top$failed)
    )
  })
  out <- do.call(rbind, per)
  rownames(out) <- NULL
  attr(out, "recall") <- sum(out$caught) / sum(out$failing)
  attr(out, "precision") <- sum(out$caught) / (k * nrow(out))
  out
}

#' Brier score
#'
#' @param p Predicted probabilities.
#' @param label Logical labels.
#' @return Mean squared error of the probabilities.
#' @export
brier <- function(p, label) mean((p - as.numeric(label))^2)
