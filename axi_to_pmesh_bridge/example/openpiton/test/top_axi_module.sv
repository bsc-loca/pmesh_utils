/* ------------------------------------------------------------------
 * Organization   : Barcelona Supercomputing Center
 * File           : top_axi_module.sv
 * Description    : top axi module containing axi_to_pmesh_bridge, 
 *                  noc_axi4_bridge and axi_ram. This is a part of
 *                  cocotb testbench                   
 * ------------------------------------------------------------------
 * COPYRIGHT
 *  Copyright (c) Barcelona Supercomputing Center, 2024-2025.
 * ------------------------------------------------------------------
 * LICENSE
 *  Licensed under the Solderpad Hardware License v 2.1 (the
 *  "License"); you may not use this file except in compliance
 *  with the License, or, at your option, the Apache License
 *  version 2.0. You may obtain a copy of the License at
 *
 *  http://www.solderpad.org/licenses/SHL-2.1
 *
 *  Unless required by applicable law or agreed to in writing,
 *  work distributed under the License is distributed on an
 *  "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
 *  either express or implied. See the License for the specific
 *  language governing permissions and limitations under the License.
 * ------------------------------------------------------------------
 * Revision History
 *  Revision   | Author                                 | Description
 *  0.0.1      | Manjunath - manjunath.kalmath@bsc.es   | initial code version
 * ------------------------------------------------------------------
 * DUT PARAMETERS:
 * BRIDGE_IN_FLIGHT_REQS        = number of in-flight requests managed by the bridge.
 * BRIDGE_EXTEND_RESET          = extend the reset internally to delay early cache accesses.
 *
 * BRIDGE_TRAP_0BYTE_WRITES     = trap AXI 0-byte write requests and acknowledge them locally.
 * BRIDGE_UNROLLER_FIFO_FT      = activate transfer unroller FIFO fall-through path.
 *
 * BRIDGE_SUPPORT_AXI_AXCACHE   = support AXI ARCACHE and AWCACHE signals.
 * BRIDGE_SUPPORT_NON_CACHEABLE = support non-cacheable accesses through the bridge.
 *
 * TESTBENCH PARAMETERS:
 * - PMESH WIDTH ADAPTER
 *     ADAPT_REGISTER_BYPASS    = introduce a register in the bypass - can help closing time.
 * ------------------------------------------------------------------
 * NOTES:
 * - activating the transfer unroller FIFO fall-through path improves performance but may
 *      complicate achieving timing closure.
 * - AXI 0-byte write requests are legal, they are bridged as PMESH 0-byte atomic SWAP operation.
 *      PMESH appears not to handle this type of operation correctly - may need to trap them.
 * - cacheability is decided based on AXI request and system address map:
 *      cacheable = cacheable in AXI request AND cacheable in system address map
 * ------------------------------------------------------------------
 * TODO:
 * ------------------------------------------------------------------
 */

`include "define.tmp.h"
`include "l2.tmp.h"
`include "noc_axi4_bridge_define.vh"
`include "tc2_addrmap.tmp.svh"

