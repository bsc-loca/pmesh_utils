/* ------------------------------------------------------------------
 * Organization   : Barcelona Supercomputing Center
 * File           : axi_to_pmesh_bridge_pkg.sv
 * Description    : constants, type definitions and support functions
 *                  for the axi_to_pmesh_bridge,
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
 *  Revision   | Author                           | Description
 *  0.0.1      | Abbas Haghi - abbas.haghi@bsc.es | initial code version
 *             | lap - luis.plana@bsc.es          | initial code version
 * ------------------------------------------------------------------
 * TODO:
 * ------------------------------------------------------------------
 */

package axi_to_pmesh_bridge_pkg;
  `include "l2.tmp.h"
  `include "define.tmp.h"

  // convenient to document code and avoid hardcoded value
  localparam unsigned BITS_IN_BYTE = $bits (byte);

  // ----------------------------------------------------------------
  // System constants
  // ----------------------------------------------------------------
  // Pmesh NoC maximum parameter values - used to check validity of above parameters automatically!
  //FIXME: need to get these constants from OpenPiton!
  localparam unsigned CACHE_LINE_BITS_MAX = 512;  // cache lines have width limitations
  localparam unsigned ATOMIC_TRF_BITS_MAX = 128;  // atomic transfers have width limitations
  localparam unsigned NC_STORE_BITS_MAX   =  64;  // non-cacheable stores have width limitations

  // NoC reads can be as wide as a cache line
  //FIXME: should we get these constants from OpenPiton?
  localparam unsigned CACHE_LINE_BITS  = 512;
  localparam unsigned ATOMIC_TRF_BITS  = 128;
  localparam unsigned NC_STORE_BITS    =  64;

  // AXI slave currently needs to allocate resources for a minimum number of transactions in flight
  localparam unsigned BRIDGE_IN_FLIGHT_REQ_MIN = 4;
  // ----------------------------------------------------------------

  // ==== AXI Parameters =================================================
  localparam CACHEABLE_WIDTH       = 1;  // bits required to indicate cacheable/non-cacheable

  localparam AXI_DATA_WIDTH        = 128;
  localparam AXI_DATA_BYTES        = AXI_DATA_WIDTH / BITS_IN_BYTE;
  localparam LOG2_AXI_DATA_BYTES   = $clog2 (AXI_DATA_BYTES);
  localparam AXI_ADDR_WIDTH        = 40;
  localparam AXI_ID_WIDTH          = 6;
  localparam AXI_PROT_WIDTH        = 3;
  localparam AXI_QOS_WIDTH         = 4;
  localparam AXI_LEN_WIDTH         = 8;
  localparam AXI_CACHE_WIDTH       = 4;
  localparam AXI_BURST_WIDTH       = 2;
  localparam AXI_SIZE_WIDTH        = 3;
  localparam AXI_RESP_WIDTH        = 2;
  localparam AXI_USER_WIDTH        = 1;
  localparam AXI_WSTRB_WIDTH       = AXI_DATA_WIDTH / BITS_IN_BYTE;
  localparam AXI_REGION_WIDTH      = 4;

  // ==== AXI Slave - NOC Driver FIFO Interface Parameters ===============
  localparam RD_ADDR_FIFO_WIDTH    = AXI_ADDR_WIDTH + AXI_SIZE_WIDTH + CACHEABLE_WIDTH;
  localparam RD_DATA_FIFO_WIDTH    = AXI_DATA_WIDTH;
  localparam WR_FIFO_WIDTH         = AXI_ADDR_WIDTH + AXI_DATA_WIDTH + AXI_SIZE_WIDTH + AXI_WSTRB_WIDTH + CACHEABLE_WIDTH;
  localparam RD_ADDR_FIFO_DEPTH    = 8;
  localparam RD_DATA_FIFO_DEPTH    = 8;
  localparam WR_FIFO_DEPTH         = 8;   
  localparam RD_BUFFER_FIFO_WIDTH  = AXI_LEN_WIDTH + AXI_SIZE_WIDTH + AXI_ADDR_WIDTH;
  localparam RD_CNTR_FIFO_WIDTH    = AXI_ID_WIDTH + AXI_LEN_WIDTH;
  // =====================================================================    


  // ----------------------------------------------------------------
  // define AXI slave <-> noc driver FIFO types and constants
  // ----------------------------------------------------------------
  typedef logic  [AXI_ADDR_WIDTH - 1:0] aif_addr_t;
  typedef logic  [AXI_DATA_WIDTH - 1:0] aif_data_t;
  typedef logic  [AXI_SIZE_WIDTH - 1:0] aif_size_t;
  typedef logic [AXI_WSTRB_WIDTH - 1:0] aif_wstrb_t;

  typedef struct packed {
    aif_addr_t addr;
    aif_size_t size;
    logic      non_cache;
  } aif_rd_addr_data_t;

  typedef aif_data_t aif_rd_data_data_t;

  typedef struct packed {
    aif_addr_t  addr;
    aif_data_t  data;
    aif_size_t  size;
    aif_wstrb_t wstrb;
    logic       non_cache;
  } aif_wr_tran_data_t;
  // ----------------------------------------------------------------

  // ----------------------------------------------------------------
  // NoC constants
  //NOTE: these reflect OpenPiton MACROS defined in the included files
  // ----------------------------------------------------------------
  localparam unsigned PITON_NOC1_WIDTH          = `PITON_NOC1_WIDTH;
  localparam unsigned PITON_NOC2_WIDTH          = `PITON_NOC2_WIDTH;

  localparam unsigned NOC_ADDR_BITS             = `PHY_ADDR_WIDTH;
  localparam unsigned NOC1_FLIT_BITS            = PITON_NOC1_WIDTH;
  localparam unsigned NOC2_FLIT_BITS            = PITON_NOC2_WIDTH;

  localparam unsigned HOME_ID_WIDTH             = `HOME_ID_WIDTH;
  localparam unsigned HOME_ALLOC_METHOD_WIDTH   = `HOME_ALLOC_METHOD_WIDTH;

  localparam unsigned MSG_SRC_CHIPID_WIDTH      = `MSG_SRC_CHIPID_WIDTH;
  localparam unsigned MSG_SRC_X_WIDTH           = `MSG_SRC_X_WIDTH;
  localparam unsigned MSG_SRC_Y_WIDTH           = `MSG_SRC_Y_WIDTH;
  localparam unsigned MSG_SRC_FBITS_WIDTH       = `MSG_SRC_FBITS_WIDTH;
  localparam unsigned MSG_DST_CHIPID_WIDTH      = `MSG_DST_CHIPID_WIDTH;
  localparam unsigned MSG_DST_X_WIDTH           = `MSG_DST_X_WIDTH;
  localparam unsigned MSG_DST_Y_WIDTH           = `MSG_DST_Y_WIDTH;
  localparam unsigned MSG_DST_FBITS_WIDTH       = `MSG_DST_FBITS_WIDTH;

  //NOTE: assume that source coordinates have the same size as destination ones.
  localparam unsigned MSG_CHIPID_BITS           = MSG_DST_CHIPID_WIDTH;
  localparam unsigned MSG_COORD_BITS            = MSG_DST_X_WIDTH;
  localparam unsigned MSG_FBITS_BITS            = MSG_DST_FBITS_WIDTH;

  localparam unsigned MSG_FIELD_BITS            = `MSG_FLIT_WIDTH;
  localparam unsigned MSG_FIELD_BYTES           = (MSG_FIELD_BITS / BITS_IN_BYTE);
  localparam unsigned LOG2_MSG_FIELD_BYTES      = $clog2 (MSG_FIELD_BYTES);

  localparam unsigned MSG_MAX_DATA_BITS         = CACHE_LINE_BITS;
  localparam unsigned MSG_MAX_DATA_BYTES        = MSG_MAX_DATA_BITS / BITS_IN_BYTE;
  localparam unsigned MSG_DATA_SIZE_BITS        = $clog2 (MSG_MAX_DATA_BYTES) + 1;
  localparam unsigned MSG_MAX_PLD_FIELDS        = MSG_MAX_DATA_BITS / MSG_FIELD_BITS;
  localparam unsigned MSG_MAX_PLD_BITS          = $clog2 (MSG_MAX_PLD_FIELDS) + 1;

  localparam unsigned NOC1_FIELDS_PER_FLIT      = NOC1_FLIT_BITS / MSG_FIELD_BITS;
  localparam unsigned NOC2_FIELDS_PER_FLIT      = NOC2_FLIT_BITS / MSG_FIELD_BITS;

  localparam unsigned MSG_MAX_HDR_FIELDS        = 3;
  localparam unsigned MSG_MAX_DATA_FIELDS       = MSG_MAX_DATA_BITS / MSG_FIELD_BITS;
  localparam unsigned MSG_MAX_FIELDS            = MSG_MAX_HDR_FIELDS + MSG_MAX_DATA_FIELDS;
  localparam unsigned MSG_FIELD_CNT_BITS        = $clog2 (MSG_MAX_FIELDS);

  localparam unsigned MSG_MAX_FLITS             = MSG_MAX_FIELDS;  // maximises when one field per PMESH flit
  localparam unsigned MSG_FLIT_CNT_BITS         = $clog2 (MSG_MAX_FLITS);

  localparam unsigned MSG_HDR1_POS              = (0 * MSG_FIELD_BITS);
  localparam unsigned MSG_HDR2_POS              = (1 * MSG_FIELD_BITS);
  localparam unsigned MSG_HDR3_POS              = (2 * MSG_FIELD_BITS);

  localparam unsigned MSG_ADDR_BITS             = `MSG_ADDR_WIDTH;
  localparam unsigned MSG_TYPE_BITS             = `MSG_TYPE_WIDTH;
  localparam unsigned MSG_LEN_BITS              = `MSG_LENGTH_WIDTH;
  localparam unsigned MSG_MSHR_BITS             = `MSG_MSHRID_WIDTH;
  localparam unsigned MSG_OPT1_BITS             = `MSG_OPTIONS_1_WIDTH;
  localparam unsigned MSG_OPT2_BITS             = `MSG_OPTIONS_2_WIDTH;
  localparam unsigned MSG_OPT3_BITS             = `MSG_OPTIONS_3_WIDTH;

  localparam unsigned MSG_OPT2_SUBCACHE_BITS    = `MSG_SUBLINE_VECTOR_WIDTH;
  localparam unsigned MSG_OPT2_DATA_SIZE_BITS   = `MSG_DATA_SIZE_WIDTH;
  localparam unsigned MSG_OPT2_MSG_AMO_MASK0    = `MSG_AMO_MASK0_WIDTH;
  
  localparam unsigned MSG_OPT3_MSG_SDID         = `MSG_SDID_WIDTH;
  localparam unsigned MSG_OPT3_MSG_LSID         = `MSG_LSID_WIDTH;
  localparam unsigned MSG_OPT3_RSVD             = `MSG_OPTIONS_3_WIDTH - `MSG_SDID_WIDTH - `MSG_LSID_WIDTH -`MSG_AMO_MASK1_WIDTH;
  localparam unsigned MSG_OPT3_MSG_AMO_MASK1    = `MSG_AMO_MASK1_WIDTH;
 
  localparam unsigned MSG_TYPE_STORE_REQ        = `MSG_TYPE_STORE_REQ;
  localparam unsigned MSG_TYPE_NC_LOAD_REQ      = `MSG_TYPE_NC_LOAD_REQ;
  localparam unsigned MSG_TYPE_NC_STORE_REQ     = `MSG_TYPE_NC_STORE_REQ;
  localparam unsigned MSG_TYPE_LOAD_MEM         = `MSG_TYPE_LOAD_MEM;
  localparam unsigned MSG_TYPE_STORE_MEM        = `MSG_TYPE_STORE_MEM;
  localparam unsigned MSG_TYPE_LOAD_MEM_ACK     = `MSG_TYPE_LOAD_MEM_ACK;
  localparam unsigned MSG_TYPE_STORE_MEM_ACK    = `MSG_TYPE_STORE_MEM_ACK;
  localparam unsigned MSG_TYPE_NODATA_ACK       = `MSG_TYPE_NODATA_ACK;
  localparam unsigned MSG_TYPE_DATA_ACK         = `MSG_TYPE_DATA_ACK;
  localparam unsigned MSG_TYPE_LOAD_REQ         = `MSG_TYPE_LOAD_REQ;
  localparam unsigned MSG_TYPE_LOAD_NOSHARE_REQ = `MSG_TYPE_LOAD_NOSHARE_REQ;
  localparam unsigned MSG_TYPE_SWAPWB_REQ       = `MSG_TYPE_SWAPWB_REQ;

  localparam unsigned MSG_DATA_SIZE_0B          = `MSG_DATA_SIZE_0B;
  localparam unsigned MSG_DATA_SIZE_1B          = `MSG_DATA_SIZE_1B;
  localparam unsigned MSG_DATA_SIZE_2B          = `MSG_DATA_SIZE_2B;
  localparam unsigned MSG_DATA_SIZE_4B          = `MSG_DATA_SIZE_4B;
  localparam unsigned MSG_DATA_SIZE_8B          = `MSG_DATA_SIZE_8B;
  localparam unsigned MSG_DATA_SIZE_16B         = `MSG_DATA_SIZE_16B;
  localparam unsigned MSG_DATA_SIZE_32B         = `MSG_DATA_SIZE_32B;
  localparam unsigned MSG_DATA_SIZE_64B         = `MSG_DATA_SIZE_64B;
  // ----------------------------------------------------------------


  // ----------------------------------------------------------------
  // NoC types
  // ----------------------------------------------------------------
  typedef logic         [PITON_NOC1_WIDTH -1:0] noc1_data_t;
  typedef logic         [PITON_NOC2_WIDTH -1:0] noc2_data_t;
  typedef logic     [MSG_SRC_CHIPID_WIDTH -1:0] noc_src_chipid_t;
  typedef logic          [MSG_SRC_X_WIDTH -1:0] noc_src_x_t;
  typedef logic          [MSG_SRC_Y_WIDTH -1:0] noc_src_y_t;
  typedef logic      [MSG_SRC_FBITS_WIDTH -1:0] noc_src_fbits_t;
  typedef logic     [MSG_DST_CHIPID_WIDTH -1:0] noc_dst_chipid_t;
  typedef logic          [MSG_DST_X_WIDTH -1:0] noc_dst_x_t;
  typedef logic          [MSG_DST_Y_WIDTH -1:0] noc_dst_y_t;
  typedef logic      [MSG_DST_FBITS_WIDTH -1:0] noc_dst_fbits_t;
  typedef logic            [HOME_ID_WIDTH -1:0] noc_num_tiles_t;
  typedef logic  [HOME_ALLOC_METHOD_WIDTH -1:0] noc_home_alloc_meth_t;

  typedef logic           [NOC_ADDR_BITS - 1:0] noc_addr_t;
  typedef logic        [MSG_MAX_PLD_BITS - 1:0] hdr_pld_size_t;

  // NoC message types
  typedef logic           [MSG_ADDR_BITS - 1:0] msg_addr_t;
  typedef logic           [MSG_TYPE_BITS - 1:0] msg_type_t;
  typedef logic            [MSG_LEN_BITS - 1:0] msg_len_t;
  typedef logic         [MSG_CHIPID_BITS - 1:0] msg_chipid_t;
  typedef logic          [MSG_COORD_BITS - 1:0] msg_coord_t;
  typedef logic          [MSG_FBITS_BITS - 1:0] msg_fbits_t;
  typedef logic           [MSG_MSHR_BITS - 1:0] msg_mshr_t;
  typedef logic           [MSG_OPT1_BITS - 1:0] msg_opt1_t;
  typedef logic           [MSG_OPT2_BITS - 1:0] msg_opt2_t;
  typedef logic           [MSG_OPT3_BITS - 1:0] msg_opt3_t;
  typedef logic      [MSG_DATA_SIZE_BITS - 1:0] msg_data_size_t;

  typedef logic  [MSG_OPT2_SUBCACHE_BITS - 1:0] opt2_subcache_t;
  typedef logic [MSG_OPT2_DATA_SIZE_BITS - 1:0] opt2_data_size_t;
  typedef logic  [MSG_OPT2_MSG_AMO_MASK0 - 1:0] opt2_amo_mask0_t;

  typedef logic       [MSG_OPT3_MSG_SDID - 1:0] opt3_sdid_t;
  typedef logic       [MSG_OPT3_MSG_LSID - 1:0] opt3_lsid_t;
  typedef logic           [MSG_OPT3_RSVD - 1:0] opt3_rsrvd_t;
  typedef logic  [MSG_OPT3_MSG_AMO_MASK1 - 1:0] opt3_amo_mask1_t;

  // NoC header1
  typedef struct packed {
    msg_chipid_t chipid;
    msg_coord_t  xpos;
    msg_coord_t  ypos;
    msg_fbits_t  fbits;
    msg_len_t    message_length;
    msg_type_t   message_type;
    msg_mshr_t   mshr_tag;
    msg_opt1_t   reserved;  // options1
  } noc_hdr1_t;

  // NoC header 2
  //FIXME: amo_mask0 is an undocumented field
  typedef struct packed {
    msg_addr_t       addr;
    opt2_subcache_t  subcache_bit_vector;
    logic            icache_bit;
    opt2_data_size_t data_size;
    opt2_amo_mask0_t amo_mask0;
  } noc_hdr2_t;

  // NoC header 3
  //FIXME: amo_mask1 is an undocumented field
  typedef struct packed {
    msg_chipid_t     src_chipid;
    msg_coord_t      src_xpos;
    msg_coord_t      src_ypos;
    msg_fbits_t      src_fbits;
    opt3_sdid_t      sdid;
    opt3_lsid_t      lsid;
    opt3_rsrvd_t     rsrvd;
    opt3_amo_mask1_t amo_mask1;
  } noc_hdr3_t;
  // ----------------------------------------------------------------

  // ----------------------------------------------------------------
  // NoC support functions
  // ----------------------------------------------------------------
  localparam unsigned MAX_REQ_HDR_NUM = 3;
  localparam unsigned MAX_RSP_HDR_NUM = 1;
  localparam unsigned MAX_HDR_NUM     = (MAX_REQ_HDR_NUM > MAX_RSP_HDR_NUM) ? MAX_REQ_HDR_NUM : MAX_RSP_HDR_NUM;
  localparam unsigned MAX_HDR_BITS    = MAX_HDR_NUM * MSG_FIELD_BITS;

  typedef logic [$clog2 (MAX_HDR_BITS) - 1:0] hdr_bits_t;

  // header length from message type
  function automatic hdr_pld_size_t noc_hdr_len (msg_type_t op);
    case (op)
      MSG_TYPE_DATA_ACK           : return 1;
      MSG_TYPE_NODATA_ACK         : return 1;
      MSG_TYPE_LOAD_MEM_ACK       : return 1;
      MSG_TYPE_STORE_MEM_ACK      : return 1;
      MSG_TYPE_NC_LOAD_REQ        : return 3;
      MSG_TYPE_NC_STORE_REQ       : return 3;
      MSG_TYPE_LOAD_NOSHARE_REQ   : return 3;
      MSG_TYPE_SWAPWB_REQ         : return 3;
      MSG_TYPE_LOAD_MEM           : return 3;
      MSG_TYPE_STORE_MEM          : return 3;
      default                     : return 0;  //NOTE: should never happen
    endcase
  endfunction

  // header length from message type
  function automatic hdr_bits_t noc_hdr_bits (msg_type_t op);
    case (op)
      MSG_TYPE_DATA_ACK           : return 64;
      MSG_TYPE_NODATA_ACK         : return 64;
      MSG_TYPE_LOAD_MEM_ACK       : return 64;
      MSG_TYPE_STORE_MEM_ACK      : return 64;
      MSG_TYPE_NC_LOAD_REQ        : return 192;
      MSG_TYPE_NC_STORE_REQ       : return 192;
      MSG_TYPE_LOAD_NOSHARE_REQ   : return 192;
      MSG_TYPE_SWAPWB_REQ         : return 192;
      MSG_TYPE_LOAD_MEM           : return 192;
      MSG_TYPE_STORE_MEM          : return 192;
      default                     : return 0;  //NOTE: should never happen
    endcase
  endfunction

  // payload length from data size - in number of fields
  function automatic hdr_pld_size_t noc_pld_len (msg_data_size_t sz);
    automatic msg_data_size_t len;
    len = ((sz - 1) >> LOG2_MSG_FIELD_BYTES) + 1;
    return len[0 +: $bits (hdr_pld_size_t)];
  endfunction

  // message type from transfer read enable (rd/~wr)
  function automatic msg_type_t noc_req_type (logic rden, logic non_cacheable_addr);
    automatic msg_type_t msg;
    case ({rden, non_cacheable_addr})
      2'b00: msg = MSG_TYPE_SWAPWB_REQ;
      2'b01: msg = MSG_TYPE_NC_STORE_REQ;
      2'b10: msg = MSG_TYPE_LOAD_NOSHARE_REQ;
      2'b11: msg = MSG_TYPE_NC_LOAD_REQ;
    endcase

    return msg;
  endfunction

  // message response type from message type
  function automatic msg_type_t noc_req_rsp (msg_type_t op);
    case (op)
      MSG_TYPE_LOAD_NOSHARE_REQ   : return MSG_TYPE_DATA_ACK;
      MSG_TYPE_SWAPWB_REQ         : return MSG_TYPE_DATA_ACK;
      MSG_TYPE_NC_STORE_REQ       : return MSG_TYPE_NODATA_ACK;
      MSG_TYPE_NC_LOAD_REQ        : return MSG_TYPE_DATA_ACK;
      default                     : return MSG_TYPE_DATA_ACK;
    endcase
  endfunction

  // encode data size
  function automatic opt2_data_size_t msg_opts2_size (msg_data_size_t size);
    case (size)
      1       : return MSG_DATA_SIZE_1B;
      2       : return MSG_DATA_SIZE_2B;
      4       : return MSG_DATA_SIZE_4B;
      8       : return MSG_DATA_SIZE_8B;
      16      : return MSG_DATA_SIZE_16B;
      32      : return MSG_DATA_SIZE_32B;
      64      : return MSG_DATA_SIZE_64B;
      default : return MSG_DATA_SIZE_0B;
    endcase
  endfunction
  // ----------------------------------------------------------------

  // ----------------------------------------------------------------
  // unrolled transfers constants
  // ----------------------------------------------------------------
  localparam unsigned AIF_DATA_BITS        = $bits (aif_data_t);  //NOTE: unrolled transfer size is tied to the AXI interface!
  localparam unsigned AIF_WSTRB_BITS       = AIF_DATA_BITS / BITS_IN_BYTE;

  localparam unsigned UNRL_MAX_DATA_BITS   = CACHE_LINE_BITS;
  localparam unsigned UNRL_MAX_DATA_BYTES  = UNRL_MAX_DATA_BITS / BITS_IN_BYTE;
  localparam unsigned UNRL_SIZE_BITS       = $clog2 (UNRL_MAX_DATA_BYTES) + 1;

  //NOTE: requests only carry write data!
  localparam unsigned UNRL_REQ_DATA_BITS   = (AIF_DATA_BITS >= ATOMIC_TRF_BITS) ? ATOMIC_TRF_BITS : (AIF_DATA_BITS >= MSG_FIELD_BITS) ? AIF_DATA_BITS : MSG_FIELD_BITS;
  localparam unsigned UNRL_RSP_DATA_BITS   = (AIF_DATA_BITS >= MSG_FIELD_BITS) ? AIF_DATA_BITS : MSG_FIELD_BITS;
  localparam unsigned UNRL_ADDR_BITS       = MSG_ADDR_BITS;
  localparam unsigned UNRL_OFST_BITS       = $clog2 (UNRL_ADDR_BITS);
  localparam unsigned UNRL_IDS_BITS        = MSG_MSHR_BITS;  // unrolled IDs must fit in message MSHR field!

  // the message MSHR field is used to convey different types of information:
  // bits needed for non-cacheable load rebuild - noc_requests
  localparam unsigned LOG2_REQ_DATA_BYTES  = $clog2 (UNRL_REQ_DATA_BITS / BITS_IN_BYTE);
  localparam unsigned NCLD_BITS            = LOG2_REQ_DATA_BYTES - LOG2_MSG_FIELD_BYTES;
  // ----------------------------------------------------------------

  // ----------------------------------------------------------------
  // unrolled transfers types
  // ----------------------------------------------------------------
  typedef logic   [UNRL_REQ_DATA_BITS - 1:0] unrolled_req_data_t;
  typedef logic   [UNRL_RSP_DATA_BITS - 1:0] unrolled_rsp_data_t;
  typedef logic       [UNRL_ADDR_BITS - 1:0] unrolled_addr_t;
  typedef logic       [UNRL_OFST_BITS - 1:0] unrolled_ofst_t;
  typedef logic       [UNRL_SIZE_BITS - 1:0] unrolled_size_t;

  // unrolled transfer request
  typedef struct packed {
    logic                rden;  // read = 1 | write = 0
    unrolled_req_data_t  data;
    unrolled_addr_t      addr;
    unrolled_ofst_t      ofst;
    unrolled_size_t      size;  // transfer size in bytes
    logic                non_cache;
  } unrolled_req_t;

  // unrolled transfer response
  typedef struct packed {
    unrolled_rsp_data_t  data;
  } unrolled_rsp_t;

  // transfer information for write_unroller
  typedef struct packed {
    aif_addr_t  addr;
    aif_data_t  data;
    aif_wstrb_t wstrb;
  } wrt_unr_tran_data_t;
  // ----------------------------------------------------------------
endpackage
