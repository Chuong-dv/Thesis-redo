xvlog -f filelist.f
xelab -relax -debug typical tb/tb_ascon_wb tb/tb_sim
xsim tb_sim -R -runall