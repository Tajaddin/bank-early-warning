-- Bank early warning on MySQL 9.7 (LTS). Doubles throughout, so scores match R's IEEE arithmetic.

CREATE TABLE IF NOT EXISTS financials (
  cert     INT    NOT NULL,
  repdte   DATE   NOT NULL,
  asset    DOUBLE NOT NULL,
  dep      DOUBLE NOT NULL,
  bro      DOUBLE NULL,
  eqv      DOUBLE NOT NULL,
  rbc1aaj  DOUBLE NOT NULL,
  nclnlsr  DOUBLE NOT NULL,
  lnatresr DOUBLE NOT NULL,
  elnatry  DOUBLE NULL,
  roa      DOUBLE NOT NULL,
  nimy     DOUBLE NOT NULL,
  eeffr    DOUBLE NOT NULL,
  lnlsdepr DOUBLE NOT NULL,
  PRIMARY KEY (cert, repdte),
  INDEX ix_financials_repdte (repdte)
);

CREATE TABLE IF NOT EXISTS failures (
  cert     INT          NOT NULL,
  faildate DATE         NOT NULL,
  name     VARCHAR(200) NOT NULL,
  PRIMARY KEY (cert, faildate)
);

-- One row per feature: the coefficient and the clipping bounds fitted in R (r/bankwarn), plus the intercept.
CREATE TABLE IF NOT EXISTS model_feature (
  feature     VARCHAR(20) NOT NULL PRIMARY KEY,
  coefficient DOUBLE      NOT NULL,
  lower_bound DOUBLE      NOT NULL,
  upper_bound DOUBLE      NOT NULL
);

CREATE TABLE IF NOT EXISTS model_intercept (
  id        TINYINT NOT NULL PRIMARY KEY CHECK (id = 1),
  intercept DOUBLE  NOT NULL
);

CREATE TABLE IF NOT EXISTS risk_score (
  cert   INT    NOT NULL,
  repdte DATE   NOT NULL,
  score  DOUBLE NOT NULL,
  PRIMARY KEY (cert, repdte)
);

-- The features, as r/bankwarn/R/features.R defines them: a bank-quarter needs its filing a year earlier, and a
-- row with any missing input is left out.
CREATE OR REPLACE VIEW bank_features AS
SELECT f.cert,
       f.repdte,
       f.eqv,
       f.rbc1aaj                      AS lev,
       f.nclnlsr                      AS ncl,
       f.lnatresr                     AS reserve,
       f.elnatry                      AS prov,
       f.roa,
       f.nimy                         AS nim,
       f.eeffr                        AS eff,
       f.lnlsdepr                     AS ltd,
       100 * f.bro / f.dep            AS brokered,
       LN(f.asset)                    AS log_assets,
       f.roa - p.roa                  AS d_roa,
       f.nclnlsr - p.nclnlsr          AS d_ncl,
       LN(f.asset / p.asset)          AS growth
  FROM financials f
  JOIN financials p
    ON p.cert = f.cert
   AND p.repdte = DATE_SUB(f.repdte, INTERVAL 1 YEAR)
 WHERE f.dep > 0 AND f.asset > 0 AND p.asset > 0
   AND f.bro IS NOT NULL AND f.elnatry IS NOT NULL;
