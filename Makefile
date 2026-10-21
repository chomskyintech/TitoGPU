RTL = rtl/cgra_pe.v rtl/cgra_array.v rtl/cgra_top.v

.PHONY: sim synth clean

sim:
	iverilog -g2012 -Wall -o build_cgra $(RTL) tb/tb_cgra.v
	vvp build_cgra

synth:
	yosys -s synth/synth.ys

clean:
	rm -f build_cgra *.vcd
