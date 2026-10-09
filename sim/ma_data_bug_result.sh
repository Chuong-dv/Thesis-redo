xvlog -sv -f filelist_core.f
xelab -relax -debug typical tb_core -s tb_core_sim
xsim tb_core_sim -runall -testplusarg HEX=fw/isa_hex/rv32ui-p-ma_data.hex -testplusarg TOHOST=80001000
