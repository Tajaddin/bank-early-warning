test_that("quarter ends move by whole years", {
  expect_equal(shift_years(as.Date(c("2009-12-31", "2009-06-30")), -1), as.Date(c("2008-12-31", "2008-06-30")))
})

test_that("features need the filing a year earlier", {
  f <- build_features(make_financials())
  expect_equal(nrow(f), 8) # 2 banks x the 4 quarters of 2009
  expect_equal(unique(f$REPDTE), quarter_ends[5:8])
  expect_equal(names(f), c("CERT", "REPDTE", FEATURES))
})

test_that("features are computed as defined", {
  f <- build_features(make_financials())
  b2 <- f[f$CERT == 2 & f$REPDTE == as.Date("2009-12-31"), ]
  expect_equal(b2$roa, -5)
  expect_equal(b2$d_roa, -5 - (-1)) # vs 2008-12-31
  expect_equal(b2$d_ncl, 13 - 5)
  expect_equal(b2$brokered, 100 * 0.05 / 0.8)
  expect_equal(b2$log_assets, log(1464.1))
  expect_equal(b2$growth, log(1464.1 / 1000))
  expect_equal(b2$lev, 1)
})

test_that("a missing input drops the row, a missing column stops", {
  fin <- make_financials()
  fin$DEP[fin$CERT == 1 & fin$REPDTE == as.Date("2009-03-31")] <- 0
  expect_equal(nrow(build_features(fin)), 7)
  expect_error(build_features(fin[, names(fin) != "ROA"]), "ROA")
})
