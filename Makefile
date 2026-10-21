RTL = rtl/cgra_pe.v rtl/cgra_array.v rtl/cgra_top.v

.PHONY: sim synth clean

sim:
	iverilog -g2012 -Wall -o build_cgra_pe rtl/cgra_pe.v tb/tb_cgra_pe.v
	vvp build_cgra_pe
	iverilog -g2012 -Wall -o build_cgra $(RTL) tb/tb_cgra.v
	vvp build_cgra

synth:
	yosys -s synth/synth.ys

clean:
	rm -f build_cgra build_cgra_pe *.vcd
