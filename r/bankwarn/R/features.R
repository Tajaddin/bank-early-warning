#' Model features
#'
#' The features, in the order the model and every SQL engine use them. Each is a
#' Call Report ratio, a ratio of two reported amounts, or a four-quarter change.
#' The SQL in `sql/` computes the same columns from the same raw fields.
#'
#' @export
FEATURES <- c(
  "eqv", "lev", "ncl", "reserve", "prov", "roa", "nim", "eff", "ltd",
  "brokered", "log_assets", "d_roa", "d_ncl", "growth"
)

#' Shift quarter-end dates by whole years
#'
#' Quarter ends (03-31, 06-30, 09-30, 12-31) exist in every year, so moving the
#' year is exact; this is what `DATE_SUB(d, INTERVAL 1 YEAR)`, `DATEADD(year, -1, d)`
#' and `ADD_MONTHS(d, -12)` do in the three SQL engines for these dates.
#'
#' @param d A `Date` vector of quarter ends.
#' @param years Whole years to add (negative to go back).
#' @return A `Date` vector.
#' @export
shift_years <- function(d, years) {
  as.Date(paste0(as.integer(format(d, "%Y")) + years, format(d, "-%m-%d")))
}

#' Build the features for every bank-quarter that has a filing a year earlier
#'
#' @param financials A data frame with the FDIC fields `CERT`, `REPDTE` (Date),
#'   `ASSET`, `DEP`, `BRO`, `EQV`, `RBC1AAJ`, `NCLNLSR`, `LNATRESR`, `ELNATRY`,
#'   `ROA`, `NIMY`, `EEFFR` and `LNLSDEPR`.
#' @return A data frame with `CERT`, `REPDTE` and one column per [FEATURES];
#'   rows with any missing feature are dropped, as the SQL drops them.
#' @export
build_features <- function(financials) {
  required <- c("CERT", "REPDTE", "ASSET", "DEP", "BRO", "EQV", "RBC1AAJ", "NCLNLSR",
                "LNATRESR", "ELNATRY", "ROA", "NIMY", "EEFFR", "LNLSDEPR")
  missing <- setdiff(required, names(financials))
  if (length(missing) > 0) stop("financials lacks: ", paste(missing, collapse = ", "))

  f <- as.data.frame(financials)[, required]
  year_ago <- f[, c("CERT", "REPDTE", "ROA", "NCLNLSR", "ASSET")]
  year_ago$REPDTE <- shift_years(year_ago$REPDTE, 1)  # last year's row, keyed on this year's date
  names(year_ago) <- c("CERT", "REPDTE", "ROA_ago", "NCL_ago", "ASSET_ago")
  x <- merge(f, year_ago, by = c("CERT", "REPDTE"))

  positive <- function(v) ifelse(!is.na(v) & v > 0, v, NA_real_)
  out <- data.frame(
    CERT = x$CERT,
    REPDTE = x$REPDTE,
    eqv = x$EQV,
    lev = x$RBC1AAJ,
    ncl = x$NCLNLSR,
    reserve = x$LNATRESR,
    prov = x$ELNATRY,
    roa = x$ROA,
    nim = x$NIMY,
    eff = x$EEFFR,
    ltd = x$LNLSDEPR,
    brokered = 100 * x$BRO / positive(x$DEP),
    log_assets = log(positive(x$ASSET)),
    d_roa = x$ROA - x$ROA_ago,
    d_ncl = x$NCLNLSR - x$NCL_ago,
    growth = log(positive(x$ASSET) / positive(x$ASSET_ago))
  )
  out <- out[stats::complete.cases(out[, FEATURES]), ]
  out <- out[order(out$REPDTE, out$CERT), ]
  rownames(out) <- NULL
  out
}
