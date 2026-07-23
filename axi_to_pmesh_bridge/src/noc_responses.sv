/* ------------------------------------------------------------------
 * Organization   : Barcelona Supercomputing Center
 * File           : noc_responses.sv
 * Description    : component of the noc_driver module, part
 *                  of the axi_to_pmesh_bridge, that handles
 *                  OpenPiton PMESH (NoC) responses
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
 * ------------------------------------------------------------------
 * TODO:
 * ------------------------------------------------------------------
 */

module noc_responses
  import axi_to_pmesh_bridge_pkg::*;
#(
  // unrolled ID types
  parameter type UNROLLED_IDS_T  = logic,
  parameter type UNROLLED_IFID_T = logic
)
(
  input  logic           clk,
  input  logic           rst_n,

  input  logic           noc2_valid_in,
  input  noc2_data_t     noc2_data_in,
  output logic           noc2_ready_out,

  //NOTE: the unroller is always ready to receive responses - no need for unrolled_rsp_rdy
  output unrolled_rsp_t  unrolled_rsp,
  output UNROLLED_IFID_T unrolled_rsp_ifid,
  output logic           unrolled_rsp_vld
);
  // ----------------------------------------------------------------
  // constants
  // ----------------------------------------------------------------
  localparam unsigned UNRL_RSP_DATA_BYTES = UNRL_RSP_DATA_BITS / BITS_IN_BYTE;

  // maximum message length in bits
  localparam unsigned RSP_HDR_BITS        = MAX_RSP_HDR_NUM * MSG_FIELD_BITS;
  localparam unsigned MSG_BITS            = RSP_HDR_BITS + UNRL_REQ_DATA_BITS;

  // number of flits required to receive a message
  //NOTE: the received message has to be a whole number of flits - may have padding!
  localparam unsigned FLITS_PER_MSG       = ((MSG_BITS - 1) / NOC2_FLIT_BITS) + 1;

  // transmitted message length
  localparam unsigned MESSAGE_BITS        = FLITS_PER_MSG * NOC2_FLIT_BITS;
  localparam unsigned MSG_BITS_CNT_BITS   = $clog2 (MESSAGE_BITS - 1) + 1;
  localparam unsigned MESSAGE_FIELDS      = MESSAGE_BITS / MSG_FIELD_BITS;

  // number of sections that may need rebuilding
  localparam unsigned RBLD_SEC_NUM        = $clog2 (UNRL_RSP_DATA_BYTES / MSG_FIELD_BYTES);

  // need multi-flt support if longest possible message does not fit in a single NOC2 flit
  localparam unsigned RSP_MULTI_FLIT_SUPPORT = ((MAX_RSP_HDR_NUM + (UNRL_RSP_DATA_BYTES / MSG_FIELD_BYTES)) > NOC2_FIELDS_PER_FLIT);
  // ----------------------------------------------------------------

  // ----------------------------------------------------------------
  // NoC request types
  // ----------------------------------------------------------------
  typedef logic       [MESSAGE_BITS - 1:0] message_t;

  typedef logic     [NOC2_FLIT_BITS - 1:0] flit_t;
  typedef logic  [MSG_FLIT_CNT_BITS - 1:0] flit_cnt_t;
  typedef logic  [MSG_BITS_CNT_BITS - 1:0] flit_ptr_t;

  typedef logic [MSG_FIELD_CNT_BITS - 1:0] field_cnt_t;
  // ----------------------------------------------------------------

  // ----------------------------------------------------------------
  // NoC response manager
  // ----------------------------------------------------------------
  noc_hdr1_t      hdr1;
  hdr_pld_size_t  pld_len;
  msg_type_t      rsp_type;
  UNROLLED_IDS_T  rsp_ids;
  hdr_bits_t      hdr_bits;

  unrolled_rsp_data_t msg_data;
  unrolled_rsp_data_t reordered_data;
  unrolled_rsp_data_t rsp_data;

  // determine NoC rsp characteristics:
  always_comb begin
    // extract hdr1 - contains all relevant information
    hdr1 = noc_hdr1_t '(noc2_data_in[MSG_HDR1_POS +: MSG_FIELD_BITS]);

    // request type
    rsp_type = hdr1.message_type;

    // payload length
    //NOTE: assumes that header length == 1 for all responses!
    pld_len = hdr1.message_length[0 +: $bits (hdr_pld_size_t)];
  end

  // extract message data - may need to process several flits
  generate

    if (RSP_MULTI_FLIT_SUPPORT) begin : multi_flit
      message_t  message;

      field_cnt_t remaining_fields;

      flit_t     flit;
      flit_cnt_t flit_cnt;
      flit_ptr_t flit_ptr;
      logic      flit_first;
      logic      flit_last;

      // keep flit count
      always_ff @ (posedge clk or negedge rst_n) begin
        if (rst_n == 0) begin
          flit_cnt <= 0;
          flit_ptr <= 0;
        end else begin
          // send out only if not busy
          if (noc2_valid_in) begin
            // flit received - count
            flit_cnt <= (flit_last ? 0 : (flit_cnt + 1));
            flit_ptr <= (flit_last ? 0 : (flit_ptr + NOC2_FLIT_BITS));
          end
        end
      end

      // is this the first flit in a message?
      always_comb begin
        flit_first = (flit_cnt == 0);
      end

      // is this the last flit in a message?
      always_comb begin
        flit_last = flit_first ? (pld_len < NOC2_FIELDS_PER_FLIT) : (remaining_fields < NOC2_FIELDS_PER_FLIT);
      end

      // keep track of the number of fields yet to be received
      //NOTE: if fewer than NOC2_FIELDS_PER_FLIT then this is the last flit.
      always_ff @ (posedge clk or negedge rst_n) begin
        if (rst_n == 0) begin
          remaining_fields <= 0;
        end else begin
          if (noc2_valid_in) begin
            if (flit_first) begin
              remaining_fields <= pld_len - NOC2_FIELDS_PER_FLIT;
            end else begin
              remaining_fields <= remaining_fields - NOC2_FIELDS_PER_FLIT;
            end
          end
        end
      end

      // append new flit to message
      always_ff @ (posedge clk or negedge rst_n) begin
        if (rst_n == 0) begin
          message <= 0;
        end else begin
          if (noc2_valid_in) begin
            message[flit_ptr +: NOC2_FLIT_BITS] <= noc2_data_in;
          end
        end
      end

      // remember message ifid and mrid - arrive in first flit
      always_ff @ (posedge clk or negedge rst_n) begin
        if (rst_n == 0) begin
          hdr_bits     <= 0;
          rsp_ids.ifid <= 0;
          rsp_ids.mrid <= 0;
        end else begin
          if (noc2_valid_in) begin
            if (flit_first) begin
              hdr_bits <= noc_hdr_bits (rsp_type);
              rsp_ids  <= UNROLLED_IDS_T'(hdr1.mshr_tag);
            end
          end
        end
      end

      // choose correct data - data payload starts after headers
      always_comb begin
        msg_data = message[hdr_bits +: UNRL_RSP_DATA_BITS];
      end

      // indicate validity to unroller
      always_ff @ (posedge clk or negedge rst_n) begin
        if (rst_n == 0) begin
          unrolled_rsp_vld <= 0;
        end else begin
          unrolled_rsp_vld <= (noc2_valid_in && flit_last);
        end
      end

    end else begin : no_multi_flit

      always_comb begin
        // choose correct data - data payload starts after headers
        hdr_bits = noc_hdr_bits (rsp_type);
        rsp_ids  = UNROLLED_IDS_T'(hdr1.mshr_tag);
        msg_data = noc2_data_in[hdr_bits +: UNRL_RSP_DATA_BITS];
      end

      // indicate validity to unroller
      always_comb begin
        unrolled_rsp_vld = noc2_valid_in;
      end

    end

  endgenerate

  // process received (message) data
  //NOTE: PMESH transfers data bytes in Big Endian order
  genvar b, f;
  // the bytes in each data field must be reversed, i.e., turned back into little-endian
  //NOTE: every field must stay in place!
  for (f = 0; f < (UNRL_RSP_DATA_BYTES >> LOG2_MSG_FIELD_BYTES); f++) begin : reordered_data_gen
    // move each byte to its new position
    for (b = 0; b < MSG_FIELD_BYTES; b++) begin : reordered_data_fields_gen
      always_comb begin
        // data payload starts after headers
        reordered_data[(f * MSG_FIELD_BITS) + ((MSG_FIELD_BYTES - 1 - b) * BITS_IN_BYTE) +: BITS_IN_BYTE] =
              msg_data[(f * MSG_FIELD_BITS) + (b * BITS_IN_BYTE) +: BITS_IN_BYTE];
      end
    end
  end

  // prepare new data and ifid
  //NOTE: data is not needed on WRITEs - the unroller will ignore it
  always_comb begin
    rsp_data          = reordered_data;
    unrolled_rsp_ifid = rsp_ids.ifid;
  end

  // rebuild data returned by narrow loads -- rebuild information is kept in MRID
  // the least-significant bits are always in the correct place
  always_comb begin
    unrolled_rsp.data[0 +: MSG_FIELD_BITS] = rsp_data[0 +: MSG_FIELD_BITS];
  end

  // the rest may need relocating
/* verilator lint_off ALWCOMBORDER */
  for (f = 0; f < RBLD_SEC_NUM; f++) begin : unrolled_rsp_data_gen
    always_comb begin
      unrolled_rsp.data[(1 << f) * MSG_FIELD_BITS +: ((1 << f) * MSG_FIELD_BITS)] =
        (rsp_ids.mrid[f] ? unrolled_rsp.data[0 +: ((1 << f) * MSG_FIELD_BITS)] :
                            rsp_data[(1 << f) * MSG_FIELD_BITS +: ((1 << f) * MSG_FIELD_BITS)]);
    end
  end
/* verilator lint_on ALWCOMBORDER */

  // receive NoC response
  //NOTE: the module is always ready to receive responses
  always_comb begin
    if (rst_n == 0) begin
      noc2_ready_out = 1'b0;
    end else begin
      noc2_ready_out = 1'b1;
    end
  end
  // ----------------------------------------------------------------
endmodule
