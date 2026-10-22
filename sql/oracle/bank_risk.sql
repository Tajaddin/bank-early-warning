-- The scoring package. Tested with utPLSQL (sql/oracle/test_bank_risk.sql).

CREATE OR REPLACE PACKAGE bank_risk AS
  -- the clipped feature: what score_quarter applies to each input
  FUNCTION clip(p_value BINARY_DOUBLE, p_lower BINARY_DOUBLE, p_upper BINARY_DOUBLE) RETURN BINARY_DOUBLE DETERMINISTIC;

  -- the logistic function, as R computes it: 1 / (1 + exp(-z))
  FUNCTION logistic(p_z BINARY_DOUBLE) RETURN BINARY_DOUBLE DETERMINISTIC;

  -- replace the scores of one quarter; returns the number of banks scored
  FUNCTION score_quarter(p_repdte DATE) RETURN PLS_INTEGER;

  -- the k riskiest banks of a quarter
  FUNCTION watch_list(p_repdte DATE, p_k PLS_INTEGER) RETURN SYS_REFCURSOR;
END bank_risk;
/

CREATE OR REPLACE PACKAGE BODY bank_risk AS
  FUNCTION clip(p_value BINARY_DOUBLE, p_lower BINARY_DOUBLE, p_upper BINARY_DOUBLE) RETURN BINARY_DOUBLE DETERMINISTIC IS
  BEGIN
    RETURN LEAST(GREATEST(p_value, p_lower), p_upper);
  END clip;

  FUNCTION logistic(p_z BINARY_DOUBLE) RETURN BINARY_DOUBLE DETERMINISTIC IS
  BEGIN
    RETURN 1D / (1D + EXP(-p_z));
  END logistic;

  FUNCTION score_quarter(p_repdte DATE) RETURN PLS_INTEGER IS
    l_scored PLS_INTEGER;
  BEGIN
    DELETE FROM risk_score WHERE repdte = p_repdte;
    INSERT INTO risk_score (cert, repdte, score)
    SELECT b.cert, b.repdte,
           1D / (1D + EXP(-(m.intercept
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
    l_scored := SQL%ROWCOUNT;
    COMMIT;
    RETURN l_scored;
  END score_quarter;

  FUNCTION watch_list(p_repdte DATE, p_k PLS_INTEGER) RETURN SYS_REFCURSOR IS
    l_rows SYS_REFCURSOR;
  BEGIN
    OPEN l_rows FOR
      SELECT s.cert, s.score, b.eqv, b.lev, b.ncl, b.roa
        FROM risk_score s
        JOIN bank_features b ON b.cert = s.cert AND b.repdte = s.repdte
       WHERE s.repdte = p_repdte
       ORDER BY s.score DESC, s.cert
       FETCH FIRST p_k ROWS ONLY;
    RETURN l_rows;
  END watch_list;
END bank_risk;
/
