"""

Copyright (c) 2020 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

"""
"""
NOTE : 
This code is taken with modifications, from Alex Forencich's Verilog AXI components axi_ram testbench 
https://github.com/alexforencich/verilog-axi/blob/master/tb/axi_ram/test_axi_ram.py
                     
Modifications have been made by Manjunath - manjunath.kalmath@bsc.es in 2024
"""

import itertools
import logging
import os
import random

import cocotb_test.simulator
import pytest

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer
from cocotb.regression import TestFactory

from cocotbext.axi import AxiBus, AxiMaster

class TB(object):
    def __init__(self, dut, num_bytes, num_transactions):
        self.dut = dut
        self.num_bytes = num_bytes
        self.num_transactions = num_transactions
        self.log = logging.getLogger("cocotb.tb")
        self.log.setLevel(logging.DEBUG)

        cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())

        self.axi_master = AxiMaster(AxiBus.from_prefix(dut, "s0_axi"), dut.clk, dut.rstn, reset_active_level=False)

    def get_num_bytes(self):
        return self.num_bytes
    
    def get_num_transactions(self):
        return self.num_transactions

    def generate_hex(self):
        return hex(random.getrandbits(self.num_bytes * 8))

    async def cycle_reset(self):
        self.dut.rstn.value = 1
        await Timer(205, units="ns")
        self.dut.rstn.value = 0
        await Timer(100, units="ns")
        self.dut.rstn.value = 1

# AXI single transaction test : placeholder
async def run_test_single(dut, data_in=None, idle_inserter=None, backpressure_inserter=None, size=None):

    NUM_BYTES        = 128
    NUM_TRANSACTIONS = 4

    ADDR_CACHE     = 0x8000000000
    ADDR_NON_CACHE = 0x1000000000

    AXI_CACHE      = 0b1111    # write-back read and write-allocate
    AXI_NON_CACHE  = 0b0011    # normal non-cacheable bufferable

    tb = TB(dut, num_bytes = NUM_BYTES, num_transactions = NUM_TRANSACTIONS)

    if size is None:
        size = tb.axi_master.write_if.max_burst_size

    await tb.cycle_reset()

    test_data = int(tb.generate_hex(), 16)
    await tb.axi_master.write_word(ADDR_NON_CACHE, test_data, size=size, ws=tb.get_num_bytes(), cache=AXI_CACHE)
    await Timer(10, units="ns")
    assert await tb.axi_master.read_word(ADDR_NON_CACHE, ws=tb.get_num_bytes(), cache=AXI_CACHE) == test_data
    await Timer(10, units="ns")

if cocotb.SIM_NAME:
    data_width = len(cocotb.top.s0_axi_wdata)

    for test in [run_test_single]:
        factory = TestFactory(test)
        factory.generate_tests()
