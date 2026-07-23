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

# AXI byte strobes test :
# check cacheable/non-cacheable stores with byte strobe combinations
async def run_test_byte_strobes(dut, data_in=None, idle_inserter=None, backpressure_inserter=None, size=None):

    NUM_BYTES        = 128
    NUM_TRANSACTIONS = 1

    TRAN_SIZE = 0

    ADDR_CACHE     = 0x8000000000
    ADDR_NON_CACHE = 0x1000000000

    AXI_CACHE      = 0b1111    # write-back read and write-allocate
    AXI_NON_CACHE  = 0b0011    # normal non-cacheable bufferable

    tb = TB(dut, num_bytes = NUM_BYTES, num_transactions = NUM_TRANSACTIONS)

    strb_mask_size = tb.axi_master.write_if.byte_lanes  # number of bits in the mask

    size = tb.axi_master.write_if.max_burst_size

    # cannot test all strobe combinations exhaustively for wide data
    # create groups of byte strobes <= 4 and replicate
    strb_size = min(4, size)
    strb_range = 1 << strb_size

    #NOTE: size can be 0 - indicating a single byte
    if (strb_size > 0):
        strb_range_num = strb_mask_size // strb_size
    else:
        strb_range_num = 1

    # test strobes for all cacheability values
    test_addr   = [ADDR_CACHE, ADDR_NON_CACHE]

    # remember initial byte strobes
    init_bs = tb.axi_master.write_if.strb_mask

    await tb.cycle_reset()

    # test partial writes using byte strobes
    for a in test_addr:
        for n in range(strb_range_num):
            for s in range(strb_range):

                # initialise memory
                tb.axi_master.write_if.strb_mask = init_bs
                init_data = int(tb.generate_hex(), 16)
                await tb.axi_master.write_word(a, init_data, size=size, ws=tb.get_num_bytes(), cache=AXI_CACHE)

                # write partial test data
                tb.axi_master.write_if.strb_mask = s
                test_data = int(tb.generate_hex(), 16)

                await tb.axi_master.write_word(a, test_data, size=size, ws=tb.get_num_bytes(), cache=AXI_CACHE)
                await Timer(10, units="ns")
                read_data = await tb.axi_master.read_word(a, size=size, ws=tb.get_num_bytes(), cache=AXI_CACHE)

                # generate a data bit mask, from the byte strobes, to check read data correctly
                iter_strb_mask = 1
                bit_mask = 0
                for i in range(0, tb.get_num_bytes()):
                    if (s & iter_strb_mask):
                        bit_mask = bit_mask | (0xff << (i * 8))
                    iter_strb_mask = iter_strb_mask << 1
                    if (iter_strb_mask == (1 << strb_mask_size)):
                        iter_strb_mask = 1

                # check that written data is read correclty and also that data not written is old
                assert (read_data &  bit_mask) == (test_data &  bit_mask)  # check that correct data was written
                assert (read_data & ~bit_mask) == (init_data & ~bit_mask)  # check that other data was not affected

# AXI sweep test :
# check cacheable/non-cacheable addresses
# check cacheable/non-cacheable AXI requests
# check AXI data sizes
async def run_test_sweep(dut, data_in=None, idle_inserter=None, backpressure_inserter=None, size=None):

    NUM_BYTES        = 128
    NUM_TRANSACTIONS = 4

    ADDR_CACHE     = 0x8000000000
    ADDR_NON_CACHE = 0x1000000000

    AXI_CACHE      = 0b1111    # write-back read and write-allocate
    AXI_NON_CACHE  = 0b0011    # normal non-cacheable bufferable

    tb = TB(dut, num_bytes = NUM_BYTES, num_transactions = NUM_TRANSACTIONS)

    max_burst_size = tb.axi_master.write_if.max_burst_size

    # test cacheability combinations based on address and AXI signals
    # tests should result in cacheable, non-cacheable, non-cacheable and non-cacheable
    test_addr   = [ADDR_CACHE, ADDR_NON_CACHE]
    test_xcache = [AXI_CACHE,  AXI_NON_CACHE]
 
    await tb.cycle_reset()

    for a in test_addr:
        for x in test_xcache:
            for s in range(max_burst_size + 1):
                test_data = int(tb.generate_hex(), 16)
                await tb.axi_master.write_word(a, test_data, size=s, ws=tb.get_num_bytes(), cache=x)
                await Timer(10, units="ns")
                assert await tb.axi_master.read_word(a, size=s, ws=tb.get_num_bytes(), cache=x) == test_data
                await Timer(10, units="ns")

