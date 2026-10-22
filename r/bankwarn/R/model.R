#' Fit the logistic early-warning model
#'
#' Each feature is clipped to its `clip` quantiles in the training data (Call
#' Report ratios have extreme values in tiny or failing banks), then a logistic
#' regression is fitted on the clipped values. The bounds travel with the
#' coefficients, so a SQL engine clips exactly as R does.
#'
#' @param train Labelled training rows ([label_failures()] then [period()]).
#' @param features Feature names to use.
#' @param clip Lower and upper quantile for clipping.
#' @return A `bankwarn_model`: intercept, coefficients and clipping bounds.
#' @export
fit_warning_model <- function(train, features = FEATURES, clip = c(0.01, 0.99)) {
  if (!any(train$failed)) stop("no failures in the training rows")
  bounds <- lapply(features, function(f) unname(stats::quantile(train[[f]], clip, names = FALSE, type = 7)))
  names(bounds) <- features
  x <- clip_features(train, features, bounds)
  data <- cbind(x, failed = as.integer(train$failed))
  fit <- stats::glm(stats::reformulate(features, response = "failed"), family = stats::binomial(), data = data)
  if (!fit$converged) stop("the logistic regression did not converge")
  co <- stats::coef(fit)
  structure(
    list(
      intercept = unname(co[["(Intercept)"]]),
      coefficients = co[features],
      lower = vapply(bounds, `[`, numeric(1), 1),
      upper = vapply(bounds, `[`, numeric(1), 2),
      features = features,
      n_train = nrow(train),
      n_failed = sum(train$failed),
      fit = fit
    ),
    class = "bankwarn_model"
  )
}

#' Clip features to bounds
#'
#' @param data A data frame with the feature columns.
#' @param features Feature names.
#' @param bounds A named list of `c(lower, upper)`.
#' @return A data frame of the clipped features.
#' @export
clip_features <- function(data, features, bounds) {
  out <- lapply(features, function(f) pmin(pmax(data[[f]], bounds[[f]][1]), bounds[[f]][2]))
  names(out) <- features
  as.data.frame(out)
}

#' Probability of failure within the horizon
#'
#' Computed the way the SQL engines compute it: clip, a dot product, the logistic
#' function. Not through `predict.glm`, so that the arithmetic matches.
#'
#' @param model A `bankwarn_model`.
#' @param data Rows with the feature columns.
#' @return A numeric vector of probabilities.
#' @export
score <- function(model, data) {
  bounds <- Map(c, model$lower, model$upper)
  x <- clip_features(data, model$features, bounds)
  logit <- model$intercept + as.vector(as.matrix(x) %*% model$coefficients[model$features])
  1 / (1 + exp(-logit))
}

#' @export
print.bankwarn_model <- function(x, ...) {
  cat("bankwarn model:", length(x$features), "features,", x$n_train, "training rows,", x$n_failed, "failed\n")
  invisible(x)
}

#' Write the model for the SQL engines
#'
#' One row per feature with its coefficient and clipping bounds, plus the
#' intercept, as JSON with every digit R holds (17 significant digits), so the
#' engines load exactly the doubles R used.
#'
#' @param model A `bankwarn_model`.
#' @param path File to write.
#' @return `path`, invisibly.
#' @export
export_model <- function(model, path) {
  rows <- data.frame(
    feature = model$features,
    coefficient = unname(model$coefficients[model$features]),
    lower = unname(model$lower),
    upper = unname(model$upper)
  )
  doc <- list(intercept = model$intercept, features = rows, n_train = model$n_train, n_failed = model$n_failed)
  # I(17): 17 significant digits round-trip any double; digits = NA writes 15 and loses the last bits
  writeLines(jsonlite::toJSON(doc, digits = I(17), auto_unbox = TRUE, pretty = TRUE), path, useBytes = TRUE)
  invisible(path)
}