module top_axi_module
import axi_to_pmesh_bridge_pkg::*;
#(
  parameter unsigned BRIDGE_IN_FLIGHT_REQS        = 8,
  parameter unsigned BRIDGE_EXTEND_RESET          = 0,
  parameter unsigned BRIDGE_TRAP_0BYTE_WRITES     = 1,
  parameter unsigned BRIDGE_UNROLLER_FIFO_FT      = 1,
  parameter unsigned BRIDGE_SUPPORT_AXI_AXCACHE   = 1,
  parameter unsigned BRIDGE_SUPPORT_NON_CACHEABLE = 1,

  parameter unsigned ADAPT_REGISTER_BYPASS        = 0
)(
    //clk and rstn signals
    input                              clk, 
    input                              rstn, //This active low reset
    
    //Write Address Channel Signals
    input  [AXI_ID_WIDTH     -1:0]   s0_axi_awid,
    input  [AXI_ADDR_WIDTH   -1:0]   s0_axi_awaddr,
    input  [AXI_LEN_WIDTH    -1:0]   s0_axi_awlen,
    input  [AXI_SIZE_WIDTH   -1:0]   s0_axi_awsize,
    input  [AXI_BURST_WIDTH  -1:0]   s0_axi_awburst,
    input                            s0_axi_awlock,
    input  [AXI_CACHE_WIDTH  -1:0]   s0_axi_awcache,
    input  [AXI_PROT_WIDTH   -1:0]   s0_axi_awprot,
    input  [AXI_QOS_WIDTH    -1:0]   s0_axi_awqos,
    input  [AXI_REGION_WIDTH -1:0]   s0_axi_awregion,
    input  [AXI_USER_WIDTH   -1:0]   s0_axi_awuser,
    input                            s0_axi_awvalid,
    output                           s0_axi_awready,

    //Write Data Channel Signals    
    input  [AXI_DATA_WIDTH   -1:0]   s0_axi_wdata,
    input  [AXI_WSTRB_WIDTH  -1:0]   s0_axi_wstrb,
    input                            s0_axi_wlast,
    input  [AXI_USER_WIDTH   -1:0]   s0_axi_wuser,
    input                            s0_axi_wvalid,
    output                           s0_axi_wready,

    //Write Response Channel Signals
    output [AXI_ID_WIDTH     -1:0]   s0_axi_bid,
    output [AXI_RESP_WIDTH   -1:0]   s0_axi_bresp,
    output [AXI_USER_WIDTH   -1:0]   s0_axi_buser,
    output                           s0_axi_bvalid,
    input                            s0_axi_bready,

    //Read Address Channel Signals
    input  [AXI_ID_WIDTH     -1:0]   s0_axi_arid,
    input  [AXI_ADDR_WIDTH   -1:0]   s0_axi_araddr,
    input  [AXI_LEN_WIDTH    -1:0]   s0_axi_arlen,
    input  [AXI_SIZE_WIDTH   -1:0]   s0_axi_arsize,
    input  [AXI_BURST_WIDTH  -1:0]   s0_axi_arburst,
    input                            s0_axi_arlock,
    input  [AXI_CACHE_WIDTH  -1:0]   s0_axi_arcache,
    input  [AXI_PROT_WIDTH   -1:0]   s0_axi_arprot,
    input  [AXI_QOS_WIDTH    -1:0]   s0_axi_arqos,
    input  [AXI_REGION_WIDTH -1:0]   s0_axi_arregion,
    input  [AXI_USER_WIDTH   -1:0]   s0_axi_aruser,
    input                            s0_axi_arvalid,
    output                           s0_axi_arready,

    //Read Data Channel Signals
    output [AXI_ID_WIDTH     -1:0]   s0_axi_rid,
    output [AXI_DATA_WIDTH   -1:0]   s0_axi_rdata,
    output [AXI_RESP_WIDTH   -1:0]   s0_axi_rresp,
    output                           s0_axi_rlast,
    output [AXI_USER_WIDTH   -1:0]   s0_axi_ruser,  
    output                           s0_axi_rvalid,
    input                            s0_axi_rready
);

//localparameters
//This is duplication but avoids warning during compilation
localparam unsigned PITON_NUM_TILES = `PITON_NUM_TILES;

//Internal Signals
//NoC Interface between axi_to_pmesh_bridge <-> NoC_AXI4_bridge
logic                            noc1_valid_out;
logic [`PITON_NOC1_WIDTH -1:0]   noc1_data_out;
logic                            noc1_ready_in;
logic                            noc2_valid_in;
logic [`PITON_NOC2_WIDTH -1:0]   noc2_data_in;
logic                            noc2_ready_out;

// need to adjust pmesh size between axi_to_pmesh_bridge amd noc_axi4_bridge
logic                            noc1_2_valid;
logic [`PITON_NOC2_WIDTH -1:0]   noc1_2_data;
logic                            noc1_2_ready;

