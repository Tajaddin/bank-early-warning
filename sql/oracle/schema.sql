-- Bank early warning on Oracle Database 23ai Free. BINARY_DOUBLE, not NUMBER: IEEE doubles, so LN, EXP and the
-- dot product round as they do in R. Statements end with ';' and PL/SQL blocks with a '/' line.

CREATE TABLE IF NOT EXISTS financials (
  cert     NUMBER(10)    NOT NULL,
  repdte   DATE          NOT NULL,
  asset    BINARY_DOUBLE NOT NULL,
  dep      BINARY_DOUBLE NOT NULL,
  bro      BINARY_DOUBLE,
  eqv      BINARY_DOUBLE NOT NULL,
  rbc1aaj  BINARY_DOUBLE NOT NULL,
  nclnlsr  BINARY_DOUBLE NOT NULL,
  lnatresr BINARY_DOUBLE NOT NULL,
  elnatry  BINARY_DOUBLE,
  roa      BINARY_DOUBLE NOT NULL,
  nimy     BINARY_DOUBLE NOT NULL,
  eeffr    BINARY_DOUBLE NOT NULL,
  lnlsdepr BINARY_DOUBLE NOT NULL,
  CONSTRAINT pk_financials PRIMARY KEY (cert, repdte)
);

CREATE INDEX IF NOT EXISTS ix_financials_repdte ON financials (repdte);

CREATE TABLE IF NOT EXISTS failures (
  cert     NUMBER(10)     NOT NULL,
  faildate DATE           NOT NULL,
  name     VARCHAR2(200)  NOT NULL,
  CONSTRAINT pk_failures PRIMARY KEY (cert, faildate)
);

CREATE TABLE IF NOT EXISTS model_feature (
  feature     VARCHAR2(20)  NOT NULL CONSTRAINT pk_model_feature PRIMARY KEY,
  coefficient BINARY_DOUBLE NOT NULL,
  lower_bound BINARY_DOUBLE NOT NULL,
  upper_bound BINARY_DOUBLE NOT NULL
);

CREATE TABLE IF NOT EXISTS model_intercept (
  id        NUMBER(1)     NOT NULL CONSTRAINT pk_model_intercept PRIMARY KEY CHECK (id = 1),
  intercept BINARY_DOUBLE NOT NULL
);

CREATE TABLE IF NOT EXISTS risk_score (
  cert   NUMBER(10)    NOT NULL,
  repdte DATE          NOT NULL,
  score  BINARY_DOUBLE NOT NULL,
  CONSTRAINT pk_risk_score PRIMARY KEY (cert, repdte)
);

-- The features, as r/bankwarn/R/features.R defines them. ADD_MONTHS keeps a month-end date at month end, which is
-- what a quarter end needs.
CREATE OR REPLACE VIEW bank_features AS
SELECT f.cert,
       f.repdte,
       f.eqv,
       f.rbc1aaj                         AS lev,
       f.nclnlsr                         AS ncl,
       f.lnatresr                        AS reserve,
       f.elnatry                         AS prov,
       f.roa,
       f.nimy                            AS nim,
       f.eeffr                           AS eff,
       f.lnlsdepr                        AS ltd,
       100D * f.bro / f.dep              AS brokered,
       LN(f.asset)                       AS log_assets,
       f.roa - p.roa                     AS d_roa,
       f.nclnlsr - p.nclnlsr             AS d_ncl,
       LN(f.asset / p.asset)             AS growth
  FROM financials f
  JOIN financials p
    ON p.cert = f.cert
   AND p.repdte = ADD_MONTHS(f.repdte, -12)
 WHERE f.dep > 0 AND f.asset > 0 AND p.asset > 0
   AND f.bro IS NOT NULL AND f.elnatry IS NOT NULL;

