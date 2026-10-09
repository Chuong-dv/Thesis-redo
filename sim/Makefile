D ?= isa_hex      # dùng: make run D=mi_hex

.PHONY: run merge clean

run:
	xvlog -sv -f filelist_core.f
	@while read name tohost; do \
		xelab -relax -debug typical -cc_type sbtc -cc_dir cov -cc_db cov_$(D)_$$name \
			tb_core -s sim_$$name > elab_$$name.log 2>&1; \
		xsim sim_$$name -runall -testplusarg HEX=fw/$(D)/$$name.hex -testplusarg TOHOST=$$tohost \
			< /dev/null > run_$$name.log 2>&1; \
		grep -q "TEST PASSED" run_$$name.log && echo "PASS $$name" || echo "FAIL $$name"; \
	done < fw/$(D)/list.txt

merge:
	xcrg -merge_cc -cc_dir cov \
		$$(ls cov/xsim.codeCov | grep '^cov_' | sed 's/^/-cc_db /') \
		-cc_merge_dir ./merge_covdb -cc_merge_db merged \
		-cc_report ./cov_report_code -report_format html
	@echo "Coverage report: ./cov_report_code/"

clean:
	rm -rf xsim.dir cov merge_covdb cov_report_code run_*.log elab_*.log *.jou *.pb *.wdb webtalk*