# AXI Read and Write Test : first write then read
async def run_test_write_read(dut, data_in=None, idle_inserter=None, backpressure_inserter=None, size=None):

    NUM_BYTES        = 128
    NUM_TRANSACTIONS = 4

    ADDR_CACHE     = 0x8000000000
    ADDR_NON_CACHE = 0x1000000000

    AXI_CACHE      = 0b1111    # write-back read and write-allocate
    AXI_NON_CACHE  = 0b0011    # normal non-cacheable bufferable

    tb = TB(dut, num_bytes = NUM_BYTES, num_transactions = NUM_TRANSACTIONS)

    if size is None:
        size = tb.axi_master.write_if.max_burst_size

    # test cacheability combinations based on address and AXI signals
    # tests should result in cacheable, non-cacheable, non-cacheable and non-cacheable
    test_addr   = [ADDR_CACHE, ADDR_NON_CACHE, ADDR_CACHE,    ADDR_NON_CACHE]
    test_xcache = [AXI_CACHE,  AXI_CACHE,      AXI_NON_CACHE, AXI_NON_CACHE]

    await tb.cycle_reset()

    for i in range(0, tb.get_num_transactions()):
        test_data = int(tb.generate_hex(), 16)
        await tb.axi_master.write_word(test_addr[i], test_data, size=size, ws=tb.get_num_bytes(), cache=test_xcache[i])
        await Timer(10, units="ns")
        assert await tb.axi_master.read_word(test_addr[i], ws=tb.get_num_bytes(), cache=test_xcache[i]) == test_data
        await Timer(10, units="ns")

# AXI Read and Write Test : write and read test runs in parallel
async def run_test_write_read_in_parallel(dut, data_in=None, idle_inserter=None, backpressure_inserter=None, size=None):

    NUM_BYTES        = 128
    NUM_TRANSACTIONS = 4

    ADDR_CACHE     = 0x8000000000
    ADDR_NON_CACHE = 0x1000000000

    AXI_CACHE      = 0b1111    # write-back read and write-allocate
    AXI_NON_CACHE  = 0b0011    # normal non-cacheable bufferable

    tb = TB(dut, num_bytes = NUM_BYTES, num_transactions = NUM_TRANSACTIONS)

    max_burst_size = tb.axi_master.write_if.max_burst_size

    if size is None:
        size = max_burst_size

    # test cacheability combinations based on address and AXI signals
    # tests should result in cacheable, non-cacheable, non-cacheable and non-cacheable
    test_addr   = [ADDR_CACHE, ADDR_NON_CACHE, ADDR_CACHE,    ADDR_NON_CACHE]
    test_xcache = [AXI_CACHE,  AXI_CACHE,      AXI_NON_CACHE, AXI_NON_CACHE]

    await tb.cycle_reset()

    for i in range(0, tb.get_num_transactions()):
        test_data = int(tb.generate_hex(), 16)
        axi_write = cocotb.start_soon(tb.axi_master.write_word(test_addr[i], test_data, size=size, ws=tb.get_num_bytes(), cache=test_xcache[i]))
        axi_read  = cocotb.start_soon(tb.axi_master.read_word(test_addr[i], ws=tb.get_num_bytes(), cache=test_xcache[i]))
        await axi_write
        assert await axi_read == test_data
        await Timer(10, units="ns")

if cocotb.SIM_NAME:
    data_width = len(cocotb.top.s0_axi_wdata)

    for test in [run_test_write_read, run_test_write_read_in_parallel, run_test_sweep, run_test_byte_strobes]:
        factory = TestFactory(test)
        factory.generate_tests()
