#!/bin/bash
xvlog -sv -f filelist_core.f
xelab -relax -debug typical tb_core -s tb_core_sim
D=${1:?can thu muc hex}      # vi du isa_hex hoac mi_hex
while read name tohost; do
    xsim tb_core_sim -runall -testplusarg HEX=fw/$D/$name.hex -testplusarg TOHOST=$tohost > run_$name.log 2>&1
    grep -q "TEST PASSED" run_$name.log && echo "PASS $name" || echo "FAIL $name"
done < fw/$D/list.txt