logic                            noc3_2_valid;
logic [`PITON_NOC3_WIDTH -1:0]   noc3_2_data;
logic                            noc3_2_ready;

//AXI-Master Interface Channel Signals between NoC_AXI4_bridge and AXI_RAM
//Write Address Channel Signals
wire [`AXI4_ID_WIDTH      -1:0] m0_axi_awid;
wire [`AXI4_ADDR_WIDTH    -1:0] m0_axi_awaddr;
wire [`AXI4_LEN_WIDTH     -1:0] m0_axi_awlen;
wire [`AXI4_SIZE_WIDTH    -1:0] m0_axi_awsize;
wire [`AXI4_BURST_WIDTH   -1:0] m0_axi_awburst;
wire                            m0_axi_awlock;
wire [`AXI4_CACHE_WIDTH  -1:0]  m0_axi_awcache;
wire [`AXI4_PROT_WIDTH   -1:0]  m0_axi_awprot;
wire [`AXI4_QOS_WIDTH    -1:0]  m0_axi_awqos;
wire [`AXI4_REGION_WIDTH -1:0]  m0_axi_awregion;
wire [`AXI4_USER_WIDTH   -1:0]  m0_axi_awuser;
wire                            m0_axi_awvalid;
wire                            m0_axi_awready;

//Write Data Channel Signals 
wire [`AXI4_DATA_WIDTH_USED -1:0]  m0_axi_wdata;
wire [`AXI4_STRB_WIDTH_USED -1:0]  m0_axi_wstrb;
wire                               m0_axi_wlast;
wire [`AXI4_USER_WIDTH   -1:0]     m0_axi_wuser;
wire                               m0_axi_wvalid;
wire                               m0_axi_wready;

