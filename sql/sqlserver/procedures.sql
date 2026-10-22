-- Scoring and the watch list in T-SQL.

CREATE OR ALTER PROCEDURE dbo.score_quarter @repdte DATE
AS
BEGIN
  SET NOCOUNT ON;
  SET XACT_ABORT ON;  -- any error rolls the quarter back as a whole
  BEGIN TRANSACTION;
    DELETE FROM dbo.risk_score WHERE repdte = @repdte;
    -- the logistic model: clip each feature to its training bounds, a dot product, the logistic function
    INSERT INTO dbo.risk_score (cert, repdte, score)
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
      FROM dbo.bank_features b
      CROSS JOIN dbo.model_intercept m
      CROSS JOIN dbo.model_params c
     WHERE b.repdte = @repdte;
    SELECT @@ROWCOUNT AS scored;
  COMMIT TRANSACTION;
END;
GO

CREATE OR ALTER PROCEDURE dbo.watch_list @repdte DATE, @k INT
AS
BEGIN
  SET NOCOUNT ON;
  SELECT TOP (@k) s.cert, s.score, b.eqv, b.lev, b.ncl, b.roa
    FROM dbo.risk_score s
    JOIN dbo.bank_features b ON b.cert = s.cert AND b.repdte = s.repdte
   WHERE s.repdte = @repdte
   ORDER BY s.score DESC, s.cert;
END;
GO
