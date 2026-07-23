/* ------------------------------------------------------------------
 * Organization   : Barcelona Supercomputing Center
 * File           : axi_to_pmesh_bridge.sv
 * Description    : Top module which converts AXI transactions to
 *                  OpenPiton PMESH (NoC) transfers. It instantiates
 *                  modules axi_slave_wrapper_pipeline and noc_driver.
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
 *  Revision   | Author                             | Description
 *  0.0.1      | Abbas Haghi - abbas.haghi@bsc.es   | initial code version
 *             | lap - luis.plana@bsc.es            | initial code version
 * ------------------------------------------------------------------
 * PARAMETERS:
 * BRIDGE_IN_FLIGHT_REQS        = number of in-flight requests managed by the bridge.
 * BRIDGE_EXTEND_RESET          = extend the reset internally to delay early cache accesses.
 *
 * BRIDGE_TRAP_0BYTE_WRITES     = trap AXI 0-byte write requests and acknowledge them locally.
 * BRIDGE_UNROLLER_FIFO_FT      = activate transfer unroller FIFO fall-through path.
 *
 * BRIDGE_SUPPORT_AXI_AXCACHE   = support AXI ARCACHE and AWCACHE signals.
 * BRIDGE_SUPPORT_NON_CACHEABLE = support non-cacheable accesses through the bridge.
 *
 * The following parameters are only meaningful if BRIDGE_SUPPORT_NON_CACHEABLE == 1:
 * SYS_ADDR_SIZE = system address size: max between Virtual Address size and Physical Address Size.
 * N_IO_SECTIONS = number of I/O (non_cacheable) sections in address map.
 *
 * The following parameters are arrays of N_IO_SECTIONS elements:
 * INIT_IO_BASE  = base address for each I/O section (included in the section).
 * INIT_IO_END   = end  address for each I/O section (not included in the section).
 * ------------------------------------------------------------------
 * NOTES:
 * - activating the transfer unroller FIFO fall-through path improves performance but may
 *      complicate achieving timing closure.
 * - AXI 0-byte write requests are legal, they are bridged as PMESH 0-byte atomic SWAP operation.
 *      PMESH appears not to handle this type of operation correctly - may need to trap them.
 * - cacheable load requests are bridged as LOAD_NOSHARE pmesh operations.
 * - cacheable store requests are bridged as SWAP_WB atomic pmesh operations.
 * - non-cacheable load requests are bridged as NC_LOAD pmesh operations.
 * - non-cacheable store requests are bridged as NC_STORE pmesh operations.
 * - cacheability is decided based on AXI request and system address map:
 *      cacheable = cacheable in AXI request AND cacheable in system address map
 * ------------------------------------------------------------------
 * TODO:
 * - redesign the bridge to make a more efficient use of in-flight transactions and transfers.
 * - clean up support for multi-flit PMESH NoC responses - not an immediate need.
 * - clean up AXI unaligned access management - pmesh does NOT support unaligned accesses.
  * ------------------------------------------------------------------
 */

