test_that("a failure counts within a year of the data becoming public", {
  l <- label_failures(build_features(make_financials()), make_failures())
  b2 <- l[l$CERT == 2, ]
  # failed 2010-06-01: public dates are quarter end + 60 days; the horizon is 365 days after that
  expect_equal(b2$failed, c(FALSE, TRUE, TRUE, TRUE))
  expect_false(any(l$failed[l$CERT == 1]))
})

test_that("quarters whose data came out after the failure are dropped", {
  fails <- data.frame(CERT = 2, FAILDATE = as.Date("2009-11-15")) # before 2009-09-30 + 60 days
  l <- label_failures(build_features(make_financials()), fails)
  expect_equal(l$REPDTE[l$CERT == 2], as.Date(c("2009-03-31", "2009-06-30")))
  expect_true(all(l$failed[l$CERT == 2]))
})

test_that("periods are inclusive", {
  l <- label_failures(build_features(make_financials()), make_failures())
  expect_equal(unique(period(l, "2009-06-30", "2009-09-30")$REPDTE), as.Date(c("2009-06-30", "2009-09-30")))
})
