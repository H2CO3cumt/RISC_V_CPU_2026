from coremark_serial import parse_coremark

SAMPLE = """2K performance run parameters for coremark.
Total ticks      : 1923077000
Iterations       : 1000
[0]crclist       : 0xe714
[0]crcmatrix     : 0x1fd7
[0]crcstate      : 0x8e3a
Correct operation validated.
CoreMark score x1000 : 26000
CoreMark/MHz x1000  : 520
PERF cycle=728b6580 instret=2eaf8370 stall=05000000 load=00100000 branch=10000000 taken=08000000 flush=0c000000
COREMARK_DONE
"""

result = parse_coremark(SAMPLE)
assert result["ticks"] == 1_923_077_000
assert result["iterations"] == 1000
assert result["score_x1000"] == 26000
assert result["coremark_per_mhz_x1000"] == 520
assert result["seconds_at_50mhz_x1000"] == 38_461
assert result["cycles"] == 0x728B6580
try:
    parse_coremark(SAMPLE.replace("0xe714", "0x0000"))
except ValueError as exc:
    assert "crclist" in str(exc)
else:
    raise AssertionError("bad CRC was accepted")
print("ALL COREMARK SERIAL PARSER TEST PASS")
