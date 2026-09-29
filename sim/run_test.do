vlib work
vlog -sv -f filelist.f +cover=bcesf
# vsim -c -coverage -do "run -all; coverage save out.ucdb; quit" tb_top
# vcover report -details out.ucdb