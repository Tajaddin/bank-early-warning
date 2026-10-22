-- Scoring and the watch list. Each CREATE is one statement (the loader sends them one at a time, no DELIMITER).

DROP PROCEDURE IF EXISTS score_quarter;
CREATE PROCEDURE score_quarter(IN p_repdte DATE)
BEGIN
  -- the logistic model: clip each feature to its training bounds, a dot product, the logistic function
  DELETE FROM risk_score WHERE repdte = p_repdte;
  INSERT INTO risk_score (cert, repdte, score)
  SELECT b.cert, b.repdte,
         1 / (1 + EXP(-(m.intercept
           + c.eqv        * LEAST(GREATEST(b.eqv,        c.eqv_lo),        c.eqv_hi)
           + c.lev        * LEAST(GREATEST(b.lev,        c.lev_lo),        c.lev_hi)
           + c.ncl        * LEAST(GREATEST(b.ncl,        c.ncl_lo),        c.ncl_hi)
           + c.reserve    * LEAST(GREATEST(b.reserve,    c.reserve_lo),    c.reserve_hi)
           + c.prov       * LEAST(GREATEST(b.prov,       c.prov_lo),       c.prov_hi)
           + c.roa        * LEAST(GREATEST(b.roa,        c.roa_lo),        c.roa_hi)
           + c.nim        * LEAST(GREATEST(b.nim,        c.nim_lo),        c.nim_hi)
           + c.eff        * LEAST(GREATEST(b.eff,        c.eff_lo),        c.eff_hi)
           + c.ltd        * LEAST(GREATEST(b.ltd,        c.ltd_lo),        c.ltd_hi)
           + c.brokered   * LEAST(GREATEST(b.brokered,   c.brokered_lo),   c.brokered_hi)
           + c.log_assets * LEAST(GREATEST(b.log_assets, c.log_assets_lo), c.log_assets_hi)
           + c.d_roa      * LEAST(GREATEST(b.d_roa,      c.d_roa_lo),      c.d_roa_hi)
           + c.d_ncl      * LEAST(GREATEST(b.d_ncl,      c.d_ncl_lo),      c.d_ncl_hi)
           + c.growth     * LEAST(GREATEST(b.growth,     c.growth_lo),     c.growth_hi))))
    FROM bank_features b
    CROSS JOIN model_intercept m
    CROSS JOIN model_params c
   WHERE b.repdte = p_repdte;
  SELECT ROW_COUNT() AS scored;
END;

-- the model as one row (one column per coefficient and bound), so scoring is a single pass over the features
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

DROP PROCEDURE IF EXISTS watch_list;
CREATE PROCEDURE watch_list(IN p_repdte DATE, IN p_k INT)
BEGIN
  -- the k riskiest banks of a quarter, with the ratios a supervisor looks at first
  SELECT s.cert, s.score, b.eqv, b.lev, b.ncl, b.roa
    FROM risk_score s
    JOIN bank_features b ON b.cert = s.cert AND b.repdte = s.repdte
   WHERE s.repdte = p_repdte
   ORDER BY s.score DESC, s.cert
   LIMIT p_k;
END;
