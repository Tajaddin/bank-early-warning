-- Bank early warning on SQL Server 2025 (Developer edition). FLOAT is IEEE double, as in R.
-- Batches are separated by GO lines; the loader sends them one at a time.

IF OBJECT_ID('dbo.financials') IS NULL
CREATE TABLE dbo.financials (
  cert     INT   NOT NULL,
  repdte   DATE  NOT NULL,
  asset    FLOAT NOT NULL,
  dep      FLOAT NOT NULL,
  bro      FLOAT NULL,
  eqv      FLOAT NOT NULL,
  rbc1aaj  FLOAT NOT NULL,
  nclnlsr  FLOAT NOT NULL,
  lnatresr FLOAT NOT NULL,
  elnatry  FLOAT NULL,
  roa      FLOAT NOT NULL,
  nimy     FLOAT NOT NULL,
  eeffr    FLOAT NOT NULL,
  lnlsdepr FLOAT NOT NULL,
  CONSTRAINT pk_financials PRIMARY KEY (cert, repdte),
  INDEX ix_financials_repdte (repdte)
);
GO

IF OBJECT_ID('dbo.failures') IS NULL
CREATE TABLE dbo.failures (
  cert     INT           NOT NULL,
  faildate DATE          NOT NULL,
  name     NVARCHAR(200) NOT NULL,
  CONSTRAINT pk_failures PRIMARY KEY (cert, faildate)
);
GO

IF OBJECT_ID('dbo.model_feature') IS NULL
CREATE TABLE dbo.model_feature (
  feature     VARCHAR(20) NOT NULL CONSTRAINT pk_model_feature PRIMARY KEY,
  coefficient FLOAT       NOT NULL,
  lower_bound FLOAT       NOT NULL,
  upper_bound FLOAT       NOT NULL
);
GO

IF OBJECT_ID('dbo.model_intercept') IS NULL
CREATE TABLE dbo.model_intercept (
  id        TINYINT NOT NULL CONSTRAINT pk_model_intercept PRIMARY KEY CHECK (id = 1),
  intercept FLOAT   NOT NULL
);
GO

IF OBJECT_ID('dbo.risk_score') IS NULL
CREATE TABLE dbo.risk_score (
  cert   INT   NOT NULL,
  repdte DATE  NOT NULL,
  score  FLOAT NOT NULL,
  CONSTRAINT pk_risk_score PRIMARY KEY (cert, repdte)
);
GO

-- The features, as r/bankwarn/R/features.R defines them.
CREATE OR ALTER VIEW dbo.bank_features AS
SELECT f.cert,
       f.repdte,
       f.eqv,
       f.rbc1aaj              AS lev,
       f.nclnlsr              AS ncl,
       f.lnatresr             AS reserve,
       f.elnatry              AS prov,
       f.roa,
       f.nimy                 AS nim,
       f.eeffr                AS eff,
       f.lnlsdepr             AS ltd,
       100 * f.bro / f.dep    AS brokered,
       LOG(f.asset)           AS log_assets,
       f.roa - p.roa          AS d_roa,
       f.nclnlsr - p.nclnlsr  AS d_ncl,
       LOG(f.asset / p.asset) AS growth
  FROM dbo.financials f
  JOIN dbo.financials p
    ON p.cert = f.cert
   AND p.repdte = DATEADD(year, -1, f.repdte)
 WHERE f.dep > 0 AND f.asset > 0 AND p.asset > 0
   AND f.bro IS NOT NULL AND f.elnatry IS NOT NULL;
GO

-- The model as one row.
CREATE OR ALTER VIEW dbo.model_params AS
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
  FROM dbo.model_feature;
GO
