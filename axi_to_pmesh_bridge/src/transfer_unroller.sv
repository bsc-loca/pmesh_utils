/* ------------------------------------------------------------------
 * Organization   : Barcelona Supercomputing Center
 * File           : transfer_unroller.sv
 * Description    : component of the noc_driver module, part of
 *                  the axi_to_pmesh_bridge, that receives AXI
 *                  requests and generates OpenPiton PMESH (NoC) requests
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
 * - the bridge never applies backpressure to PMESH:
 *     + it only issues a new request when it has the free resources to accept the response
 *     + parameter BRIDGE_IN_FLIGHT_REQS must be adjusted carefuly
 * - Need to comply with PMESH transfers restrictions:
 *     + atomic transfers have width limitations.
 *     + non-cacheable stores have width limitations.
 * - activating the transfer unroller FIFO fall-through path improves performance but may
 *      complicate achieving timing closure.
 * - AXI 0-byte write requests are legal, they are bridged as PMESH 0-byte atomic SWAP operation.
 *      PMESH appears not to handle this type of operation correctly - may need to trap them.
 * ------------------------------------------------------------------
 * TODO:
 * - maybe support a better priority scheme
 * ------------------------------------------------------------------
 */

module transfer_unroller
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
  parameter logic [N_IO_SECTIONS-1:0][SYS_ADDR_SIZE-1:0] INIT_IO_END   = {SYS_ADDR_SIZE {1'b0}},

  // unrolled ID types
  parameter type UNROLLED_IDS_T  = logic,
  parameter type UNROLLED_IFID_T = logic,
  parameter type UNROLLED_MRID_T = logic
)
(
  input  logic               clk,
  input  logic               rst_n,

  // read transfers in the rd_addr FIFO
  input  aif_rd_addr_data_t  aif_rd_addr_data,
  output logic               aif_rd_addr_rd_rq,
  input  logic               aif_rd_addr_emtpy,

  // read responses are sent in the rd_data FIFO
  output aif_rd_data_data_t  aif_rd_data_data,
  output logic               aif_rd_data_wr_rq,
  input  logic               aif_rd_data_full,

  // write transfers in the wr_trans FIFO
  input  aif_wr_tran_data_t  aif_wr_trans_data,
  output logic               aif_wr_trans_rd_rq,
  input  logic               aif_wr_trans_empty,

  // write responses are sent directly - do not use a FIFO
  output logic               aif_wr_ack,

  input  logic               unrolled_req_rdy,
  output logic               unrolled_req_vld,
  output unrolled_req_t      unrolled_req,
  output UNROLLED_IDS_T      unrolled_req_ids,

  //NOTE: the unroller is always ready to receive responses - no need for unrolled_rsp_rdy
  input  logic               unrolled_rsp_vld,
  input  unrolled_rsp_t      unrolled_rsp,
  input  UNROLLED_IFID_T     unrolled_rsp_ifid
);
  // ----------------------------------------------------------------
  // Address map support functions
  // this code is taken, with minor modifications,
  // from file vector_scalar_address_generation_unit.sv
  // authored by Juli Serra Balaguer - juli.serra@bsc.es (JS)
  // ----------------------------------------------------------------
  // determine if an address is cacheable or not
  function automatic logic range_check(input logic[SYS_ADDR_SIZE-1:0] start_region,
                                       input logic[SYS_ADDR_SIZE-1:0] end_region,
                                       input logic[SYS_ADDR_SIZE-1:0] address);
      return (address >= start_region) && (address < end_region);
  endfunction : range_check

  function automatic logic is_inside_IO_sections_escher (input logic[SYS_ADDR_SIZE-1:0] address);
      // if we don't specify any region we assume everything is accessible
      logic[N_IO_SECTIONS-1:0] pass;
      pass = '0;
      for (int unsigned k = 0; k < N_IO_SECTIONS; k++) begin : pass_gen
          pass[k] = range_check(INIT_IO_BASE[k], INIT_IO_END[k], address);
      end
      return |pass;
  endfunction : is_inside_IO_sections_escher
  // ----------------------------------------------------------------

  // ----------------------------------------------------------------
  // constants
  // ----------------------------------------------------------------
  localparam unsigned UNRL_IFID_BITS        = $bits (UNROLLED_IFID_T);
  localparam unsigned UNRL_MRID_BITS        = $bits (UNROLLED_MRID_T);

  localparam unsigned BRIDGE_IN_FLIGHT_BITS = UNRL_IFID_BITS + 1;  //NOTE: needs to represent BRIDGE_IN_FLIGHT_REQS

  localparam unsigned IN_FLIGHT_PTR_BITS    = UNRL_IFID_BITS;

  // each AXI-side write request may require several NoC-side micro-requests
  localparam unsigned MR_MAX_REQS           = (1 << UNRL_MRID_BITS);
  localparam unsigned MR_MAX_REQS_BITS      = UNRL_MRID_BITS + 1;  //NOTE: needs to represent MR_MAX_REQS

  localparam unsigned RSP_FIFO_WIDTH        = UNRL_RSP_DATA_BITS;
  localparam unsigned RSP_FIFO_DEPTH        = 1;  //NOTE: all responses fit in a single register

  localparam unsigned PRIO_WR               = 1'b0;
  localparam unsigned PRIO_RD               = 1'b1;

  localparam unsigned UNRL_REQ_DATA_BYTES   = UNRL_REQ_DATA_BITS / BITS_IN_BYTE;

  localparam unsigned NC_STORE_BYTES        = NC_STORE_BITS / BITS_IN_BYTE;

  // may need to partition non-cacheable stores into partial requests
  localparam unsigned WR_PART_NUM           = (BRIDGE_SUPPORT_NON_CACHEABLE & (AIF_DATA_BITS > NC_STORE_BITS) & (UNRL_REQ_DATA_BITS > NC_STORE_BITS)) ? (AIF_DATA_BITS / NC_STORE_BITS) : 1;
  localparam unsigned WR_PART_NUM_BITS      = (WR_PART_NUM > 1) ? $clog2 (WR_PART_NUM) : 1;
  // ----------------------------------------------------------------

  // ----------------------------------------------------------------
  // types
  // ----------------------------------------------------------------
  typedef logic    [BRIDGE_IN_FLIGHT_BITS - 1:0] in_flight_cnt_t;
  typedef logic       [IN_FLIGHT_PTR_BITS - 1:0] in_flight_ptr_t;

  typedef logic         [MR_MAX_REQS_BITS - 1:0] wr_mr_cnt_t;
  typedef logic         [WR_PART_NUM_BITS - 1:0] wr_part_cnt_t;
  typedef logic            [NC_STORE_BITS - 1:0] wr_part_data_t;
  typedef logic           [NC_STORE_BYTES - 1:0] wr_part_wstrb_t;

  // task state
  typedef enum logic {
    TASK_IDLE,  // no request to service or requester not busy
    TASK_PARK   // waiting for a requester handshake to complete
  } task_state_t;
  // ----------------------------------------------------------------

  // ----------------------------------------------------------------
  // transfer unroller
  // ----------------------------------------------------------------
  task_state_t                        unrl_state, unrl_state_nxt;

  logic                               top_prio;
  logic                               sel_rd, sel_rd_prev;  // select read request
  logic                               sel_wr, sel_wr_prev;  // select write request

  logic [BRIDGE_IN_FLIGHT_REQS - 1:0] in_flt_rden;  // indicates in-flight is a read ==1 / write == 0 request
  in_flight_cnt_t                     in_flt_cnt;
  logic                               in_flt_full;
  logic                               in_flt_new;
  logic                               in_flt_done;  // indicates that received in-flight has completed
  in_flight_ptr_t                     in_flt_head;  // indicates ID of next request to be ack'd to AXI
  in_flight_ptr_t                     in_flt_tail;  // indicates next in-flight ID
  logic [BRIDGE_IN_FLIGHT_REQS - 1:0] in_flt_issd;  // indicates in-flight has issued last micro-request

  unrolled_req_t                      rd_req;
  UNROLLED_IDS_T                      rd_req_ids;
  unrolled_req_t                      wr_req;
  UNROLLED_IDS_T                      wr_req_ids;
  logic                               wr_done;      // all write micro-operations have been issued

  logic                               req_issd;
  logic                               req_busy;
  logic                               req_prkd;
  logic                               req_0byte;
  logic                               req_0byte_fall_through;
  unrolled_size_t                     req_size_rd;

  logic                               is_non_cache;

  logic                               writing;

  wrt_unr_tran_data_t                 wr_trans_data;
  logic                               wr_mr_stall;
  logic                               wr_mr_vld;
  unrolled_req_data_t                 wr_mr_data;
  unrolled_addr_t                     wr_mr_addr;
  unrolled_ofst_t                     wr_mr_ofst;
  unrolled_size_t                     wr_mr_size;
  UNROLLED_MRID_T                     wr_mr_id;
  logic                               wr_mr_last;
  logic [BRIDGE_IN_FLIGHT_REQS - 1:0] wr_mr_req_vld;

  logic                               wr_part_0byte;
  logic                               wr_part_last;

  wr_mr_cnt_t                         wr_mr_inflt_cnt[BRIDGE_IN_FLIGHT_REQS - 1:0];

  logic [BRIDGE_IN_FLIGHT_REQS - 1:0] wr_mr_rsp_vld;

  logic                               rsp_data_vld;

  in_flight_ptr_t                     rsp_ifid;

  unrolled_rsp_data_t                 rsp_fifo_data;
  logic [BRIDGE_IN_FLIGHT_REQS - 1:0] rsp_fifo_data_push;

  unrolled_rsp_data_t                 aif_fifo_data[BRIDGE_IN_FLIGHT_REQS - 1:0];
  logic [BRIDGE_IN_FLIGHT_REQS - 1:0] aif_fifo_data_pop;
  logic [BRIDGE_IN_FLIGHT_REQS - 1:0] aif_fifo_data_empty;

  // ----------------------------------------------------------------
  // NoC1 request status
  // ----------------------------------------------------------------
  // noc_requester status
  always_comb begin
    req_busy = (unrolled_req_vld && !unrolled_req_rdy);
  end

  // need to park requests if requester is not ready!
  always_comb begin
    req_prkd = (unrl_state == TASK_PARK);
  end

  // ----------------------------------------------------------------
  // check transfer cacheability
  // ----------------------------------------------------------------
  // check both request cacheability and address map cacheability
  generate
    if (BRIDGE_SUPPORT_NON_CACHEABLE) begin : non_cacheable_support_gen
      aif_addr_t req_addr;
      logic      req_non_cache;

      // use provided address and AXI signals
      always_comb begin
        req_addr      = sel_rd ? aif_rd_addr_data.addr      : aif_wr_trans_data.addr;
        req_non_cache = sel_rd ? aif_rd_addr_data.non_cache : aif_wr_trans_data.non_cache;
      end

      always_comb begin
        is_non_cache = req_non_cache || is_inside_IO_sections_escher (req_addr);
      end
    end else begin : no_non_cacheable_support_gen
      always_comb begin
        is_non_cache = 0;
      end
    end
  endgenerate
  // ----------------------------------------------------------------

  // convert AXI-encoded size to bytes
  always_comb begin
    req_size_rd = (1 << aif_rd_addr_data.size);
  end

   // if needed, identify AXI 0-byte write requests
  //NOTE: AXI 0-byte write requests are legal, they are bridged as PMESH 0-byte atomic SWAP operation.
  //      PMESH appears not to handle this type of operation correctly
  //      may need to trap them and shortcut them to the correct FIFO
  generate
    if (BRIDGE_TRAP_0BYTE_WRITES) begin : trap_0byte_writes
      always_comb begin
        req_0byte  = (sel_wr && (aif_wr_trans_data.wstrb == 0));
      end
    end else begin : no_trap_0byte_writes
      always_comb begin
        req_0byte  = 0;
      end
    end
  endgenerate

  // writes may take several cycles - keep read/write selection constant
  always_ff @(posedge clk or negedge rst_n) begin
    if (rst_n == 0) begin
        writing <= 1'b0;
    end else begin
      if (wr_done) begin
        writing <= 1'b0;
      end else if (sel_wr) begin
        writing <= 1'b1;
      end
    end
  end
  // ----------------------------------------------------------------

  // ----------------------------------------------------------------
  // arbitrate between read and write requests
  //NOTE: a rotating priority is used: last operation issued gets low priority
  // ----------------------------------------------------------------
  // select top priority for next request
  always_ff @(posedge clk or negedge rst_n) begin
    if (rst_n == 0) begin
        top_prio <= PRIO_WR;
    end else begin
      if (req_issd) begin
        top_prio <= (sel_rd ? PRIO_WR : PRIO_RD);
      end
    end
  end

  // select read request
  always_comb begin
    // do not select if request already in flight
    if (in_flt_full) begin
      sel_rd = 1'b0;
    end else begin
      if (!req_prkd && !writing) begin
        // change selection only if requester not busy!
        sel_rd = (!aif_rd_addr_emtpy &&
                  ((top_prio == PRIO_RD) || aif_wr_trans_empty)
                 );
      end else begin
        sel_rd = sel_rd_prev;
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (rst_n == 0) begin
      sel_rd_prev <= 1'b0;
    end else begin
      sel_rd_prev <= sel_rd;  // remember previous selection
    end
  end

  // select write request
  always_comb begin
    // do not select if previous request already in flight
    if (in_flt_full) begin
      sel_wr = 1'b0;
    end else begin
      if (!req_prkd && !writing) begin
        // change selection only if requester not busy!
        sel_wr = (!aif_wr_trans_empty &&
                  ((top_prio == PRIO_WR) || aif_rd_addr_emtpy)
                 );
      end else begin
        sel_wr = sel_wr_prev;
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (rst_n == 0) begin
      sel_wr_prev <= 1'b0;
    end else begin
      sel_wr_prev <= sel_wr;  // remember previous selection
    end
  end
  // ----------------------------------------------------------------

  // ----------------------------------------------------------------
  // prepare read requests
  // ----------------------------------------------------------------
  always_comb begin
    rd_req.rden = 1'b1;
    rd_req.addr = unrolled_addr_t'(aif_rd_addr_data.addr);
    rd_req.size = req_size_rd;

    rd_req_ids.ifid = in_flt_tail;

    // read operations do not have micro-requests
    rd_req_ids.mrid = {UNRL_MRID_BITS {1'b0}};

    //NOTE: unnecessary but avoids linting error without adding any logic!
    rd_req.ofst = wr_mr_ofst;
    rd_req.data = wr_mr_data;

    rd_req.non_cache = is_non_cache;
  end

  // complete AIF-side read request handshake
  always_comb begin
    aif_rd_addr_rd_rq = (sel_rd && !req_busy);
  end
  // ----------------------------------------------------------------

  // ----------------------------------------------------------------
  // prepare write requests
  // ----------------------------------------------------------------
  // may need to partition non-cacheable stores into partial requests
  generate
    if (WR_PART_NUM > 1) begin : nc_part_support_gen
      wr_part_cnt_t   wr_part_cnt;
      aif_addr_t      wr_part_addr;
      wr_part_data_t  wr_part_data;
      wr_part_wstrb_t wr_part_wstrb;

      logic           part_0byte;

      unrolled_size_t req_size_wr;

      if (BRIDGE_TRAP_0BYTE_WRITES) begin : trap_0byte_parts
        always_comb begin
          part_0byte = (wr_part_wstrb == 0);
        end
      end else begin : no_trap_0byte_parts
        always_comb begin
          part_0byte = 0;
        end
      end

      // keep track of the partial transaction being handled
      always_ff @(posedge clk or negedge rst_n) begin
        if (rst_n == 0) begin
          wr_part_cnt <= 0;
        end else begin
          if (wr_mr_last || wr_part_0byte) begin
            if (wr_part_last) begin
              wr_part_cnt <= 0;
            end else begin
              wr_part_cnt <= wr_part_cnt + 1;
            end
          end
        end
      end

      // send the correct transfer information
      always_comb begin
        logic  wr_part_cont;

        // convert AXI-encoded size to bytes
        req_size_wr = (1 << aif_wr_trans_data.size);

        wr_part_addr  = aif_wr_trans_data.addr + (wr_part_cnt * NC_STORE_BYTES);
        wr_part_data  = aif_wr_trans_data.data[(wr_part_cnt * NC_STORE_BITS) +: NC_STORE_BITS];
        wr_part_wstrb = aif_wr_trans_data.wstrb[(wr_part_cnt * NC_STORE_BYTES) +: NC_STORE_BYTES];

        // check if need to continue (remaining write strobes are not zero)
        wr_part_cont  = |(aif_wr_trans_data.wstrb >> ((wr_part_cnt + 1) * NC_STORE_BYTES));

        if (sel_wr && is_non_cache && ((req_size_wr * BITS_IN_BYTE) > NC_STORE_BITS) && !req_0byte) begin
          // need to send partition data only
          wr_trans_data.addr  = wr_part_addr;
          wr_trans_data.data  = {{(UNRL_REQ_DATA_BITS - NC_STORE_BITS) {1'b0}}, wr_part_data};
          wr_trans_data.wstrb = {{(UNRL_REQ_DATA_BYTES - NC_STORE_BYTES) {1'b0}}, wr_part_wstrb};

          wr_part_0byte = part_0byte;
          wr_part_last  = (wr_part_cnt == (WR_PART_NUM - 1)) || !wr_part_cont;
        end else begin
          // no need to partition - pass input straight through
          wr_trans_data.addr  = aif_wr_trans_data.addr;
          wr_trans_data.data  = aif_wr_trans_data.data;
          wr_trans_data.wstrb = aif_wr_trans_data.wstrb;

          // indicate last partition
          wr_part_0byte = 1'b0;
          wr_part_last  = 1'b1;
        end
      end
    end else begin : no_nc_part_support_gen
      always_comb begin
        // no need to partition - pass input straight through
        wr_trans_data.addr  = aif_wr_trans_data.addr;
        wr_trans_data.data  = aif_wr_trans_data.data;
        wr_trans_data.wstrb = aif_wr_trans_data.wstrb;

        // indicate last partition
        wr_part_0byte = 1'b0;
        wr_part_last  = 1'b1;
      end
    end
  endgenerate

  // generate data, address and size for each micro-request
    write_unroller
    #(
      .UNROLLED_MRID_T (UNROLLED_MRID_T)
    )
    write_unroller_inst (
      .rst_n           (rst_n),
      .clk             (clk),
      .sel_wr          (sel_wr),
      .req_busy        (req_busy),
      .wr_trans        (wr_trans_data),
      .wr_part_last    (wr_part_last),
      .mr_stall        (wr_mr_stall),
      .mr_vld          (wr_mr_vld),
      .mr_data         (wr_mr_data),
      .mr_addr         (wr_mr_addr),
      .mr_ofst         (wr_mr_ofst),
      .mr_size         (wr_mr_size),
      .mr_id           (wr_mr_id),
      .mr_last         (wr_mr_last)
    );

  // stall micro-request if MR_MAX_REQS micro-requests are in flight or
  // micro-request is a 0-byte store partition
  always_comb begin
    wr_mr_stall = ((wr_mr_inflt_cnt[in_flt_tail] == MR_MAX_REQS) && !wr_mr_rsp_vld[in_flt_tail]) || wr_part_0byte;
  end

  // generate the actual micro-request
  always_comb begin
    wr_req.rden = 1'b0;
    wr_req.addr = wr_mr_addr;
    wr_req.ofst = wr_mr_ofst;
    wr_req.size = wr_mr_size;

    wr_req_ids.ifid = in_flt_tail;
    wr_req_ids.mrid = wr_mr_id;

    wr_req.data = wr_mr_data;

    wr_req.non_cache = is_non_cache;
  end

  // check if the whole write operation is complete - last micro-operation of last partition
  always_comb begin
    wr_done = (wr_mr_last && wr_part_last);
  end

  // complete the AIF-side write request handshake after all micro-requests have completed
  always_comb begin
    aif_wr_trans_rd_rq = wr_done;
  end
  // ----------------------------------------------------------------

  // ----------------------------------------------------------------
  // generate requests
  // ----------------------------------------------------------------
  //NOTE: do not issue 0-byte write requests - deal with them internally!
  always_comb begin
    unrolled_req     = (sel_rd ? rd_req : wr_req);
    unrolled_req_ids = (sel_rd ? rd_req_ids : wr_req_ids);
    unrolled_req_vld = (sel_rd || (sel_wr && !wr_mr_stall && !req_0byte));
  end
  // ----------------------------------------------------------------

  // ----------------------------------------------------------------
  // may need to park (stall) request if requester is busy
  // ----------------------------------------------------------------
  always_comb begin
    case (unrl_state)
      TASK_PARK: begin
        if (!req_busy) begin
          unrl_state_nxt = TASK_IDLE;
        end else begin
          unrl_state_nxt = TASK_PARK;
        end
      end

      default: begin  //NOTE: TASK_IDLE
        if (req_busy) begin
          unrl_state_nxt = TASK_PARK;
        end else begin
          unrl_state_nxt = TASK_IDLE;
        end
      end
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (rst_n == 0) begin
      unrl_state <= TASK_IDLE;
    end else begin
      unrl_state <= unrl_state_nxt;
    end
  end
  // ----------------------------------------------------------------

  // ----------------------------------------------------------------
  // keep track of number of requests in flight
  // ----------------------------------------------------------------
  always_comb begin
    //NOTE: an in-flight write request can have several micro-requests
    in_flt_new = (!req_busy && (sel_rd || sel_wr));
  end

  // in-flight operation is only one after data/ack sent to AXI side
  always_comb begin
    in_flt_done = aif_fifo_data_pop[in_flt_head];
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (rst_n == 0) begin
      in_flt_cnt <= 0;
    end else begin
      case ({req_issd, in_flt_done})
        2'b01   : in_flt_cnt <= in_flt_cnt - 1;
        2'b10   : in_flt_cnt <= in_flt_cnt + 1;
        default : in_flt_cnt <= in_flt_cnt;  // both or none active!
      endcase
    end
  end

  always_comb begin
    in_flt_full = (in_flt_cnt == BRIDGE_IN_FLIGHT_REQS);
  end

  // request is read == 1 / write == 0
  always_ff @(posedge clk or negedge rst_n) begin
    if (rst_n == 0) begin
      in_flt_rden <= {BRIDGE_IN_FLIGHT_REQS {1'b0}};  //NOTE: not needed but avoids a linting warning!
    end else begin
      if (in_flt_new) begin
        in_flt_rden[in_flt_tail] <= sel_rd;
      end
    end
  end

  always_comb begin
    //NOTE: an in-flight write request can have several micro-requests
    req_issd = (!req_busy && (sel_rd || wr_done));
  end

  // request has issued last micro-request
  always_ff @(posedge clk or negedge rst_n) begin
    if (rst_n == 0) begin
      in_flt_issd <= {BRIDGE_IN_FLIGHT_REQS {1'b0}};
    end else begin
      if (req_issd) begin
        in_flt_issd[in_flt_tail] <= 1'b1;
      end

      if (in_flt_done) begin
        in_flt_issd[in_flt_head] <= 1'b0;
      end
    end
  end

  // head = ID of oldest in-flight request
  always_ff @(posedge clk or negedge rst_n) begin
    if (rst_n == 0) begin
      in_flt_head <= 0;
    end else begin
      if (in_flt_done) begin
        if (in_flt_head == (BRIDGE_IN_FLIGHT_REQS - 1)) begin
          in_flt_head <= 0;
        end else begin
          in_flt_head <= in_flt_head + 1;
        end
      end
    end
  end

  // tail = ID of youngest in-flight request
  always_ff @(posedge clk or negedge rst_n) begin
    if (rst_n == 0) begin
      in_flt_tail <= 0;
    end else begin
      if (req_issd) begin
        if (in_flt_tail == (BRIDGE_IN_FLIGHT_REQS - 1)) begin
          in_flt_tail <= 0;
        end else begin
          in_flt_tail <= in_flt_tail + 1;
        end
      end
    end
  end
  // ----------------------------------------------------------------

  // ----------------------------------------------------------------
  // manage responses
  // ----------------------------------------------------------------
  always_comb begin
    rsp_ifid = unrolled_rsp_ifid;
  end

  // store all read responses but only the last write micro-request response
  //NOTE: indicate valid if wr_mr_inflt_cnt is about to go to zero!
  always_comb begin
    rsp_data_vld = unrolled_rsp_vld &&
                   (in_flt_rden[rsp_ifid] ||
                    (in_flt_issd[rsp_ifid] && (wr_mr_inflt_cnt[rsp_ifid] == 1))
                   );
  end

  // process response - store in FIFO
  always_comb begin
    rsp_fifo_data = unrolled_rsp.data;
  end

  // instantiate enough resources to accept all in-flight request without putting backpressure on PMESH
  genvar c;
  for (c = 0; c < BRIDGE_IN_FLIGHT_REQS; c++) begin : rsp_fifos_gen
    // generate flags to indicate valid issued micro-request
    always_comb begin
      wr_mr_req_vld[c] = ((wr_req_ids.ifid == c) && wr_mr_vld && !req_0byte);
    end

    // generate flags to indicate valid received micro-response
    always_comb begin
      wr_mr_rsp_vld[c] = ((rsp_ifid == c) && !in_flt_rden[c] && unrolled_rsp_vld);
    end

    // these counters keep track of the number of outstanding micro-requests for very every in-flight write
    //NOTE: count up with micro-request sent and down with micro-response received
    always_ff @(posedge clk or negedge rst_n) begin
      if (rst_n == 0) begin
        wr_mr_inflt_cnt[c] <= 0;
      end else begin
        case ({wr_mr_req_vld[c], wr_mr_rsp_vld[c]})
          2'b01   : wr_mr_inflt_cnt[c] <= wr_mr_inflt_cnt[c] - 1;
          2'b10   : wr_mr_inflt_cnt[c] <= wr_mr_inflt_cnt[c] + 1;
          default : wr_mr_inflt_cnt[c] <= wr_mr_inflt_cnt[c];
        endcase
      end
    end

    // push store response into correct FIFO - according to in-flight ID
    //NOTE: a NoC response and a 0-byte request cannot target the same FIFO
    always_comb begin
      rsp_fifo_data_push[c] = ((rsp_data_vld && (rsp_ifid == c)) || (req_0byte && (in_flt_tail == c)));
    end

    // need to store response data given that it may come out-of-order!
    //NOTE: FIFO FALL_THROUGH provides input data on the output in the same clock cycle - if empty
    fifo_v3 #(
        .FALL_THROUGH   (BRIDGE_UNROLLER_FIFO_FT),
        .DATA_WIDTH     (RSP_FIFO_WIDTH),
        .DEPTH          (RSP_FIFO_DEPTH)
    ) write_fifo(
        .clk_i          (clk),
        .rst_ni         (rst_n),
        .flush_i        (1'b0),
        .testmode_i     (1'b0),
        .full_o         (),
        .empty_o        (aif_fifo_data_empty[c]),
        .usage_o        (),
        .data_i         (rsp_fifo_data),  //NOTE: broadcast data to all FIFOs
        .push_i         (rsp_fifo_data_push[c]),
        .data_o         (aif_fifo_data[c]),
        .pop_i          (aif_fifo_data_pop[c])
    );

    // pop response from 'head' FIFO - oldest request
    always_comb begin
      aif_fifo_data_pop[c] = ((in_flt_head == c) && !aif_fifo_data_empty[c] && (!in_flt_rden[c] || req_0byte_fall_through || !aif_rd_data_full));
    end
  end

  // treat a 0-byte request correctly if FIFO fall-through is activated
  //NOTE: in_flt_rden may be one cycle late in this case!
  generate
    if (BRIDGE_UNROLLER_FIFO_FT) begin
      always_comb begin
        req_0byte_fall_through = req_0byte && (in_flt_tail == in_flt_head);
      end
    end else begin
      always_comb begin
        req_0byte_fall_through = 0;
      end
    end
  endgenerate

  // read data comes from unrolled response
  always_comb begin
    aif_rd_data_data = aif_fifo_data[in_flt_head];
  end

  // send read data - only if read response
  always_comb begin
    aif_rd_data_wr_rq = (aif_fifo_data_pop[in_flt_head] && in_flt_rden[in_flt_head] && !req_0byte_fall_through);
  end

  // send write ack to AIF side - only if write response
  always_comb begin
    aif_wr_ack = (aif_fifo_data_pop[in_flt_head] && (!in_flt_rden[in_flt_head] || req_0byte_fall_through));
  end
  // ----------------------------------------------------------------
endmodule
