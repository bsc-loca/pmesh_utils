/* ------------------------------------------------------------------
 * Organization   : Barcelona Supercomputing Center
 * File           : noc_driver.sv
 * Description    : component of the axi_to_pmesh_bridge that
 *                  handles OpenPiton PMESH (NoC) requests and responses
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
 *  Revision   | Author                    | Description
 *  0.0.1      | lap - luis.plana@bsc.es   | initial code version
 * ------------------------------------------------------------------
 * PARAMETERS:
 * BRIDGE_IN_FLIGHT_REQS        = number of in-flight requests managed by the bridge.
 * BRIDGE_TRAP_0BYTE_WRITES     = trap AXI 0-byte write requests and acknowledge them locally.
 * BRIDGE_UNROLLER_FIFO_FT      = activate transfer unroller FIFO fall-through path.
 * BRIDGE_SUPPORT_NON_CACHEABLE = support non-cacheable accesses through the bridge.
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
 * ------------------------------------------------------------------
 * TODO:
 * ------------------------------------------------------------------
 */

module noc_driver
  import axi_to_pmesh_bridge_pkg::*;
#(
  parameter unsigned BRIDGE_IN_FLIGHT_REQS        = 1,
  parameter unsigned BRIDGE_TRAP_0BYTE_WRITES     = 1,
  parameter unsigned BRIDGE_UNROLLER_FIFO_FT      = 1,
  parameter unsigned BRIDGE_SUPPORT_NON_CACHEABLE = 0,

  // IO addresses - non-cacheable
  parameter int unsigned                                 SYS_ADDR_SIZE = $bits (aif_addr_t),      //! system address size: max between Virtual Address size and Physical Address Size.
  parameter int unsigned                                 N_IO_SECTIONS =  1,
  parameter logic [N_IO_SECTIONS-1:0][SYS_ADDR_SIZE-1:0] INIT_IO_BASE  = {SYS_ADDR_SIZE {1'b0}},  // defaults to cacheable accesses
  parameter logic [N_IO_SECTIONS-1:0][SYS_ADDR_SIZE-1:0] INIT_IO_END   = {SYS_ADDR_SIZE {1'b0}}
)
(
  input  logic                 clk,
  input  logic                 rst_n,

  input  logic                 internal_rst_n,

  // AXI-side interface
  // read transfers in the rd_addr FIFO
  input  aif_rd_addr_data_t    aif_rd_addr_data,
  output logic                 aif_rd_addr_rd_rq,
  input  logic                 aif_rd_addr_emtpy,

  // read responses are sent in the rd_data FIFO
  output aif_rd_data_data_t    aif_rd_data_data,
  output logic                 aif_rd_data_wr_rq,
  input  logic                 aif_rd_data_full,

  // write transfers in the wr_trans FIFO
  input  aif_wr_tran_data_t    aif_wr_trans_data,
  output logic                 aif_wr_trans_rd_rq,
  input  logic                 aif_wr_trans_empty,

  // write responses are sent directly - do not use a FIFO
  output logic                 aif_wr_ack,

  //NoC Interface
  //from the bridge
  output logic                 noc1_valid_out,
  output noc1_data_t           noc1_data_out,
  input  logic                 noc1_ready_in,
  //to the bridge
  input  logic                 noc2_valid_in,
  input  noc2_data_t           noc2_data_in,
  output logic                 noc2_ready_out,

  //Source
  input  noc_src_chipid_t      src_chipid,
  input  noc_src_x_t           src_xpos,
  input  noc_src_y_t           src_ypos,
  input  noc_src_fbits_t       src_fbits,

  //Destination
  input  noc_dst_chipid_t      dest_chipid,
  input  noc_dst_fbits_t       dest_fbits,

  //number of tiles and home allocation method
  input  noc_num_tiles_t       noc_num_tiles,
  input  noc_home_alloc_meth_t noc_home_alloc_meth
);

  // ----------------------------------------------------------------
  // unrolled transfers constants and types
  // ----------------------------------------------------------------
  // bits needed for in-flight ID
  localparam unsigned UNRL_IFID_BITS = (BRIDGE_IN_FLIGHT_REQS > 1) ? $clog2 (BRIDGE_IN_FLIGHT_REQS) : 1;

  // bits left over for micro-request ID
  localparam unsigned UNRL_MRID_BITS = UNRL_IDS_BITS - UNRL_IFID_BITS;

  typedef logic  [UNRL_IFID_BITS - 1:0] unrolled_ifid_t;
  typedef logic  [UNRL_MRID_BITS - 1:0] unrolled_mrid_t;

  // unrolled IDS is a combination of in-flight ID and micro-request ID
  typedef struct packed {
    unrolled_mrid_t mrid;
    unrolled_ifid_t ifid;
  } unrolled_ids_t;
  // ----------------------------------------------------------------

  // ----------------------------------------------------------------
  // top-level signals
  // ----------------------------------------------------------------
  logic           unrolled_req_vld;
  logic           unrolled_req_rdy;
  unrolled_req_t  unrolled_req;
  unrolled_ids_t  unrolled_req_ids;

  logic           unrolled_rsp_vld;
  unrolled_rsp_t  unrolled_rsp;
  unrolled_ifid_t unrolled_rsp_ifid;
  // ----------------------------------------------------------------

  // ----------------------------------------------------------------
  // transfer unroller
  //NOTE: the unroller is always ready to receive responses - no need for unrolled_rsp_rdy
  // ----------------------------------------------------------------
  transfer_unroller 
  #(
    .BRIDGE_IN_FLIGHT_REQS        (BRIDGE_IN_FLIGHT_REQS),
    .BRIDGE_TRAP_0BYTE_WRITES     (BRIDGE_TRAP_0BYTE_WRITES),
    .BRIDGE_UNROLLER_FIFO_FT      (BRIDGE_UNROLLER_FIFO_FT),
    .BRIDGE_SUPPORT_NON_CACHEABLE (BRIDGE_SUPPORT_NON_CACHEABLE),
    .SYS_ADDR_SIZE                (SYS_ADDR_SIZE),
    .N_IO_SECTIONS                (N_IO_SECTIONS),
    .INIT_IO_BASE                 (INIT_IO_BASE),
    .INIT_IO_END                  (INIT_IO_END),
    .UNROLLED_IDS_T               (unrolled_ids_t),
    .UNROLLED_IFID_T              (unrolled_ifid_t),
    .UNROLLED_MRID_T              (unrolled_mrid_t)
  )
  transfer_unroller_inst (
    .clk                     (clk),
    .rst_n                   (rst_n),
    .aif_rd_addr_data        (aif_rd_addr_data),
    .aif_rd_addr_rd_rq       (aif_rd_addr_rd_rq),
    .aif_rd_addr_emtpy       (aif_rd_addr_emtpy),
    .aif_rd_data_data        (aif_rd_data_data),
    .aif_rd_data_wr_rq       (aif_rd_data_wr_rq),
    .aif_rd_data_full        (aif_rd_data_full),
    .aif_wr_trans_data       (aif_wr_trans_data),
    .aif_wr_trans_rd_rq      (aif_wr_trans_rd_rq),
    .aif_wr_trans_empty      (aif_wr_trans_empty),
    .aif_wr_ack              (aif_wr_ack),
    .unrolled_req_rdy        (unrolled_req_rdy),
    .unrolled_req_vld        (unrolled_req_vld),
    .unrolled_req            (unrolled_req),
    .unrolled_req_ids        (unrolled_req_ids),
    .unrolled_rsp_vld        (unrolled_rsp_vld),
    .unrolled_rsp            (unrolled_rsp),
    .unrolled_rsp_ifid       (unrolled_rsp_ifid)
  );
  // ----------------------------------------------------------------

  // ----------------------------------------------------------------
  // NoC request manager
  // ----------------------------------------------------------------
  noc_requests
  #(
    .UNROLLED_IDS_T          (unrolled_ids_t),
    .UNROLLED_MRID_T         (unrolled_mrid_t)
  )
  noc_requests_inst (
    .clk                     (clk),
    .rst_n                   (rst_n),
    .internal_rst_n          (internal_rst_n),
    .unrolled_req_rdy        (unrolled_req_rdy),
    .unrolled_req_vld        (unrolled_req_vld),
    .unrolled_req            (unrolled_req),
    .unrolled_req_ids        (unrolled_req_ids),
    .noc1_valid_out          (noc1_valid_out),
    .noc1_data_out           (noc1_data_out),
    .noc1_ready_in           (noc1_ready_in),
    .src_chipid              (src_chipid),
    .src_xpos                (src_xpos),
    .src_ypos                (src_ypos),
    .src_fbits               (src_fbits),
    .dest_chipid             (dest_chipid),
    .dest_fbits              (dest_fbits),
    .noc_num_tiles           (noc_num_tiles),
    .noc_home_alloc_meth     (noc_home_alloc_meth)
  );
  // ----------------------------------------------------------------

  // ----------------------------------------------------------------
  // NoC response manager
  //NOTE: the unroller is always ready to receive responses - no need for unrolled_rsp_rdy
  // ----------------------------------------------------------------
  noc_responses
  #(
    .UNROLLED_IDS_T          (unrolled_ids_t),
    .UNROLLED_IFID_T         (unrolled_ifid_t)
  )
  noc_responses_inst (
    .clk                     (clk),
    .rst_n                   (rst_n),
    .noc2_valid_in           (noc2_valid_in),
    .noc2_data_in            (noc2_data_in),
    .noc2_ready_out          (noc2_ready_out),
    .unrolled_rsp            (unrolled_rsp),
    .unrolled_rsp_ifid       (unrolled_rsp_ifid),
    .unrolled_rsp_vld        (unrolled_rsp_vld)
  );
  // ----------------------------------------------------------------
endmodule
