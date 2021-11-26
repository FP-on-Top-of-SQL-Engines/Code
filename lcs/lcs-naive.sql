-- Find the length of the longest common subsequence.
--
-- For example, consider the sequences (ABCD) and (ACBAD).
-- They have 5 length-2 common subsequences: (AB), (AC), (AD), (BD), and (CD);
-- 2 length-3 common subsequences: (ABD) and (ACD); and no longer common subsequences.
-- So (ABD) and (ACD) are their longest common subsequences.
--
-- Example source: https://en.wikipedia.org/wiki/Longest_common_subsequence_problem

DROP FUNCTION IF EXISTS lcs(text, text);
CREATE FUNCTION lcs(l text, r text) RETURNS int AS
$$
  SELECT CASE
    WHEN l = '' OR r = '' THEN 0
    WHEN left(l,1) = left(r,1) THEN 1 + lcs(right(l,-1), right(r,-1))
    ELSE GREATEST(lcs(right(l,-1), r), lcs(l, right(r,-1)))
  END;
$$ LANGUAGE SQL STABLE STRICT;

-----------------------------------------------------------------------
-- Determine the length of the longest common subsequence of seq1 and seq2

\timing on
SELECT s1.seq, s2.seq, lcs(s1.seq,s2.seq)
FROM sequences AS s1, sequences AS s2
LIMIT :iterations;
\timing off