//Write Response Channel Signals
wire [`AXI4_ID_WIDTH    -1:0]  m0_axi_bid;
wire [`AXI4_RESP_WIDTH  -1:0]  m0_axi_bresp;
wire [`AXI4_USER_WIDTH  -1:0]  m0_axi_buser;
wire                           m0_axi_bvalid;
wire                           m0_axi_bready;

//Read Address Channel Signals
wire [`AXI4_ID_WIDTH     -1:0]  m0_axi_arid;
wire [`AXI4_ADDR_WIDTH   -1:0]  m0_axi_araddr;
wire [`AXI4_LEN_WIDTH    -1:0]  m0_axi_arlen;
wire [`AXI4_SIZE_WIDTH   -1:0]  m0_axi_arsize;
wire [`AXI4_BURST_WIDTH  -1:0]  m0_axi_arburst;
wire                            m0_axi_arlock;
wire [`AXI4_CACHE_WIDTH  -1:0]  m0_axi_arcache;
wire [`AXI4_PROT_WIDTH   -1:0]  m0_axi_arprot;
wire [`AXI4_QOS_WIDTH    -1:0]  m0_axi_arqos;
wire [`AXI4_REGION_WIDTH -1:0]  m0_axi_arregion;
wire [`AXI4_USER_WIDTH   -1:0]  m0_axi_aruser;
wire                            m0_axi_arvalid;
wire                            m0_axi_arready;

//Read Data Channel Signals 
wire [`AXI4_ID_WIDTH        -1:0]   m0_axi_rid;
wire [`AXI4_DATA_WIDTH_USED -1:0]   m0_axi_rdata;
wire [`AXI4_RESP_WIDTH      -1:0]   m0_axi_rresp;
wire                                m0_axi_rlast;
wire [`AXI4_USER_WIDTH      -1:0]   m0_axi_ruser;
wire                                m0_axi_rvalid;
wire                                m0_axi_rready;

wire                                axi_id_deadlock;

//axi_to_pmesh_bridge
axi_to_pmesh_bridge #(
  .BRIDGE_IN_FLIGHT_REQS        (BRIDGE_IN_FLIGHT_REQS),
  .BRIDGE_EXTEND_RESET          (BRIDGE_EXTEND_RESET),
  .BRIDGE_TRAP_0BYTE_WRITES     (BRIDGE_TRAP_0BYTE_WRITES),
  .BRIDGE_UNROLLER_FIFO_FT      (BRIDGE_UNROLLER_FIFO_FT),
  .BRIDGE_SUPPORT_AXI_AXCACHE   (BRIDGE_SUPPORT_AXI_AXCACHE),
  .BRIDGE_SUPPORT_NON_CACHEABLE (BRIDGE_SUPPORT_NON_CACHEABLE),
  .SYS_ADDR_SIZE                (`PHY_ADDR_WIDTH),
  .N_IO_SECTIONS                (NIOSections),
  .INIT_IO_BASE                 (InitIOBase),
  .INIT_IO_END                  (InitIOEnd)
) axi_to_pmesh_bridge_inst(
    //clk and rstn signals
    .clk(clk),
    .rst_n(rstn),

    //Write Address Channel Signals
    .s_axi_awready(s0_axi_awready),
    .s_axi_awaddr (s0_axi_awaddr ),
    .s_axi_awvalid(s0_axi_awvalid),
    .s_axi_awlen  (s0_axi_awlen  ),
    .s_axi_awsize (s0_axi_awsize ),
    .s_axi_awid   (s0_axi_awid   ),
    .s_axi_awburst(s0_axi_awburst),
    .s_axi_awlock (s0_axi_awlock ),
    .s_axi_awcache(s0_axi_awcache),
    .s_axi_awprot (s0_axi_awprot ),
    .s_axi_awqos  (s0_axi_awqos  ),
    .s_axi_awregion(s0_axi_awregion),
    .s_axi_awuser (s0_axi_awuser),
    
    //Write Data Channel Signals 
    .s_axi_wready(s0_axi_wready),
    .s_axi_wvalid(s0_axi_wvalid),
    .s_axi_wdata (s0_axi_wdata),
    .s_axi_wstrb (s0_axi_wstrb),
    .s_axi_wlast (s0_axi_wlast),
    .s_axi_wuser (s0_axi_wuser),

    //Write Response Channel Signals
    .s_axi_bvalid(s0_axi_bvalid),
    .s_axi_bready(s0_axi_bready),
    .s_axi_bid   (s0_axi_bid),
    .s_axi_bresp (s0_axi_bresp),
    .s_axi_buser (s0_axi_buser),

    //Read Address Channel Signals 
    .s_axi_arready(s0_axi_arready),
    .s_axi_araddr (s0_axi_araddr ),
    .s_axi_arvalid(s0_axi_arvalid),
    .s_axi_arlen  (s0_axi_arlen  ),
    .s_axi_arsize (s0_axi_arsize ),
    .s_axi_arid   (s0_axi_arid   ),
    .s_axi_arburst(s0_axi_arburst),
    .s_axi_arlock (s0_axi_arlock ),
    .s_axi_arcache(s0_axi_arcache),
    .s_axi_arprot (s0_axi_arprot ),
    .s_axi_arqos  (s0_axi_arqos  ),
    .s_axi_arregion(s0_axi_arregion),
    .s_axi_aruser (s0_axi_aruser),

    //Read Data Channel Signals
    .s_axi_rready(s0_axi_rready),
    .s_axi_rvalid(s0_axi_rvalid),
    .s_axi_rdata (s0_axi_rdata),
    .s_axi_rlast (s0_axi_rlast),
    .s_axi_ruser (s0_axi_ruser),
    .s_axi_rid   (s0_axi_rid),
    .s_axi_rresp (s0_axi_rresp),

    //NoC
    .noc1_data_out (noc1_data_out),
    .noc1_valid_out(noc1_valid_out),
    .noc1_ready_in (noc1_ready_in),
    .noc2_data_in  (noc2_data_in),
    .noc2_valid_in (noc2_valid_in),
    .noc2_ready_out(noc2_ready_out),

    //Source
    .src_chipid(14'b0),
    .src_xpos  (`DMA_XPOS),
    .src_ypos  (`DMA_YPOS),
    .src_fbits (`NOC_FBITS_DMA), 

    //Destination
    .dest_chipid(14'b0),
    .dest_fbits (`NOC_FBITS_L2),

    //number of tiles and home allocation method
    .noc_num_tiles(PITON_NUM_TILES[5:0]),
    .noc_home_alloc_meth(`HOME_ALLOC_MIXED_ORDER_BITS)
);

// adjust pmesh messages of different widths in NoC1 to NoC2 connection
pmesh_width_adapter #(
    .ADAPT_INPUT_NOC_BITS  (`PITON_NOC1_WIDTH),
    .ADAPT_OUTPUT_NOC_BITS (`PITON_NOC2_WIDTH),
    .ADAPT_REGISTER_BYPASS (ADAPT_REGISTER_BYPASS)
) pmesh_adapter_noc1_noc2 (
    .clk                   (clk),
    .rst_n                 (rstn),
    .input_noc_valid_in    (noc1_valid_out),
    .input_noc_data_in     (noc1_data_out),
    .input_noc_ready_out   (noc1_ready_in),
    .output_noc_valid_out  (noc1_2_valid),
    .output_noc_data_out   (noc1_2_data),
    .output_noc_ready_in   (noc1_2_ready)
);

// adjust pmesh messages of different widths in NoC3 to NoC2 connection
pmesh_width_adapter #(
    .ADAPT_INPUT_NOC_BITS  (`PITON_NOC3_WIDTH),
    .ADAPT_OUTPUT_NOC_BITS (`PITON_NOC2_WIDTH),
    .ADAPT_REGISTER_BYPASS (ADAPT_REGISTER_BYPASS)
) pmesh_adapter_noc3_noc2 (
    .clk                   (clk),
    .rst_n                 (rstn),
    .input_noc_valid_in    (noc3_2_valid),
    .input_noc_data_in     (noc3_2_data),
    .input_noc_ready_out   (noc3_2_ready),
    .output_noc_valid_out  (noc2_valid_in),
    .output_noc_data_out   (noc2_data_in),
    .output_noc_ready_in   (noc2_ready_out)
);

//NoC-AXI4 Bridge 
noc_axi4_bridge #(.SWAP_ENDIANESS(1),
                     .NUM_REQ_OUTSTANDING_LOG2(1),
                     `ifdef SRAM_IP
                     .OUTSTAND_QUEUE_BRAM(0),
                     `endif  // SRAM_IP
                     .AXI4_DAT_WIDTH_USED(`AXI4_DATA_WIDTH_USED))
noc_axi4_bridge_inst(
    //clk and rstn signals
    .clk(clk),
    .rst_n(rstn),

    //uart related
    .uart_boot_en(1'b0), 
    .phy_init_done(1'b1), 
    .axi_id_deadlock(axi_id_deadlock),

    //Write Address Channel Signals
    .m_axi_awid(m0_axi_awid),
    .m_axi_awaddr(m0_axi_awaddr),
    .m_axi_awlen(m0_axi_awlen),
    .m_axi_awsize(m0_axi_awsize),
    .m_axi_awburst(m0_axi_awburst),
    .m_axi_awlock(m0_axi_awlock),
    .m_axi_awcache(m0_axi_awcache),
    .m_axi_awprot(m0_axi_awprot),
    .m_axi_awqos(m0_axi_awqos),
    .m_axi_awregion(m0_axi_awregion),
    .m_axi_awuser(m0_axi_awuser),
    .m_axi_awvalid(m0_axi_awvalid),
    .m_axi_awready(m0_axi_awready),

    //Write Data Channel Signals
    .m_axi_wdata(m0_axi_wdata),
    .m_axi_wstrb(m0_axi_wstrb),
    .m_axi_wlast(m0_axi_wlast),
    .m_axi_wuser(m0_axi_wuser),
    .m_axi_wvalid(m0_axi_wvalid),
    .m_axi_wready(m0_axi_wready),

    //Write Response Channel Signals
    .m_axi_bid(m0_axi_bid),
    .m_axi_bresp(m0_axi_bresp),
    .m_axi_buser(m0_axi_buser),
    .m_axi_bvalid(m0_axi_bvalid),
    .m_axi_bready(m0_axi_bready),

    //Read Address Channel Signals
    .m_axi_arid(m0_axi_arid),
    .m_axi_araddr(m0_axi_araddr),
    .m_axi_arlen(m0_axi_arlen),
    .m_axi_arsize(m0_axi_arsize),
    .m_axi_arburst(m0_axi_arburst),
    .m_axi_arlock(m0_axi_arlock),
    .m_axi_arcache(m0_axi_arcache),
    .m_axi_arprot(m0_axi_arprot),
    .m_axi_arqos(m0_axi_arqos),
    .m_axi_arregion(m0_axi_arregion),
    .m_axi_aruser(m0_axi_aruser),
    .m_axi_arvalid(m0_axi_arvalid),
    .m_axi_arready(m0_axi_arready),

    //Read Data Channel Signals
    .m_axi_rid(m0_axi_rid),
    .m_axi_rdata(m0_axi_rdata),
    .m_axi_rresp(m0_axi_rresp),
    .m_axi_rlast(m0_axi_rlast),
    .m_axi_ruser(m0_axi_ruser),
    .m_axi_rvalid(m0_axi_rvalid),
    .m_axi_rready(m0_axi_rready),

    //NoC Interface
    .src_bridge_vr_noc2_val(noc1_2_valid),
    .src_bridge_vr_noc2_dat(noc1_2_data),
    .src_bridge_vr_noc2_rdy(noc1_2_ready),
    .bridge_dst_vr_noc3_val(noc3_2_valid),
    .bridge_dst_vr_noc3_dat(noc3_2_data),
    .bridge_dst_vr_noc3_rdy(noc3_2_ready)
);

//AXI RAM
axi_ram #(
    .DATA_WIDTH(`AXI4_DATA_WIDTH_USED),
    .ADDR_WIDTH(8),
    .STRB_WIDTH(`AXI4_STRB_WIDTH_USED),
    .ID_WIDTH(`AXI4_ID_WIDTH),
    .PIPELINE_OUTPUT(0)
)axi_ram_inst(
    //clk and rstn siganls
    .clk(clk),
    .rst(rstn),

    //Write Address Channel Signals
    .s_axi_awid(m0_axi_awid),
    .s_axi_awaddr(m0_axi_awaddr[7:0]),
    .s_axi_awlen(m0_axi_awlen),
    .s_axi_awsize(m0_axi_awsize),
    .s_axi_awburst(m0_axi_awburst),
    .s_axi_awlock(m0_axi_awlock),
    .s_axi_awcache(m0_axi_awcache),
    .s_axi_awprot(m0_axi_awprot),
    .s_axi_awvalid(m0_axi_awvalid),
    .s_axi_awready(m0_axi_awready),

    //Write Data Channel Signals 
    .s_axi_wdata(m0_axi_wdata),
    .s_axi_wstrb(m0_axi_wstrb),
    .s_axi_wlast(m0_axi_wlast),
    .s_axi_wvalid(m0_axi_wvalid),
    .s_axi_wready(m0_axi_wready),

    //Write Response Signals
    .s_axi_bid(m0_axi_bid),
    .s_axi_bresp(m0_axi_bresp),
    .s_axi_bvalid(m0_axi_bvalid),
    .s_axi_bready(m0_axi_bready),

    //Read Address Channel Signals
    .s_axi_arid(m0_axi_arid),
    .s_axi_araddr(m0_axi_araddr[7:0]),
    .s_axi_arlen(m0_axi_arlen),
    .s_axi_arsize(m0_axi_arsize),
    .s_axi_arburst(m0_axi_arburst),
    .s_axi_arlock(m0_axi_arlock),
    .s_axi_arcache(m0_axi_arcache),
    .s_axi_arprot(m0_axi_arprot),
    .s_axi_arvalid(m0_axi_arvalid),
    .s_axi_arready(m0_axi_arready),    

    //Read Data Channel Signals
    .s_axi_rid(m0_axi_rid),
    .s_axi_rdata(m0_axi_rdata),
    .s_axi_rresp(m0_axi_rresp),
    .s_axi_rlast(m0_axi_rlast),
    .s_axi_rvalid(m0_axi_rvalid),
    .s_axi_rready(m0_axi_rready)
);

endmodule
