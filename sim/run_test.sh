xvlog -sv -f filelist.f
xelab -relax -debug typical wb_ascon_tb -s tb_sim
xsim tb_sim -runall -testplusarg KAT=kat128.txt