#!/bin/bash
# Cach dung: [TOP=ten_module_tb] ./run_test.sh [ten_test] [file_kat]
TEST=${1:-kat}                  # mac dinh la kat
KAT=${2:-kat128.txt}            # mac dinh dung file vector da sinh
TOP=${TOP:-wb_ascon_tb}         # mac dinh la testbench goc cua wrapper
LOG=run_${TOP}_${TEST}.log

xvlog -sv -f filelist.f                            || exit 1
xelab -relax -debug typical $TOP -s tb_sim         || exit 1
xsim tb_sim -runall -testplusarg TEST=$TEST -testplusarg KAT=$KAT | tee $LOG

grep -q "TEST PASSED" $LOG      # exit code: 0 neu pass, 1 neu fail