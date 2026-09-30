vlib work
vlog -sv -f filelist.f +cover=bcesf
vsim -c -coverage work.wb_ascon_tb -do "run -all; coverage save out.ucdb; quit" 
# vcover report -details out.ucdb