-- utPLSQL 3 tests for the bank_risk package. Run on an empty schema, before the real model and data are loaded
-- (scripts/oracle_tests.py): score_quarter commits, so the suite cleans up after itself instead of rolling back.

CREATE OR REPLACE PACKAGE test_bank_risk AS
  --%suite(bank_risk: scoring the early-warning model in PL/SQL)
  --%rollback(manual)

  --%beforeeach
  PROCEDURE two_banks_and_a_model;

  --%aftereach
  PROCEDURE clean_up;

  --%test(clip keeps a value inside its bounds)
  PROCEDURE clip_bounds;

  --%test(the logistic of 0 is one half, and of -z is one minus that of z)
  PROCEDURE logistic_values;

  --%test(a quarter scores every bank with a filing a year earlier, and no other)
  PROCEDURE scores_eligible_banks;

  --%test(a score is the clipped dot product through the logistic function, worked by hand)
  PROCEDURE score_by_hand;

  --%test(scoring a quarter again replaces its scores)
  PROCEDURE rescoring_replaces;

  --%test(the watch list puts the highest score first and stops at k)
  PROCEDURE watch_list_order;
END test_bank_risk;
/

CREATE OR REPLACE PACKAGE BODY test_bank_risk AS
  c_q CONSTANT DATE := DATE '1999-12-31';

  PROCEDURE filing(p_cert NUMBER, p_repdte DATE, p_eqv BINARY_DOUBLE) IS
  BEGIN
    INSERT INTO financials (cert, repdte, asset, dep, bro, eqv, rbc1aaj, nclnlsr, lnatresr, elnatry, roa, nimy, eeffr, lnlsdepr)
    VALUES (p_cert, p_repdte, 1000D, 800D, 40D, p_eqv, 8D, 1D, 1.5D, 0.2D, 1D, 3.5D, 70D, 80D);
  END filing;

  PROCEDURE two_banks_and_a_model IS
  BEGIN
    -- bank -1: thick capital (30%, clipped to 20); bank -2: 10%; bank -3: no filing a year earlier
    filing(-1, c_q, 30D); filing(-1, ADD_MONTHS(c_q, -12), 25D);
    filing(-2, c_q, 10D); filing(-2, ADD_MONTHS(c_q, -12), 12D);
    filing(-3, c_q, 5D);
    -- intercept -1; only equity counts: coefficient -0.1, clipped to [0, 20]
    DELETE FROM model_feature;
    DELETE FROM model_intercept;
    INSERT INTO model_intercept (id, intercept) VALUES (1, -1D);
    INSERT INTO model_feature (feature, coefficient, lower_bound, upper_bound)
      SELECT column_value, CASE column_value WHEN 'eqv' THEN -0.1D ELSE 0D END,
             CASE column_value WHEN 'eqv' THEN 0D ELSE -1D * BINARY_DOUBLE_MAX_NORMAL END,
             CASE column_value WHEN 'eqv' THEN 20D ELSE BINARY_DOUBLE_MAX_NORMAL END
        FROM TABLE(sys.odcivarchar2list('eqv', 'lev', 'ncl', 'reserve', 'prov', 'roa', 'nim', 'eff', 'ltd',
                                        'brokered', 'log_assets', 'd_roa', 'd_ncl', 'growth'));
    COMMIT;
  END two_banks_and_a_model;

  PROCEDURE clean_up IS
  BEGIN
    DELETE FROM risk_score WHERE cert < 0;
    DELETE FROM financials WHERE cert < 0;
    DELETE FROM model_feature;
    DELETE FROM model_intercept;
    COMMIT;
  END clean_up;

  PROCEDURE clip_bounds IS
  BEGIN
    ut.expect(bank_risk.clip(30D, 0D, 20D)).to_equal(20D);
    ut.expect(bank_risk.clip(-5D, 0D, 20D)).to_equal(0D);
    ut.expect(bank_risk.clip(7.5D, 0D, 20D)).to_equal(7.5D);
  END clip_bounds;

  PROCEDURE logistic_values IS
  BEGIN
    ut.expect(bank_risk.logistic(0D)).to_equal(0.5D);
    ut.expect(bank_risk.logistic(-2D) + bank_risk.logistic(2D)).to_be_within(1e-15).of_(1D);
  END logistic_values;

  PROCEDURE scores_eligible_banks IS
    l_scored PLS_INTEGER;
    l_certs  SYS_REFCURSOR;
    l_expect SYS_REFCURSOR;
  BEGIN
    l_scored := bank_risk.score_quarter(c_q);
    ut.expect(l_scored).to_equal(2);
    OPEN l_certs FOR SELECT cert FROM risk_score WHERE repdte = c_q ORDER BY cert;
    OPEN l_expect FOR SELECT -2 AS cert FROM dual UNION ALL SELECT -1 FROM dual;
    ut.expect(l_certs).to_equal(l_expect);
  END scores_eligible_banks;

  PROCEDURE score_by_hand IS
    l_scored PLS_INTEGER;
    l_thick  BINARY_DOUBLE;
    l_thin   BINARY_DOUBLE;
  BEGIN
    l_scored := bank_risk.score_quarter(c_q);
    SELECT score INTO l_thick FROM risk_score WHERE cert = -1 AND repdte = c_q;
    SELECT score INTO l_thin FROM risk_score WHERE cert = -2 AND repdte = c_q;
    -- bank -1: z = -1 - 0.1 * 20 = -3; bank -2: z = -1 - 0.1 * 10 = -2
    ut.expect(l_thick).to_be_within(1e-15).of_(1 / (1 + EXP(3)));
    ut.expect(l_thin).to_be_within(1e-15).of_(1 / (1 + EXP(2)));
  END score_by_hand;

  PROCEDURE rescoring_replaces IS
    l_scored PLS_INTEGER;
    l_rows   PLS_INTEGER;
  BEGIN
    l_scored := bank_risk.score_quarter(c_q);
    UPDATE model_intercept SET intercept = 0D;
    COMMIT;
    l_scored := bank_risk.score_quarter(c_q);
    SELECT COUNT(*) INTO l_rows FROM risk_score WHERE repdte = c_q;
    ut.expect(l_rows).to_equal(2);
    SELECT COUNT(*) INTO l_rows FROM risk_score WHERE repdte = c_q AND cert = -2 AND ABS(score - 1 / (1 + EXP(1))) < 1e-15;
    ut.expect(l_rows).to_equal(1);
  END rescoring_replaces;

  PROCEDURE watch_list_order IS
    l_scored PLS_INTEGER;
    l_rows   SYS_REFCURSOR;
    l_cert   NUMBER;
    l_score  BINARY_DOUBLE;
    l_eqv    BINARY_DOUBLE;
    l_lev    BINARY_DOUBLE;
    l_ncl    BINARY_DOUBLE;
    l_roa    BINARY_DOUBLE;
    l_count  PLS_INTEGER := 0;
  BEGIN
    l_scored := bank_risk.score_quarter(c_q);
    l_rows := bank_risk.watch_list(c_q, 1);
    LOOP
      FETCH l_rows INTO l_cert, l_score, l_eqv, l_lev, l_ncl, l_roa;
      EXIT WHEN l_rows%NOTFOUND;
      l_count := l_count + 1;
      ut.expect(l_cert).to_equal(-2); -- thinner capital, higher score
    END LOOP;
    CLOSE l_rows;
    ut.expect(l_count).to_equal(1);
  END watch_list_order;
END test_bank_risk;
/
