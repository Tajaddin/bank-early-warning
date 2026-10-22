# Small, hand-checkable Call Report rows: bank 1 is healthy, bank 2 deteriorates and fails.
quarter_ends <- as.Date(c("2008-03-31", "2008-06-30", "2008-09-30", "2008-12-31",
                          "2009-03-31", "2009-06-30", "2009-09-30", "2009-12-31"))

make_financials <- function() {
  bank <- function(cert, roa, ncl, eqv, asset) {
    data.frame(
      CERT = cert, REPDTE = quarter_ends, ASSET = asset, DEP = asset * 0.8, BRO = asset * 0.05,
      EQV = eqv, RBC1AAJ = eqv - 1, NCLNLSR = ncl, LNATRESR = 1.5, ELNATRY = 0.2,
      ROA = roa, NIMY = 3.5, EEFFR = 70, LNLSDEPR = 80
    )
  }
  rbind(
    bank(1, roa = rep(1, 8), ncl = rep(0.5, 8), eqv = rep(10, 8), asset = rep(1000, 8)),
    bank(2, roa = c(1, 0.5, 0, -1, -2, -3, -4, -5), ncl = c(1, 2, 3, 5, 7, 9, 11, 13),
         eqv = c(9, 8, 7, 6, 5, 4, 3, 2), asset = c(1000, 1000, 1000, 1000, 1100, 1210, 1331, 1464.1))
  )
}

make_failures <- function() data.frame(CERT = c(2, 99), FAILDATE = as.Date(c("2010-06-01", "2009-01-01")))
