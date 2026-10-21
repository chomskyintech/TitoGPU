RTL = rtl/cgra_pe.v rtl/cgra_array.v rtl/cgra_top.v

.PHONY: sim synth synth-mac clean

sim:
	iverilog -g2012 -Wall -o build_cgra_pe rtl/cgra_pe.v tb/tb_cgra_pe.v
	vvp build_cgra_pe
	iverilog -g2012 -Wall -o build_cgra_controller $(RTL) tb/tb_cgra_controller.v
	vvp build_cgra_controller
	iverilog -g2012 -Wall -o build_cgra $(RTL) tb/tb_cgra.v
	vvp build_cgra
	iverilog -g2012 -Wall -o build_tito_mac rtl/tito_systolic_mac.v tb/tb_tito_systolic_mac.v
	vvp build_tito_mac
	iverilog -g2012 -Wall -o build_tito_mac_n4 rtl/tito_systolic_mac.v tb/tb_tito_systolic_mac_n4.v
	vvp build_tito_mac_n4

synth: synth-mac
	yosys -s synth/synth.ys

synth-mac:
	yosys -p 'read_verilog rtl/tito_systolic_mac.v; hierarchy -top tito_systolic_mac; synth -top tito_systolic_mac; stat'

clean:
	rm -f build_cgra build_cgra_pe build_cgra_controller build_tito_mac build_tito_mac_n4 *.vcd
