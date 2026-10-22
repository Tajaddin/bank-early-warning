#' Label bank-quarters by failure within a year of the data becoming public
#'
#' A Call Report for quarter end `REPDTE` is public about `publication_lag_days`
#' later. A bank-quarter is positive when the bank failed in the
#' `horizon_days` after that date. Bank-quarters whose bank failed before the data
#' was public are dropped: no one could have acted on them, so counting them as
#' caught would flatter the model.
#'
#' @param features Output of [build_features()].
#' @param failures A data frame with `CERT` and `FAILDATE` (Date).
#' @param publication_lag_days Days from quarter end to public data.
#' @param horizon_days Days after publication in which a failure counts.
#' @return `features` with a logical `failed` column and the bank's `FAILDATE`.
#' @export
label_failures <- function(features, failures, publication_lag_days = 60, horizon_days = 365) {
  fails <- as.data.frame(failures)[!is.na(failures$CERT) & !is.na(failures$FAILDATE), c("CERT", "FAILDATE")]
  fails <- stats::aggregate(FAILDATE ~ CERT, data = fails, FUN = min)  # first failure of a certificate
  x <- merge(features, fails, by = "CERT", all.x = TRUE)
  public <- x$REPDTE + publication_lag_days
  too_late <- !is.na(x$FAILDATE) & x$FAILDATE <= public
  x <- x[!too_late, ]
  public <- public[!too_late]
  x$failed <- !is.na(x$FAILDATE) & x$FAILDATE <= public + horizon_days
  x <- x[order(x$REPDTE, x$CERT), ]
  rownames(x) <- NULL
  x
}

#' Split labelled bank-quarters by report date
#'
#' @param labelled Output of [label_failures()].
#' @param from,to Inclusive `Date` bounds on `REPDTE`.
#' @return The rows in range.
#' @export
period <- function(labelled, from, to) {
  labelled[labelled$REPDTE >= as.Date(from) & labelled$REPDTE <= as.Date(to), ]
}
