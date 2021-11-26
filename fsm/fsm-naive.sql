-- Demonstrate the use of a recursive SQL UDF to drive a finite state
-- machine (derived from a regular expression) to parse chemical compound
-- formulae.
--
-- Recursive SQL UDF to parse string 'input'.  Finite state machine
-- currently is in state 'state'.
--
DROP FUNCTION IF EXISTS parse(int, text);
CREATE FUNCTION parse(state int, input text) RETURNS boolean AS
$$
  SELECT CASE WHEN length(input) = 0
              THEN (SELECT DISTINCT edge.final
                    FROM   fsm AS edge
                    WHERE  state = edge.source)
              ELSE COALESCE(parse((
                SELECT edge.target
                FROM fsm AS edge
                WHERE state = edge.source
                AND   strpos(edge.labels, left(input, 1)) > 0
              ), right(input, -1)), false)
         END;
$$ LANGUAGE SQL;

-----------------------------------------------------------------------
-- Parse 1000 chemical compounds and validate their formulae

\timing on
SELECT c.*, parse(0, c.formula)
FROM compounds AS c
LIMIT :iterations;
\timing off