-- Recursive interpreter for artihmetic expressions,
-- walks an expression DAG over +/* operators and numeric literals
--
-- Note: Function eval() defines a standard top-down evaluation, but
--       the evaluation AFTER COMPILATION to WITH RECURSIVE will perform
--       *parallel* bottom-up evaluation:
--       *all* literal leaves will be evaluated in one iteration,
--       in the next iteration *all* operators referring to these leaves
--       will be evaluated, etc.

-- Recursive SQL UDF in functional style: expression interpreter
DROP FUNCTION IF EXISTS eval(expression);
CREATE FUNCTION eval(e expression) RETURNS numeric AS
$$
  SELECT CASE e.op
    WHEN 'ℓ' THEN e.lit
    WHEN '+' THEN eval((SELECT e1 FROM expression AS e1 WHERE e1.node = e.arg1))
                  +
                  eval((SELECT e2 FROM expression AS e2 WHERE e2.node = e.arg2))
    WHEN '*' THEN eval((SELECT e1 FROM expression AS e1 WHERE e1.node = e.arg1))
                  *
                  eval((SELECT e2 FROM expression AS e2 WHERE e2.node = e.arg2))
  END;
$$ LANGUAGE SQL;

-----------------------------------------------------------------------
-- Perform expression evaluation of root expression

SELECT setseed(0.42);

\timing on
SELECT e.node AS node, eval(e) AS result
FROM expression AS e
LIMIT :iterations;
\timing off