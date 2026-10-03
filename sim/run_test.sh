#!/bin/bash
# Cach dung: ./run_test.sh [ten_test] [file_kat]
TEST=${1:-kat}                              # mac dinh la kat
KAT=${2:-kat128.txt}        # mac dinh dung file vector da sinh

xvlog -sv -f filelist.f                        || exit 1
xelab -relax -debug typical wb_ascon_tb -s tb_sim || exit 1
xsim tb_sim -runall -testplusarg TEST=$TEST -testplusarg KAT=$KAT | tee run_$TEST.log

grep -q "TEST PASSED" run_$TEST.log             # exit code: 0 neu pass, 1 neu fail