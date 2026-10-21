RTL = rtl/cgra_pe.v rtl/cgra_array.v rtl/cgra_top.v

.PHONY: sim synth synth-writeback synth-mac synth-scheduler synth-accelerator synth-stream synth-command synth-burst synth-tiled synth-dma synth-double-buffered synth-axi clean

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
	iverilog -g2012 -Wall -o build_tito_matmul rtl/tito_systolic_mac.v rtl/tito_systolic_matmul.v tb/tb_tito_systolic_matmul.v
	vvp build_tito_matmul
	iverilog -g2012 -Wall -o build_tito_accel rtl/tito_systolic_mac.v rtl/tito_systolic_matmul.v rtl/tito_systolic_scratchpad.v rtl/tito_systolic_accelerator.v tb/tb_tito_systolic_accelerator.v
	vvp build_tito_accel
	iverilog -g2012 -Wall -o build_tito_stream rtl/tito_systolic_mac.v rtl/tito_systolic_banked_scratchpad.v rtl/tito_systolic_stream_accelerator.v tb/tb_tito_systolic_stream_accelerator.v
	vvp build_tito_stream
	iverilog -g2012 -Wall -o build_tito_command rtl/tito_systolic_mac.v rtl/tito_systolic_banked_scratchpad.v rtl/tito_systolic_stream_accelerator.v rtl/tito_systolic_command_accelerator.v tb/tb_tito_systolic_command_accelerator.v
	vvp build_tito_command
	iverilog -g2012 -Wall -o build_tito_k_tiling rtl/tito_systolic_mac.v rtl/tito_systolic_banked_scratchpad.v rtl/tito_systolic_stream_accelerator.v rtl/tito_systolic_command_accelerator.v tb/tb_tito_systolic_k_tiling.v
	vvp build_tito_k_tiling
	iverilog -g2012 -Wall -o build_tito_burst rtl/tito_systolic_mac.v rtl/tito_systolic_banked_scratchpad.v rtl/tito_systolic_stream_accelerator.v rtl/tito_systolic_command_accelerator.v rtl/tito_systolic_burst_command_accelerator.v tb/tb_tito_systolic_burst_command_accelerator.v
	vvp build_tito_burst
	iverilog -g2012 -Wall -o build_tito_tiled rtl/tito_systolic_mac.v rtl/tito_systolic_banked_scratchpad.v rtl/tito_systolic_stream_accelerator.v rtl/tito_systolic_command_accelerator.v rtl/tito_systolic_burst_command_accelerator.v rtl/tito_systolic_tiled_burst_accelerator.v tb/tb_tito_systolic_tiled_burst_accelerator.v
	vvp build_tito_tiled
	iverilog -g2012 -Wall -o build_tito_dma rtl/tito_systolic_mac.v rtl/tito_systolic_banked_scratchpad.v rtl/tito_systolic_stream_accelerator.v rtl/tito_systolic_command_accelerator.v rtl/tito_systolic_burst_command_accelerator.v rtl/tito_systolic_tiled_burst_accelerator.v rtl/tito_systolic_dma_reader.v tb/tb_tito_systolic_dma_reader.v
	vvp build_tito_dma +MEM_GAP=0
	vvp build_tito_dma +MEM_GAP=2
	vvp build_tito_dma +MEM_GAP=5
	iverilog -g2012 -Wall -o build_tito_dbuf rtl/tito_systolic_mac.v rtl/tito_systolic_double_buffered_banked_scratchpad.v rtl/tito_systolic_double_buffered_stream_accelerator.v rtl/tito_systolic_double_buffered_command_accelerator.v rtl/tito_systolic_double_buffered_burst_command_accelerator.v rtl/tito_systolic_double_buffered_tiled_burst_accelerator.v rtl/tito_systolic_double_buffered_dma_reader.v tb/tb_tito_systolic_double_buffered_dma_reader.v
	vvp build_tito_dbuf +MEM_GAP=0
	vvp build_tito_dbuf +MEM_GAP=2
	vvp build_tito_dbuf +MEM_GAP=5
	iverilog -g2012 -Wall -o build_tito_axi_read rtl/tito_systolic_axi4_read_adapter.v tb/tb_tito_systolic_axi4_read_adapter.v
	vvp build_tito_axi_read
	iverilog -g2012 -Wall -o build_tito_axi_width rtl/tito_systolic_axi4_read_adapter.v tb/tb_tito_systolic_axi4_width_converter.v
	vvp build_tito_axi_width
	iverilog -g2012 -Wall -o build_tito_axi_write rtl/tito_systolic_axi4_write_adapter.v tb/tb_tito_systolic_axi4_write_adapter.v
	vvp build_tito_axi_write
	iverilog -g2012 -Wall -o build_tito_axi_result_writeback rtl/tito_systolic_axi4_write_adapter.v rtl/tito_systolic_axi4_result_writeback.v tb/tb_tito_systolic_axi4_result_writeback.v
	vvp build_tito_axi_result_writeback
	iverilog -g2012 -Wall -o build_tito_axi_dbuf rtl/tito_systolic_mac.v rtl/tito_systolic_double_buffered_banked_scratchpad.v rtl/tito_systolic_double_buffered_stream_accelerator.v rtl/tito_systolic_double_buffered_command_accelerator.v rtl/tito_systolic_double_buffered_burst_command_accelerator.v rtl/tito_systolic_double_buffered_tiled_burst_accelerator.v rtl/tito_systolic_double_buffered_dma_reader.v rtl/tito_systolic_axi4_read_adapter.v rtl/tito_systolic_axi4_double_buffered_accelerator.v tb/tb_tito_systolic_axi4_double_buffered_accelerator.v
	vvp build_tito_axi_dbuf +MEM_GAP=0
	vvp build_tito_axi_dbuf +MEM_GAP=2
	vvp build_tito_axi_dbuf +MEM_GAP=5

