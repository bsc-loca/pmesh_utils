# Copyright (c) 2020 Alex Forencich
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.
#
# NOTE : 
# This code is taken with modifications, from Alex Forencich's Verilog AXI components axi_ram testbench
# https://github.com/alexforencich/verilog-axi/blob/master/tb/axi_ram/Makefile
#                     
# Modifications have been made by Manjunath - manjunath.kalmath@bsc.es in 2024
#

TOPLEVEL_LANG = verilog

SIM ?= verilator
WAVES ?= 0

COCOTB_HDL_TIMEUNIT = 1ns
COCOTB_HDL_TIMEPRECISION = 1ps

#DUT
#package
VERILOG_SOURCES +=$(shell pwd)/../../../include/axi_to_pmesh_bridge_pkg.sv
#openpiton 
VERILOG_SOURCES +=$(shell pwd)/../src/flat_id_to_xy.tmp.v 
VERILOG_SOURCES +=$(shell pwd)/../src/l15_home_encoder.tmp.v
#Additional files to verify design
VERILOG_SOURCES +=$(shell pwd)/top_axi_module.sv
VERILOG_SOURCES +=$(shell pwd)/axi_ram.v
VERILOG_SOURCES +=$(shell pwd)/../../../../pmesh_width_adapter/src/pmesh_width_adapter.sv
VERILOG_SOURCES +=$(shell pwd)/noc_axi4_bridge/axi4_zeroer.v
VERILOG_SOURCES +=$(shell pwd)/noc_axi4_bridge/bram_sdp_1ck.v
VERILOG_SOURCES +=$(shell pwd)/noc_axi4_bridge/bram_tdp_1ck_wrfirst.v
VERILOG_SOURCES +=$(shell pwd)/noc_axi4_bridge/noc_axi4_bridge_buffer.sv
VERILOG_SOURCES +=$(shell pwd)/noc_axi4_bridge/noc_axi4_bridge_deser.sv 
VERILOG_SOURCES +=$(shell pwd)/noc_axi4_bridge/noc_axi4_bridge_ser.sv 
VERILOG_SOURCES +=$(shell pwd)/noc_axi4_bridge/noc_axi4_bridge_write.sv 
VERILOG_SOURCES +=$(shell pwd)/noc_axi4_bridge/noc_axi4_bridge_read.sv
VERILOG_SOURCES +=$(shell pwd)/noc_axi4_bridge/noc_axi4_bridge.v
VERILOG_SOURCES +=$(shell pwd)/noc_axi4_bridge/noc_extractSize.v
VERILOG_SOURCES +=$(shell pwd)/noc_axi4_bridge/storage_addr_trans.tmp.v
#bsc
VERILOG_SOURCES +=$(shell pwd)/../../../src/addr_to_x_y.sv
VERILOG_SOURCES +=$(shell pwd)/../../../src/axi_slave_rd_pipeline.sv
VERILOG_SOURCES +=$(shell pwd)/../../../src/axi_slave_wrapper_pipeline.sv 
VERILOG_SOURCES +=$(shell pwd)/../../../src/axi_slave_wr_pipeline.sv
VERILOG_SOURCES +=$(shell pwd)/../../../src/axi_to_pmesh_bridge.sv
VERILOG_SOURCES +=$(shell pwd)/../../../src/fifo_v3.sv
VERILOG_SOURCES +=$(shell pwd)/../../../src/noc_driver.sv
VERILOG_SOURCES +=$(shell pwd)/../../../src/noc_requests.sv
VERILOG_SOURCES +=$(shell pwd)/../../../src/noc_responses.sv
VERILOG_SOURCES +=$(shell pwd)/../../../src/alexforencich_priority_encoder.v
VERILOG_SOURCES +=$(shell pwd)/../../../src/transfer_unroller.sv
VERILOG_SOURCES +=$(shell pwd)/../../../src/write_unroller.sv

TOPLEVEL = top_axi_module
MODULE  ?= test_axi_to_pmesh_bridge


ifeq ($(SIM), vcs)
	COMPILE_ARGS += +incdir+$(shell pwd)/../include -full64 -debug_all -debug_access+r -kdb

	COMPILE_ARGS += $(foreach v,$(filter PARAM_%,$(.VARIABLES)),-P $(TOPLEVEL).$(subst PARAM_,,$(v))=$($(v)))

	COMPILE_ARGS += +vcs+lic+wait

	ifeq ($(WAVES), 1)
		COMPILE_ARGS += -gui
	endif
else ifeq ($(SIM), questa)
	COMPILE_ARGS += +incdir+$(shell pwd)/../include 

	COMPILE_ARGS += $(foreach v,$(filter PARAM_%,$(.VARIABLES)),-P $(TOPLEVEL).$(subst PARAM_,,$(v))=$($(v)))

	ifeq ($(WAVES), 1)
		GUI=1
	endif
else ifeq ($(SIM), verilator)
	COMPILE_ARGS += +incdir+$(shell pwd)/../include +incdir+$(shell pwd)/../../../include -Wno-SELRANGE -Wno-WIDTH -Wno-CASEINCOMPLETE -Wno-misindent -Wno-UNOPTFLAT

	COMPILE_ARGS += $(foreach v,$(filter PARAM_%,$(.VARIABLES)),-G$(subst PARAM_,,$(v))=$($(v)))

	ifeq ($(WAVES), 1)
		EXTRA_ARGS += --trace --trace-structs
	endif

endif

include $(shell cocotb-config --makefiles)/Makefile.sim

clean::
	rm -f inter.fsdb novas.conf novas_dump.log novas.rc ucli.key
	rm -rf verdiLog
	rm -f modelsim.ini transcript vsim.wlf