CREATE OR REPLACE VIEW model_params AS
SELECT MAX(CASE feature WHEN 'eqv'        THEN coefficient END) AS eqv,
       MAX(CASE feature WHEN 'eqv'        THEN lower_bound END) AS eqv_lo,
       MAX(CASE feature WHEN 'eqv'        THEN upper_bound END) AS eqv_hi,
       MAX(CASE feature WHEN 'lev'        THEN coefficient END) AS lev,
       MAX(CASE feature WHEN 'lev'        THEN lower_bound END) AS lev_lo,
       MAX(CASE feature WHEN 'lev'        THEN upper_bound END) AS lev_hi,
       MAX(CASE feature WHEN 'ncl'        THEN coefficient END) AS ncl,
       MAX(CASE feature WHEN 'ncl'        THEN lower_bound END) AS ncl_lo,
       MAX(CASE feature WHEN 'ncl'        THEN upper_bound END) AS ncl_hi,
       MAX(CASE feature WHEN 'reserve'    THEN coefficient END) AS reserve,
       MAX(CASE feature WHEN 'reserve'    THEN lower_bound END) AS reserve_lo,
       MAX(CASE feature WHEN 'reserve'    THEN upper_bound END) AS reserve_hi,
       MAX(CASE feature WHEN 'prov'       THEN coefficient END) AS prov,
       MAX(CASE feature WHEN 'prov'       THEN lower_bound END) AS prov_lo,
       MAX(CASE feature WHEN 'prov'       THEN upper_bound END) AS prov_hi,
       MAX(CASE feature WHEN 'roa'        THEN coefficient END) AS roa,
       MAX(CASE feature WHEN 'roa'        THEN lower_bound END) AS roa_lo,
       MAX(CASE feature WHEN 'roa'        THEN upper_bound END) AS roa_hi,
       MAX(CASE feature WHEN 'nim'        THEN coefficient END) AS nim,
       MAX(CASE feature WHEN 'nim'        THEN lower_bound END) AS nim_lo,
       MAX(CASE feature WHEN 'nim'        THEN upper_bound END) AS nim_hi,
       MAX(CASE feature WHEN 'eff'        THEN coefficient END) AS eff,
       MAX(CASE feature WHEN 'eff'        THEN lower_bound END) AS eff_lo,
       MAX(CASE feature WHEN 'eff'        THEN upper_bound END) AS eff_hi,
       MAX(CASE feature WHEN 'ltd'        THEN coefficient END) AS ltd,
       MAX(CASE feature WHEN 'ltd'        THEN lower_bound END) AS ltd_lo,
       MAX(CASE feature WHEN 'ltd'        THEN upper_bound END) AS ltd_hi,
       MAX(CASE feature WHEN 'brokered'   THEN coefficient END) AS brokered,
       MAX(CASE feature WHEN 'brokered'   THEN lower_bound END) AS brokered_lo,
       MAX(CASE feature WHEN 'brokered'   THEN upper_bound END) AS brokered_hi,
       MAX(CASE feature WHEN 'log_assets' THEN coefficient END) AS log_assets,
       MAX(CASE feature WHEN 'log_assets' THEN lower_bound END) AS log_assets_lo,
       MAX(CASE feature WHEN 'log_assets' THEN upper_bound END) AS log_assets_hi,
       MAX(CASE feature WHEN 'd_roa'      THEN coefficient END) AS d_roa,
       MAX(CASE feature WHEN 'd_roa'      THEN lower_bound END) AS d_roa_lo,
       MAX(CASE feature WHEN 'd_roa'      THEN upper_bound END) AS d_roa_hi,
       MAX(CASE feature WHEN 'd_ncl'      THEN coefficient END) AS d_ncl,
       MAX(CASE feature WHEN 'd_ncl'      THEN lower_bound END) AS d_ncl_lo,
       MAX(CASE feature WHEN 'd_ncl'      THEN upper_bound END) AS d_ncl_hi,
       MAX(CASE feature WHEN 'growth'     THEN coefficient END) AS growth,
       MAX(CASE feature WHEN 'growth'     THEN lower_bound END) AS growth_lo,
       MAX(CASE feature WHEN 'growth'     THEN upper_bound END) AS growth_hi
  FROM model_feature;