module axi_to_pmesh_bridge
import axi_to_pmesh_bridge_pkg::*;
#(
  parameter unsigned BRIDGE_IN_FLIGHT_REQS        = 8,
  parameter unsigned BRIDGE_EXTEND_RESET          = 0,
  parameter unsigned BRIDGE_TRAP_0BYTE_WRITES     = 1,
  parameter unsigned BRIDGE_UNROLLER_FIFO_FT      = 1,
  parameter unsigned BRIDGE_SUPPORT_AXI_AXCACHE   = 0,
  parameter unsigned BRIDGE_SUPPORT_NON_CACHEABLE = 0,

  // IO addresses - non-cacheable
  parameter int unsigned                                 SYS_ADDR_SIZE = $bits (aif_addr_t),      //! system address size: max between Virtual Address size and Physical Address Size.
  parameter int unsigned                                 N_IO_SECTIONS =  1,
  parameter logic [N_IO_SECTIONS-1:0][SYS_ADDR_SIZE-1:0] INIT_IO_BASE  = {SYS_ADDR_SIZE {1'b0}},  // defaults to all cacheable accesses
  parameter logic [N_IO_SECTIONS-1:0][SYS_ADDR_SIZE-1:0] INIT_IO_END   = {SYS_ADDR_SIZE {1'b0}}
)
(
    //ADD to NOC signals here
    output  noc1_data_t                  noc1_data_out      ,
    output  logic                        noc1_valid_out     ,
    input   logic                        noc1_ready_in      ,

    input   noc2_data_t                  noc2_data_in       ,
    input   logic                        noc2_valid_in      ,
    output  logic                        noc2_ready_out     ,

    input   noc_src_chipid_t             src_chipid         ,
    input   noc_src_x_t                  src_xpos           ,
    input   noc_src_y_t                  src_ypos           ,
    input   noc_src_fbits_t              src_fbits          ,

    input   noc_dst_chipid_t             dest_chipid        ,
    input   noc_dst_fbits_t              dest_fbits         ,

    input   noc_num_tiles_t              noc_num_tiles      ,
    input   noc_home_alloc_meth_t        noc_home_alloc_meth,

    // AXI SIGNALS
    input   wire                         clk                ,
    input   wire                         rst_n              ,

    // AXI Read Signals
    output  wire                         s_axi_arready      ,
    input   wire [AXI_ADDR_WIDTH-1:0]    s_axi_araddr       ,
    input   wire                         s_axi_arvalid      ,
    input   wire [AXI_LEN_WIDTH-1:0]     s_axi_arlen        ,
    input   wire [AXI_SIZE_WIDTH-1:0]    s_axi_arsize       ,
    input   wire [AXI_ID_WIDTH-1:0]      s_axi_arid         ,
    input   wire [AXI_BURST_WIDTH-1:0]   s_axi_arburst      ,
    input   wire                         s_axi_arlock       ,
    input   wire [AXI_CACHE_WIDTH-1:0]   s_axi_arcache      ,
    input   wire [AXI_PROT_WIDTH-1:0]    s_axi_arprot       ,
    input   wire [AXI_QOS_WIDTH-1:0]     s_axi_arqos        ,
    input   wire [AXI_REGION_WIDTH-1:0]  s_axi_arregion     ,
    input   wire [AXI_USER_WIDTH-1:0]    s_axi_aruser       ,
    input   wire                         s_axi_rready       ,
    output  wire                         s_axi_rvalid       ,
    output  wire [AXI_DATA_WIDTH-1:0]    s_axi_rdata        ,
    output  wire                         s_axi_rlast        ,
    output  wire [AXI_USER_WIDTH-1:0]    s_axi_ruser        ,
    output  wire [AXI_ID_WIDTH-1:0]      s_axi_rid          ,
    output  wire [AXI_RESP_WIDTH-1:0]    s_axi_rresp        ,

    // AXI Write Signals
    output  wire                         s_axi_awready      ,
    input   wire [AXI_ADDR_WIDTH-1:0]    s_axi_awaddr       ,
    input   wire                         s_axi_awvalid      ,
    input   wire [AXI_LEN_WIDTH-1:0]     s_axi_awlen        ,
    input   wire [AXI_SIZE_WIDTH-1:0]    s_axi_awsize       ,
    input   wire [AXI_ID_WIDTH-1:0]      s_axi_awid         ,
    input   wire [AXI_BURST_WIDTH-1:0]   s_axi_awburst      ,
    input   wire                         s_axi_awlock       ,
    input   wire [AXI_CACHE_WIDTH-1:0]   s_axi_awcache      ,
    input   wire [AXI_PROT_WIDTH-1:0]    s_axi_awprot       ,
    input   wire [AXI_QOS_WIDTH-1:0]     s_axi_awqos        ,
    input   wire [AXI_REGION_WIDTH-1:0]  s_axi_awregion     ,
    input   wire [AXI_USER_WIDTH-1:0]    s_axi_awuser       ,
    output  wire                         s_axi_wready       ,
    input   wire                         s_axi_wvalid       ,
    input   wire [AXI_DATA_WIDTH-1:0]    s_axi_wdata        ,
    input   wire [AXI_WSTRB_WIDTH-1:0]   s_axi_wstrb        ,
    input   wire                         s_axi_wlast        ,
    input   wire [AXI_USER_WIDTH-1:0]    s_axi_wuser        ,
    output  wire                         s_axi_bvalid       ,
    input   wire                         s_axi_bready       ,
    output  wire [AXI_ID_WIDTH-1:0]      s_axi_bid          ,
    output  wire [AXI_USER_WIDTH-1:0]    s_axi_buser        ,
    output  wire [AXI_RESP_WIDTH-1:0]    s_axi_bresp
);

localparam unsigned IFID_BITS_MAX = (BRIDGE_SUPPORT_NON_CACHEABLE) ? (MSG_MSHR_BITS - NCLD_BITS) : (MSG_MSHR_BITS - 1);
localparam unsigned IN_FLIGHT_MAX = (1 << IFID_BITS_MAX);

// AXI slave currently needs to allocate resources for a minimum number of transactions in flight
localparam unsigned ADJUSTED_IN_FLIGHT_REQS = (BRIDGE_IN_FLIGHT_REQS > BRIDGE_IN_FLIGHT_REQ_MIN) ? BRIDGE_IN_FLIGHT_REQS : BRIDGE_IN_FLIGHT_REQ_MIN;

// AXI slave splits the number of in-flight transactions between reads and writes - this may need revisiting
//NOTE: a check may be necessary if the minimum value for ADJUSTED_IN_FLIGHT_REQS changes
localparam unsigned IN_FLIGHT_AXI_SPLIT = ADJUSTED_IN_FLIGHT_REQS / 2;

// ----------------------------------------------------------------
// compile-time parameter value checks:
// - only single cache-line NoC requests are supported
// - cache line size is limited to CACHE_LINE_BITS_MAX bits
// - atomic tansfer size is limited to ATOMIC_TRF_BITS_MAX bits
// - non-cacheable store width is limited to NC_STORE_BITS_MAX bits
// - only IN_FLIGHT_MAX in-flight transfers are supported
// ----------------------------------------------------------------
generate
  if (AXI_DATA_WIDTH > CACHE_LINE_BITS) begin : axi_data_width_check_gen
    $fatal (1, "error: [axi_to_pmesh_bridge] unsupported AXI_DATA_WIDTH setting");
  end

  if (CACHE_LINE_BITS > CACHE_LINE_BITS_MAX) begin : cache_line_bits_check_gen
    $fatal (1, "error: [axi_to_pmesh_bridge] unsupported CACHE_LINE_BITS setting");
  end

  if ((ATOMIC_TRF_BITS > CACHE_LINE_BITS) || (ATOMIC_TRF_BITS > ATOMIC_TRF_BITS_MAX)) begin : atomic_trf_bits_check_gen
    $fatal (1, "error: [axi_to_pmesh_bridge] unsupported ATOMIC_TRF_BITS setting");
  end

  if ((NC_STORE_BITS > CACHE_LINE_BITS) || (NC_STORE_BITS > NC_STORE_BITS_MAX)) begin : no_store_bits_check_gen
    $fatal (1, "error: [axi_to_pmesh_bridge] unsupported NC_STORE_BITS setting");
  end

  if (BRIDGE_IN_FLIGHT_REQS > IN_FLIGHT_MAX) begin : bridge_in_flight_reqs_check_gen
    $fatal (1, "error: [axi_to_pmesh_bridge] unsupported BRIDGE_IN_FLIGHT_REQS setting");
  end
endgenerate
// ----------------------------------------------------------------

// ----------------------------------------------------------------
// signals
// ----------------------------------------------------------------
// Read Addrs FIFO signals
wire                           s_rd_addr_fifo_wr_rq;
wire                           s_rd_addr_fifo_rd_rq;
wire [RD_ADDR_FIFO_WIDTH-1:0]  s_rd_addr_fifo_data_out;
wire [RD_ADDR_FIFO_WIDTH-1:0]  s_rd_addr_fifo_data_in;
wire                           s_rd_addr_fifo_empty;
wire                           s_rd_addr_fifo_full;

// Read Data FIFO signals: this fifo should be show ahead
wire                           s_rd_data_fifo_rd_rq;
wire                           s_rd_data_fifo_wr_rq;
wire [RD_DATA_FIFO_WIDTH-1:0]  s_rd_data_fifo_data_in;
wire [RD_DATA_FIFO_WIDTH-1:0]  s_rd_data_fifo_data_out;
wire                           s_rd_data_fifo_empty;
wire                           s_rd_data_fifo_full;

// Write Addrs/Data FIFO signals
wire                           s_wr_fifo_wr_rq;
wire                           s_wr_fifo_rd_rq;
wire [WR_FIFO_WIDTH-1:0]       s_wr_fifo_data_in;
wire [WR_FIFO_WIDTH-1:0]       s_wr_fifo_data_out;
wire                           s_wr_fifo_empty;
wire                           s_wr_fifo_full;

// Write ACK from NOC Bridge
wire                           s_noc_wack;  // ACK must be 1 only for 1 cycle

// internal reset signal - can be an extension of the external reset to delay interactions with memory
wire                           internal_rst_n;
// ----------------------------------------------------------------


// ----------------------------------------------------------------
// extended reset -- allows caches time to initialise
// ----------------------------------------------------------------
// if requested through parameter BRIDGE_EXTEND_RESET == 1, extend the reset internally to delay
// memory accesses. This gives the cache memories time to initialise correctly.
generate
  //NOTE: this code was taken, with minor signal name changes, from 'lagarto_ox_wrapper.sv'
  //https://gitlab.bsc.es/hwdesign/chips/zetta-tc2/-/blob/main/piton/design/chip/tile/rtl/lagarto_ox_wrapper.sv#L182-204
  // following a recommendation by Arnau Bigas Soldevila @arnau.bigas:
  // latch the reset active until a pre-defined timer runs out, after which the SRAMs are guaranteed to be initialized.
  if (BRIDGE_EXTEND_RESET == 1) begin : extended_rst
    logic [15:0] wake_up_cnt_d, wake_up_cnt_q;

    assign wake_up_cnt_d = (wake_up_cnt_q[$high(wake_up_cnt_q)]) ? wake_up_cnt_q : wake_up_cnt_q + 1;

    always_ff @(posedge clk or negedge rst_n) begin : p_regs
      if(~rst_n) begin
        wake_up_cnt_q <= 0;
      end else begin
        wake_up_cnt_q <= wake_up_cnt_d;
      end
    end

    // reset gate this
    assign internal_rst_n = wake_up_cnt_q[$high(wake_up_cnt_q)];
  end else begin  : no_extended_rst // BRIDGE_EXTEND_RESET == 0
    assign internal_rst_n = 1'b1;
  end
endgenerate
// ----------------------------------------------------------------

// ----------------------------------------------------------------
// AXI slave -- services AXI requests
// ----------------------------------------------------------------
axi_slave_wrapper_pipeline #(
    .ON_FLY_WR_NUM(IN_FLIGHT_AXI_SPLIT),
    .ON_FLY_RD_NUM(IN_FLIGHT_AXI_SPLIT),
    .BRIDGE_SUPPORT_AXI_AXCACHE(BRIDGE_SUPPORT_AXI_AXCACHE)
)
axi_slave(
    .o_rd_addr_fifo_wr_rq (s_rd_addr_fifo_wr_rq)   ,
    .o_rd_addr_fifo_data  (s_rd_addr_fifo_data_in) ,
    //.i_rd_addr_fifo_empty (s_rd_addr_fifo_empty)   ,
    .i_rd_addr_fifo_full  (s_rd_addr_fifo_full)    ,
    .o_rd_data_fifo_rd_rq (s_rd_data_fifo_rd_rq)   ,
    .i_rd_data_fifo_data  (s_rd_data_fifo_data_out),
    .i_rd_data_fifo_empty (s_rd_data_fifo_empty)   ,
    .o_wr_fifo_wr_rq      (s_wr_fifo_wr_rq)        ,
    .o_wr_fifo_data       (s_wr_fifo_data_in)      ,
    //.i_wr_fifo_empty      (s_wr_fifo_empty)        ,
    .i_wr_fifo_full       (s_wr_fifo_full)         ,
    .i_NOC_WACK           (s_noc_wack)             ,
    .S_AXI_ACLK           (clk)                    ,
    .S_AXI_ARESETN        (rst_n)                  ,
    .S_AXI_ARREADY        (s_axi_arready)          ,
    .S_AXI_ARADDR         (s_axi_araddr)           ,
    .S_AXI_ARVALID        (s_axi_arvalid)          ,
    .S_AXI_ARLEN          (s_axi_arlen)            ,
    .S_AXI_ARSIZE         (s_axi_arsize)           ,
    .S_AXI_ARID           (s_axi_arid)             ,
    .S_AXI_ARBURST        (s_axi_arburst)          ,
    .S_AXI_ARLOCK         (s_axi_arlock)           ,
    .S_AXI_ARCACHE        (s_axi_arcache)          ,
    .S_AXI_ARPROT         (s_axi_arprot)           ,
    .S_AXI_ARQOS          (s_axi_arqos)            ,
    .S_AXI_ARREGION       (s_axi_arregion)         ,
    .S_AXI_ARUSER         (s_axi_aruser)           ,
    .S_AXI_RREADY         (s_axi_rready)           ,
    .S_AXI_RVALID         (s_axi_rvalid)           ,
    .S_AXI_RDATA          (s_axi_rdata)            ,
    .S_AXI_RLAST          (s_axi_rlast)            ,
    .S_AXI_RUSER          (s_axi_ruser)            ,
    .S_AXI_RID            (s_axi_rid)              ,
    .S_AXI_RRESP          (s_axi_rresp)            ,
    .S_AXI_AWREADY        (s_axi_awready)          ,
    .S_AXI_AWADDR         (s_axi_awaddr)           ,
    .S_AXI_AWVALID        (s_axi_awvalid)          ,
    .S_AXI_AWLEN          (s_axi_awlen)            ,
    .S_AXI_AWSIZE         (s_axi_awsize)           ,
    .S_AXI_AWID           (s_axi_awid)             ,
    .S_AXI_AWBURST        (s_axi_awburst)          ,
    .S_AXI_AWLOCK         (s_axi_awlock)           ,
    .S_AXI_AWCACHE        (s_axi_awcache)          ,
    .S_AXI_AWPROT         (s_axi_awprot)           ,
    .S_AXI_AWQOS          (s_axi_awqos)            ,
    .S_AXI_AWREGION       (s_axi_awregion)         ,
    .S_AXI_AWUSER         (s_axi_awuser)           ,
    .S_AXI_WREADY         (s_axi_wready)           ,
    .S_AXI_WVALID         (s_axi_wvalid)           ,
    .S_AXI_WDATA          (s_axi_wdata)            ,
    .S_AXI_WSTRB          (s_axi_wstrb)            ,
    .S_AXI_WLAST          (s_axi_wlast)            ,
    .S_AXI_WUSER          (s_axi_wuser)            ,
    .S_AXI_BVALID         (s_axi_bvalid)           ,
    .S_AXI_BREADY         (s_axi_bready)           ,
    .S_AXI_BID            (s_axi_bid)              ,
    .S_AXI_BUSER          (s_axi_buser)            ,
    .S_AXI_BRESP          (s_axi_bresp)
);
// ----------------------------------------------------------------

// ----------------------------------------------------------------
// These FIFOs are used for elastic communication between the AXI slave and the NoC driver
// ----------------------------------------------------------------
fifo_v3 #(
    .FALL_THROUGH   (1'b0)              ,
    .DATA_WIDTH     (WR_FIFO_WIDTH)     ,
    .DEPTH          (WR_FIFO_DEPTH)
) write_fifo(
    .clk_i          (clk)               ,
    .rst_ni         (rst_n)             ,   // Asynchronous reset active low
    .flush_i        (1'b0)              ,
    .testmode_i     (1'b0)              ,
    .full_o         (s_wr_fifo_full)    ,
    .empty_o        (s_wr_fifo_empty)   ,
    .usage_o        ()                  ,
    .data_i         (s_wr_fifo_data_in) ,
    .push_i         (s_wr_fifo_wr_rq)   ,
    .data_o         (s_wr_fifo_data_out),
    .pop_i          (s_wr_fifo_rd_rq)
);

fifo_v3 #(
    .FALL_THROUGH   (1'b0)                   ,
    .DATA_WIDTH     (RD_ADDR_FIFO_WIDTH)     ,
    .DEPTH          (RD_ADDR_FIFO_DEPTH)
) read_addr_fifo(
    .clk_i          (clk)                    ,
    .rst_ni         (rst_n)                  ,
    .flush_i        (1'b0)                   ,
    .testmode_i     (1'b0)                   ,
    .full_o         (s_rd_addr_fifo_full)    ,
    .empty_o        (s_rd_addr_fifo_empty)   ,
    .usage_o        ()                       ,
    .data_i         (s_rd_addr_fifo_data_in) ,
    .push_i         (s_rd_addr_fifo_wr_rq)   ,
    .data_o         (s_rd_addr_fifo_data_out),
    .pop_i          (s_rd_addr_fifo_rd_rq)
);

fifo_v3 #(
    .FALL_THROUGH   (1'b0)                   ,
    .DATA_WIDTH     (RD_DATA_FIFO_WIDTH)     ,
    .DEPTH          (RD_DATA_FIFO_DEPTH)
) read_data_fifo(
    .clk_i          (clk)                    ,
    .rst_ni         (rst_n)                  ,
    .flush_i        (1'b0)                   ,
    .testmode_i     (1'b0)                   ,
    .full_o         (s_rd_data_fifo_full)    ,
    .empty_o        (s_rd_data_fifo_empty)   ,
    .usage_o        ()                       ,
    .data_i         (s_rd_data_fifo_data_in) ,
    .push_i         (s_rd_data_fifo_wr_rq)   ,
    .data_o         (s_rd_data_fifo_data_out),
    .pop_i          (s_rd_data_fifo_rd_rq)
);
// ----------------------------------------------------------------

// ----------------------------------------------------------------
// NoC driver -- initiates pmesh transactions
// ----------------------------------------------------------------
noc_driver
#(
    .BRIDGE_IN_FLIGHT_REQS        (BRIDGE_IN_FLIGHT_REQS),
    .BRIDGE_SUPPORT_NON_CACHEABLE (BRIDGE_SUPPORT_NON_CACHEABLE),
    .BRIDGE_TRAP_0BYTE_WRITES     (BRIDGE_TRAP_0BYTE_WRITES),
    .BRIDGE_UNROLLER_FIFO_FT      (BRIDGE_UNROLLER_FIFO_FT),
    .SYS_ADDR_SIZE                (SYS_ADDR_SIZE),
    .N_IO_SECTIONS                (N_IO_SECTIONS),
    .INIT_IO_BASE                 (INIT_IO_BASE),
    .INIT_IO_END                  (INIT_IO_END)
)
noc_driver_inst
(
    .clk                 (clk)                     ,
    .rst_n               (rst_n)                   ,
    .internal_rst_n      (internal_rst_n)          ,
    .aif_rd_addr_data    (s_rd_addr_fifo_data_out) ,
    .aif_rd_addr_rd_rq   (s_rd_addr_fifo_rd_rq)    ,
    .aif_rd_addr_emtpy   (s_rd_addr_fifo_empty)    ,
    .aif_rd_data_data    (s_rd_data_fifo_data_in)  ,
    .aif_rd_data_wr_rq   (s_rd_data_fifo_wr_rq)    ,
    .aif_rd_data_full    (s_rd_data_fifo_full)     ,
    .aif_wr_trans_data   (s_wr_fifo_data_out)      ,
    .aif_wr_trans_rd_rq  (s_wr_fifo_rd_rq)         ,
    .aif_wr_trans_empty  (s_wr_fifo_empty)         ,
    .aif_wr_ack          (s_noc_wack)              ,
    .noc1_valid_out      (noc1_valid_out)          ,
    .noc1_data_out       (noc1_data_out)           ,
    .noc1_ready_in       (noc1_ready_in)           ,
    .noc2_valid_in       (noc2_valid_in)           ,
    .noc2_data_in        (noc2_data_in)            ,
    .noc2_ready_out      (noc2_ready_out)          ,
    .src_chipid          (src_chipid)              ,
    .src_xpos            (src_xpos)                ,
    .src_ypos            (src_ypos)                ,
    .src_fbits           (src_fbits)               ,
    .dest_chipid         (dest_chipid)             ,
    .dest_fbits          (dest_fbits)              ,
    .noc_num_tiles       (noc_num_tiles)           ,
    .noc_home_alloc_meth (noc_home_alloc_meth)     
);
// ----------------------------------------------------------------
endmodule
