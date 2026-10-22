test_that("auc by hand", {
  expect_equal(auc(c(0.9, 0.8, 0.3, 0.1), c(TRUE, FALSE, TRUE, FALSE)), 0.75)
  expect_equal(auc(c(1, 1), c(TRUE, FALSE)), 0.5) # a tie counts half
  expect_true(is.na(auc(c(1, 2), c(TRUE, TRUE))))
})

test_that("the interval resamples banks and contains the estimate", {
  set.seed(3)
  score <- stats::runif(400)
  label <- stats::runif(400) < score / 2
  ci <- auc_interval(score, label, rep(1:100, 4), n = 200)
  expect_lt(ci[1], auc(score, label))
  expect_gt(ci[2], auc(score, label))
})

test_that("the watch list counts failures among each quarter's top k", {
  d <- data.frame(
    CERT = 1:6, REPDTE = as.Date(rep(c("2011-03-31", "2011-06-30"), each = 3)),
    score = c(0.9, 0.5, 0.1, 0.2, 0.8, 0.7), failed = c(TRUE, FALSE, TRUE, FALSE, FALSE, TRUE)
  )
  w <- watch_list(d, "score", k = 1)
  expect_equal(w$caught, c(1, 0))
  expect_equal(w$failing, c(2, 1))
  expect_equal(attr(w, "recall"), 1 / 3)
  expect_equal(attr(w, "precision"), 1 / 2)
  expect_equal(brier(c(1, 0), c(TRUE, TRUE)), 0.5)
})
