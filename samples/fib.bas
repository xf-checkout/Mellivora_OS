10 REM Fibonacci sequence - Mellivora BASIC sample
20 PRINT "Fibonacci Sequence"
30 PRINT "------------------"
40 LET A = 0
50 LET B = 1
60 LET I = 1
70 WHILE I <= 20
80   PRINT A
90   LET C = A + B
100  LET A = B
110  LET B = C
120  LET I = I + 1
130 WEND
140 PRINT "Done."
150 END
