/* ------------------------------------------------------------------
 * Organization   : Barcelona Supercomputing Center
 * File           : noc_requests.sv
 * Description    : component of the noc_driver module, part
 *                  of the axi_to_pmesh_bridge, that handles
 *                  OpenPiton PMESH (NoC) requests
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
 *  0.0.1      | lap - luis.plana@bsc.es                | initial code version
 *  0.0.2      | Alireza Monemi - alireza.monemi@bsc.es | initial multi-flit support
 * ------------------------------------------------------------------
 * NOTES:
 * - PMESH messages are formed by (64-bit) FIELDS
 *     + a FIELD can contain a HEADER or DATA
 * - PMESH messages are split in FLITS for transmission
 *     + FLIT SIZE = NoC width
 *     + NoC1 and NoC2 can have different widths.
 * - PMESH components expect specific narrow data placement in message
 * ------------------------------------------------------------------
 * TODO:
 * ------------------------------------------------------------------
 */

module noc_requests
  import axi_to_pmesh_bridge_pkg::*;
#(
  // unrolled ID types
  parameter type UNROLLED_IDS_T  = logic,
  parameter type UNROLLED_MRID_T = logic
)
(
  input  logic                 clk,
  input  logic                 rst_n,

  input  logic                 internal_rst_n,

  output logic                 unrolled_req_rdy,
  input  logic                 unrolled_req_vld,
  input  unrolled_req_t        unrolled_req,
  input  UNROLLED_IDS_T        unrolled_req_ids,

  output logic                 noc1_valid_out,
  output noc1_data_t           noc1_data_out,
  input  logic                 noc1_ready_in,

  input  noc_src_chipid_t      src_chipid,
  input  noc_src_x_t           src_xpos,
  input  noc_src_x_t           src_ypos,
  input  noc_src_fbits_t       src_fbits,

  input  noc_dst_chipid_t      dest_chipid,
  input  noc_dst_fbits_t       dest_fbits,

  input  noc_num_tiles_t       noc_num_tiles,
  input  noc_home_alloc_meth_t noc_home_alloc_meth
);
  // ----------------------------------------------------------------
  // constants
  // ----------------------------------------------------------------
  localparam unsigned UNRL_REQ_DATA_BYTES    = UNRL_REQ_DATA_BITS / BITS_IN_BYTE;
  localparam unsigned UNRL_MRID_BITS         = $bits (UNROLLED_MRID_T);

  // maximum message length in bits
  localparam unsigned MSG_BITS               = (MAX_REQ_HDR_NUM * MSG_FIELD_BITS) + UNRL_REQ_DATA_BITS;

  // number of flits required to transmit a message
  //NOTE: the transmitted message has to be a whole number of flits - may need padding!
  localparam unsigned FLITS_PER_MSG          = ((MSG_BITS - 1) / NOC1_FLIT_BITS) + 1;

  // transmitted message length
  localparam unsigned MESSAGE_BITS           = FLITS_PER_MSG * NOC1_FLIT_BITS;
  localparam unsigned MSG_BITS_CNT_BITS      = $clog2 (MESSAGE_BITS - 1) + 1;
  localparam unsigned MESSAGE_FIELDS         = MESSAGE_BITS / MSG_FIELD_BITS;

  localparam unsigned LOG2_BYTE              = $clog2 (BITS_IN_BYTE);

  // need multi-flit support if longest possible message does not fit in a single NOC1 flit
  localparam unsigned REQ_MULTI_FLIT_SUPPORT = ((MAX_REQ_HDR_NUM + (UNRL_REQ_DATA_BYTES / MSG_FIELD_BYTES)) > NOC1_FIELDS_PER_FLIT);
  // ----------------------------------------------------------------

  // ----------------------------------------------------------------
  // NoC request types
  // ----------------------------------------------------------------
  typedef logic         [MESSAGE_BITS - 1:0] message_t;
  typedef logic       [MSG_FIELD_BITS - 1:0] msg_fld_data_t;
  typedef logic [(2 * MSG_FIELD_BITS) - 1:0] wide_data_t;

  typedef logic       [NOC1_FLIT_BITS - 1:0] flit_t;
  typedef logic    [MSG_FLIT_CNT_BITS - 1:0] flit_cnt_t;
  typedef logic    [MSG_BITS_CNT_BITS - 1:0] flit_ptr_t;

  typedef logic   [MSG_FIELD_CNT_BITS - 1:0] field_cnt_t;
  // ----------------------------------------------------------------

  // ----------------------------------------------------------------
  // NoC request manager
  // ----------------------------------------------------------------
  logic           noc_busy;

  message_t       message;

  msg_addr_t      msg_addr;

  unrolled_req_data_t replicated_data;
  unrolled_req_data_t reordered_data;

  noc_hdr1_t      hdr1;
  noc_hdr2_t      hdr2;
  noc_hdr3_t      hdr3;
  hdr_pld_size_t  hdr_len;
  hdr_pld_size_t  pld_len;
  hdr_pld_size_t  msg_len;

  msg_type_t      req_type;
  UNROLLED_IDS_T  req_mshr;

  noc_addr_t      noc_req_addr;

  msg_coord_t     dest_xpos;
  msg_coord_t     dest_ypos;

  // ----------------------------------------------------------------
  // destination coordinates calculation
  // ----------------------------------------------------------------
  // adapt address sizes
  //NOTE: this code avoids linting errors for any valid parameter settings
  always_comb begin
    // cast to equal size, pad with zeroes to larger size, truncate to smaller size
    logic [($bits(noc_addr_t) + $bits(unrolled_addr_t)) - 1:0] tmp_long_addr;

    tmp_long_addr = {{$bits(noc_addr_t) {1'b0}}, unrolled_req.addr};
    noc_req_addr  = noc_addr_t '(tmp_long_addr[$bits(noc_addr_t) - 1:0]);
  end

  addr_to_x_y addr_to_x_y_inst (
    .system_tile_count       (noc_num_tiles),
    .home_alloc_method       (noc_home_alloc_meth),
    .axi2noc_req_address_s0  (noc_req_addr),
    .lhid_s1_x               (dest_xpos),
    .lhid_s1_y               (dest_ypos)
  );
  // ----------------------------------------------------------------

  // determine request type, header and payload lengths
  always_comb begin
    req_type = noc_req_type (unrolled_req.rden, unrolled_req.non_cache);

    // header and payload lenghts - in terms of fields, not flits!
    hdr_len = noc_hdr_len (req_type);

    if (unrolled_req.rden) begin
      pld_len = 0;  // read requests do not carry a payload
    end else begin
      pld_len = noc_pld_len (unrolled_req.size);
    end

    //NOTE: PMESH message length does not count header1!
    msg_len = hdr_len + pld_len - 1;
  end

  // generate message MSHR_TAG - build from IFID and MRID
  always_comb begin
    req_mshr.ifid = unrolled_req_ids.ifid;
  end

  //NOTE: PMESH may trim size/offset information when transporting narrow loads
  //      use MRID field to convey narrow load response rebuild information
  generate
    if (LOG2_REQ_DATA_BYTES > LOG2_MSG_FIELD_BYTES) begin : mrid_gen
      always_comb begin
        if (unrolled_req.rden) begin
          req_mshr.mrid = {{(UNRL_MRID_BITS - (LOG2_REQ_DATA_BYTES - LOG2_MSG_FIELD_BYTES)) {1'b0}},
                             unrolled_req.addr[LOG2_MSG_FIELD_BYTES +: ((LOG2_REQ_DATA_BYTES - LOG2_MSG_FIELD_BYTES))]};
        end else begin
          req_mshr.mrid = unrolled_req_ids.mrid;
        end
      end
    end else begin : no_mrid_gen
      always_comb begin
        req_mshr.mrid = unrolled_req_ids.mrid;
      end
    end
  endgenerate

  // encode header1
  always_comb begin
    hdr1 = {$bits (noc_hdr1_t) {1'b0}};  // avoid unassigned bits

    hdr1.chipid         = dest_chipid;
    hdr1.xpos           = dest_xpos;
    hdr1.ypos           = dest_ypos;
    hdr1.fbits          = dest_fbits;
    hdr1.message_length = msg_len;
    hdr1.message_type   = req_type;
    hdr1.mshr_tag       = msg_mshr_t'(req_mshr);
  end

  // adapt request and NoC address sizes
  //NOTE: this mechanism avoids linting errors/warnings in all parameter settings
  generate
    if ($bits(msg_addr_t) > $bits(unrolled_addr_t)) begin : msg_addr_pad_gen
      // pad with zeroes to larger size
      always_comb begin
        msg_addr = {{($bits(msg_addr_t) - $bits(unrolled_addr_t)) {1'b0}}, unrolled_req.addr};
      end
    end else if ($bits(msg_addr_t) < $bits(unrolled_addr_t)) begin : msg_addr_truncate_gen
      // truncate to smaller size
      always_comb begin
        msg_addr = unrolled_req.addr[$bits(msg_addr_t) - 1:0];
      end
    end else begin : msg_addr_keep_gen
      // cast to equal size
      always_comb begin
        msg_addr = msg_addr_t '(unrolled_req.addr);
      end
    end
  endgenerate

  // encode header2 - if required
  //FIXME: amo_mask0 is an undocumented field
  always_comb begin
    hdr2 = {$bits (noc_hdr2_t) {1'b0}};  // avoid unassigned bits

    hdr2.addr       = msg_addr;
    hdr2.data_size  = msg_opts2_size (unrolled_req.size);
    hdr2.icache_bit = 1'b0;
    hdr2.amo_mask0  = (msg_opts2_size (unrolled_req.size) == MSG_DATA_SIZE_16B)? 8'hFF: 8'h00;
  end

  // encode header 3 - if required
  //FIXME: amo_mask1 is an undocumented field
  always_comb begin
    hdr3 = {$bits (noc_hdr3_t) {1'b0}};  // avoid unassigned bits

    hdr3.src_chipid = src_chipid;
    hdr3.src_xpos   = src_xpos;
    hdr3.src_ypos   = src_ypos;
    hdr3.src_fbits  = src_fbits;
    hdr3.amo_mask1  = (msg_opts2_size (unrolled_req.size) == MSG_DATA_SIZE_16B)? 8'hFF: 8'h00;
  end

  genvar b, f;

  // prepare write data for transmission
  // first: different PMESH components require narrow data to be placed:
  // - according to the address alignment,
  // - at the least-significant end or
  // - at the most-significant end
  msg_fld_data_t  low_data;
  wide_data_t     wide_data;
  msg_fld_data_t  high_data;
  msg_fld_data_t  copy_data;

  always_comb begin
    low_data  = msg_fld_data_t'(unrolled_req.data[((unrolled_req.ofst >> LOG2_MSG_FIELD_BYTES) * MSG_FIELD_BITS) +: MSG_FIELD_BITS] >> (unrolled_req.ofst << LOG2_BYTE));
    wide_data = wide_data_t'({low_data, {MSG_FIELD_BITS {1'b0}}} >> (unrolled_req.size << LOG2_BYTE));
    high_data = msg_fld_data_t'(wide_data[MSG_FIELD_BITS - 1:0]);
    copy_data = high_data | unrolled_req.data[((unrolled_req.ofst >> LOG2_MSG_FIELD_BYTES) * MSG_FIELD_BITS) +: MSG_FIELD_BITS] | low_data;
  end

  for (f = 0; f < (UNRL_REQ_DATA_BYTES >> LOG2_MSG_FIELD_BYTES); f++) begin : replicated_data_gen
    always_comb begin
      if (unrolled_req.size <= MSG_FIELD_BYTES) begin : copy_data_gen
        replicated_data[(f * MSG_FIELD_BITS) +: MSG_FIELD_BITS] = copy_data;
      end else begin : keep_data_gen
        replicated_data[(f * MSG_FIELD_BITS) +: MSG_FIELD_BITS] = unrolled_req.data[(f * MSG_FIELD_BITS) +: MSG_FIELD_BITS];
      end
    end
  end

  //second: PMESH transfers data bytes in Big Endian order
  // the bytes in each data field must be reversed, i.e., turned into big-endian
  //NOTE: every field must stay in place!
  for (f = 0; f < (UNRL_REQ_DATA_BYTES >> LOG2_MSG_FIELD_BYTES); f++) begin : reordered_data_gen
    // move each byte to its new position
    for (b = 0; b < MSG_FIELD_BYTES; b++) begin : reordered_data_fields_gen
      always_comb begin
        reordered_data[(f * MSG_FIELD_BITS) + ((MSG_FIELD_BYTES - 1 - b) * BITS_IN_BYTE) +: BITS_IN_BYTE] =
          replicated_data[(f * MSG_FIELD_BITS) + (b * BITS_IN_BYTE) +: BITS_IN_BYTE];
      end
    end
  end

  // populate message
  always_comb begin
    // data padding - avoids unknows
    //NOTE: PMESH does not have padding rules
    message = {MSG_BITS {1'b0}};

    message[MSG_HDR1_POS +: MSG_FIELD_BITS] = hdr1;

    if (hdr_len > 1) begin
      message[MSG_HDR2_POS +: MSG_FIELD_BITS] = hdr2;

      if (hdr_len > 2) begin
        message[MSG_HDR3_POS +: MSG_FIELD_BITS] = hdr3;
      end
    end

    // populate data - if writing
    if (!unrolled_req.rden) begin
      message[(hdr_len * MSG_FIELD_BITS) +: UNRL_REQ_DATA_BITS] = reordered_data;
    end
  end

  // NoC status
  always_comb begin
    noc_busy = (noc1_valid_out && !noc1_ready_in) || (internal_rst_n == 0);
  end

  // send message - may need to split in flits!
  generate

    if (REQ_MULTI_FLIT_SUPPORT) begin : multi_flit

      field_cnt_t remaining_fields;

      flit_t     flit;
      flit_cnt_t flit_cnt;
      flit_ptr_t flit_ptr;
      logic      flit_first;
      logic      flit_last;

      // unroller interface
      always_comb begin
        unrolled_req_rdy = (!noc_busy && flit_last);
      end

      // flit count and flit pointer
      always_ff @ (posedge clk or negedge rst_n) begin
        if (rst_n == 0) begin
          flit_cnt <= 0;
          flit_ptr <= 0;
        end else begin
          // send out only if not busy
          if (!noc_busy) begin
            if (unrolled_req_vld) begin
              // flit sent - count
              flit_cnt <= (flit_last ? 0 : (flit_cnt + 1));
              flit_ptr <= (flit_last ? 0 : (flit_ptr + NOC1_FLIT_BITS));
            end
          end
        end
      end

      // is this the first flit in a message?
      always_comb begin
        flit_first = (flit_cnt == 0);
      end

      // is this the last flit in a message?
      always_comb begin
        flit_last = flit_first ? (msg_len < NOC1_FIELDS_PER_FLIT) : (remaining_fields < NOC1_FIELDS_PER_FLIT);
      end

      // keep track of the number of fields yet to be transmitted
      //NOTE: if fewer than NOC1_FIELDS_PER_FLIT then this is the last flit.
      always_ff @ (posedge clk or negedge rst_n) begin
        if (rst_n == 0) begin
          remaining_fields <= 0;
        end else begin
          if (!noc_busy) begin
            if (unrolled_req_vld) begin
              if (flit_first) begin
                remaining_fields <= msg_len - NOC1_FIELDS_PER_FLIT;
              end else begin
                remaining_fields <= remaining_fields - NOC1_FIELDS_PER_FLIT;
              end
            end
          end
        end
      end

      // select flit from message
      always_comb begin
        flit = message[flit_ptr +: NOC1_FLIT_BITS];
      end

      // send NoC request out
      always_ff @ (posedge clk or negedge rst_n) begin
        if (rst_n == 0) begin
          noc1_valid_out <= 1'b0;
          noc1_data_out  <= {$bits (noc1_data_t) {1'b0}};  //NOTE: unnecessary but avoids linting error!
        end else begin
          // send out only if not busy
          if (!noc_busy) begin
            if (unrolled_req_vld) begin
              // new request - send out
              noc1_valid_out <= 1'b1;
              noc1_data_out  <= flit;
            end else begin
              // no new request - indicate not valid
              noc1_valid_out <= 1'b0;
            end
          end
        end
      end

    end else begin : no_multi_flit

      // unroller interface
      always_comb begin
        unrolled_req_rdy = !noc_busy;
      end

      // send NoC request out
      always_ff @ (posedge clk or negedge rst_n) begin
        if (rst_n == 0) begin
          noc1_valid_out <= 1'b0;
          noc1_data_out  <= {$bits (noc1_data_t) {1'b0}};  //NOTE: unnecessary but avoids linting error!
        end else begin
          // send out only if not busy
          if (!noc_busy) begin
            if (unrolled_req_vld) begin
              // new request - send out
              noc1_valid_out <= 1'b1;
              noc1_data_out  <= message;
            end else begin
              // no new request - indicate not valid
              noc1_valid_out <= 1'b0;
            end
          end
        end
      end
    end

  endgenerate
  // ----------------------------------------------------------------
endmodule