synth: synth-mac synth-scheduler synth-accelerator synth-stream synth-command synth-burst synth-tiled synth-dma synth-double-buffered synth-axi
	yosys -s synth/synth.ys

synth-mac:
	yosys -p 'read_verilog rtl/tito_systolic_mac.v; hierarchy -top tito_systolic_mac; synth -top tito_systolic_mac; stat'

synth-scheduler:
	yosys -p 'read_verilog rtl/tito_systolic_mac.v rtl/tito_systolic_matmul.v; hierarchy -top tito_systolic_matmul; synth -top tito_systolic_matmul; stat'

synth-accelerator:
	yosys -p 'read_verilog rtl/tito_systolic_mac.v rtl/tito_systolic_matmul.v rtl/tito_systolic_scratchpad.v rtl/tito_systolic_accelerator.v; hierarchy -top tito_systolic_accelerator; synth -top tito_systolic_accelerator; stat'

synth-stream:
	yosys -p 'read_verilog rtl/tito_systolic_mac.v rtl/tito_systolic_banked_scratchpad.v rtl/tito_systolic_stream_accelerator.v; hierarchy -top tito_systolic_stream_accelerator; synth -top tito_systolic_stream_accelerator; stat'

synth-command:
	yosys -p 'read_verilog rtl/tito_systolic_mac.v rtl/tito_systolic_banked_scratchpad.v rtl/tito_systolic_stream_accelerator.v rtl/tito_systolic_command_accelerator.v; hierarchy -top tito_systolic_command_accelerator; synth -top tito_systolic_command_accelerator; stat'

synth-burst:
	yosys -p 'read_verilog rtl/tito_systolic_mac.v rtl/tito_systolic_banked_scratchpad.v rtl/tito_systolic_stream_accelerator.v rtl/tito_systolic_command_accelerator.v rtl/tito_systolic_burst_command_accelerator.v; hierarchy -top tito_systolic_burst_command_accelerator; synth -top tito_systolic_burst_command_accelerator; stat'

synth-tiled:
	yosys -p 'read_verilog rtl/tito_systolic_mac.v rtl/tito_systolic_banked_scratchpad.v rtl/tito_systolic_stream_accelerator.v rtl/tito_systolic_command_accelerator.v rtl/tito_systolic_burst_command_accelerator.v rtl/tito_systolic_tiled_burst_accelerator.v; hierarchy -top tito_systolic_tiled_burst_accelerator; synth -top tito_systolic_tiled_burst_accelerator; stat'

synth-dma:
	yosys -p 'read_verilog rtl/tito_systolic_mac.v rtl/tito_systolic_banked_scratchpad.v rtl/tito_systolic_stream_accelerator.v rtl/tito_systolic_command_accelerator.v rtl/tito_systolic_burst_command_accelerator.v rtl/tito_systolic_tiled_burst_accelerator.v rtl/tito_systolic_dma_reader.v; hierarchy -top tito_systolic_dma_reader; synth -top tito_systolic_dma_reader; stat'

synth-double-buffered:
	yosys -p 'read_verilog rtl/tito_systolic_mac.v rtl/tito_systolic_double_buffered_banked_scratchpad.v rtl/tito_systolic_double_buffered_stream_accelerator.v rtl/tito_systolic_double_buffered_command_accelerator.v rtl/tito_systolic_double_buffered_burst_command_accelerator.v rtl/tito_systolic_double_buffered_tiled_burst_accelerator.v rtl/tito_systolic_double_buffered_dma_reader.v; hierarchy -top tito_systolic_double_buffered_dma_reader; synth -top tito_systolic_double_buffered_dma_reader; stat'

synth-writeback:
	yosys -p 'read_verilog rtl/tito_systolic_axi4_write_adapter.v rtl/tito_systolic_axi4_result_writeback.v; hierarchy -top tito_systolic_axi4_result_writeback; synth -top tito_systolic_axi4_result_writeback; stat'

synth-axi:
	yosys -p 'read_verilog rtl/tito_systolic_mac.v rtl/tito_systolic_double_buffered_banked_scratchpad.v rtl/tito_systolic_double_buffered_stream_accelerator.v rtl/tito_systolic_double_buffered_command_accelerator.v rtl/tito_systolic_double_buffered_burst_command_accelerator.v rtl/tito_systolic_double_buffered_tiled_burst_accelerator.v rtl/tito_systolic_double_buffered_dma_reader.v rtl/tito_systolic_axi4_read_adapter.v rtl/tito_systolic_axi4_double_buffered_accelerator.v; hierarchy -top tito_systolic_axi4_double_buffered_accelerator; synth -top tito_systolic_axi4_double_buffered_accelerator; stat'

clean:
	rm -f build_cgra build_cgra_pe build_cgra_controller build_tito_mac build_tito_mac_n4 build_tito_matmul build_tito_accel build_tito_stream build_tito_command build_tito_k_tiling build_tito_burst build_tito_tiled build_tito_dma build_tito_dbuf build_tito_axi_read build_tito_axi_width build_tito_axi_write build_tito_axi_result_writeback build_tito_axi_dbuf *.vcd
