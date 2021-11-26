-- Virtual machine (VM) featuring three-address opcodes

-----------------------------------------------------------------------
-- Tail-recursive SQL UDF into functional style that implements
-- the VM instructions.  The second parameter represents the
-- machine's register file (each register hold one integer).
--
DROP FUNCTION IF EXISTS run(instruction, int[]);
CREATE FUNCTION run(ins instruction, regs int[]) RETURNS int AS
$$
  SELECT CASE ins.opc
    WHEN 'lod' THEN run((SELECT p FROM program AS p WHERE p.loc = ins.loc+1),
                        regs[:ins.reg1-1] || ins.reg2 || regs[ins.reg1+1:])

    WHEN 'mov' THEN run((SELECT p FROM program AS p WHERE p.loc = ins.loc+1),
                        regs[:ins.reg1-1] || regs[ins.reg2] || regs[ins.reg1+1:])

    WHEN 'jeq' THEN run((SELECT p FROM program AS p WHERE p.loc = CASE WHEN regs[ins.reg1] = regs[ins.reg2]
                                                                       THEN ins.reg3
                                                                       ELSE ins.loc + 1
                                                                  END),
                        regs)

    WHEN 'jmp' THEN run((SELECT p FROM program AS p WHERE p.loc = ins.reg1),
                        regs)

    WHEN 'add' THEN run((SELECT p FROM program AS p WHERE p.loc = ins.loc+1),
                        regs[:ins.reg1-1] || regs[ins.reg2] + regs[ins.reg3] || regs[ins.reg1+1:])

    WHEN 'mul' THEN run((SELECT p FROM program AS p WHERE p.loc = ins.loc+1),
                        regs[:ins.reg1-1] || regs[ins.reg2] * regs[ins.reg3] || regs[ins.reg1+1:])

    WHEN 'div' THEN run((SELECT p FROM program AS p WHERE p.loc = ins.loc+1),
                        regs[:ins.reg1-1] || regs[ins.reg2] / regs[ins.reg3] || regs[ins.reg1+1:])

    WHEN 'mod' THEN run((SELECT p FROM program AS p WHERE p.loc = ins.loc+1),
                        regs[:ins.reg1-1] || regs[ins.reg2] % regs[ins.reg3] || regs[ins.reg1+1:])

    WHEN 'hlt' THEN regs[ins.reg1]
  END
$$
LANGUAGE SQL STABLE STRICT;

-----------------------------------------------------------------------
-- Compute the length of the Collatz sequence (also known as
-- the "3N + 1 problem") for the value N held in register R1.

\timing on
SELECT num,
       run((SELECT p FROM program AS p WHERE p.loc = 0), -- program entry instruction
            ARRAY[num,0,0,0,0,0,0]) AS collatz        -- initial register file
FROM generate_series(1, :N) AS _(num);
\timing off