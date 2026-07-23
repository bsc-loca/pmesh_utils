/* ------------------------------------------------------------------
 * Organization   : Barcelona Supercomputing Center
 * File           : write_unroller.sv
 * Description    : component of the noc_driver module, part of the
 *                  axi_to_pmesh_bridge, that unrolls a single AXI write
 *                  request into one or more OpenPiton PMESH (NoC) write
 *                  requests of the correct size at the correct address
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
 *  Revision   | Author                               | Description
 *  0.0.1      | lap - luis.plana@bsc.es              | initial code version
 *             | Manjunath - manjunath.kalmath@bsc.es |
 * ------------------------------------------------------------------
 * Dependencies
 * This module uses priority_encoder module from:
 * https://github.com/alexforencich/verilog-axis/blob/master/rtl/priority_encoder.v
 * ------------------------------------------------------------------
 * TODO:
 * ------------------------------------------------------------------
 */

module write_unroller
  import axi_to_pmesh_bridge_pkg::*;
#(
  // unrolled ID types
  parameter type UNROLLED_MRID_T = logic
)
(
  input  logic               rst_n,
  input  logic               clk,
  input  logic               sel_wr,
  input  logic               req_busy,
  input  wrt_unr_tran_data_t wr_trans,
  input  logic               wr_part_last,
  input  logic               mr_stall,
  output logic               mr_vld,
  output unrolled_req_data_t mr_data,
  output unrolled_addr_t     mr_addr,
  output unrolled_ofst_t     mr_ofst,
  output unrolled_size_t     mr_size,
  output UNROLLED_MRID_T     mr_id,
  output logic               mr_last
);
  // ----------------------------------------------------------------
  // constants
  // ----------------------------------------------------------------
  localparam unsigned UNRL_MR_DATA_BYTES = UNRL_REQ_DATA_BITS / BITS_IN_BYTE;

  localparam unsigned NUM_SEC       = (AIF_DATA_BITS > UNRL_REQ_DATA_BITS) ? AIF_DATA_BITS / UNRL_REQ_DATA_BITS : 1;

  localparam unsigned SEC_BITS      = NUM_SEC;
  localparam unsigned SEC_CNT_BITS  = (SEC_BITS > 1) ? $clog2 (SEC_BITS) : 1;

  localparam unsigned MR_WSTRB_BITS = AIF_WSTRB_BITS / NUM_SEC;

  localparam unsigned COMP_BITS     = (2 * MR_WSTRB_BITS) - 1;
  localparam unsigned COMP_LEVELS   = (COMP_BITS > 1) ? $clog2 (COMP_BITS) : 1;
  // ----------------------------------------------------------------

  // ----------------------------------------------------------------
  // NoC response types
  // ----------------------------------------------------------------
  typedef logic               [SEC_BITS - 1:0] sec_t;
  typedef logic           [SEC_CNT_BITS - 1:0] sec_cnt_t;
  typedef logic          [MR_WSTRB_BITS - 1:0] mr_wstrb_t;
  typedef logic              [COMP_BITS - 1:0] comp_t;
  typedef logic            [COMP_LEVELS - 1:0] comp_enc_t;
  typedef aif_wstrb_t                          wstrb_t;
  // ----------------------------------------------------------------

  // ----------------------------------------------------------------
  // write unroller
  // ----------------------------------------------------------------
  sec_t               sec_comp;
  sec_t               sec_mask, sec_nxt_mask;
  logic               sec_done;
  logic               sec_last;
  sec_cnt_t           sec_num;
  mr_wstrb_t          sec_wstb;

  mr_wstrb_t          mr_wstb;
  mr_wstrb_t          mr_mask;
  unrolled_req_data_t mr_bmsk;

  comp_t              comp;
  comp_enc_t          comp_enc;
  mr_wstrb_t          wstb;
  mr_wstrb_t          mask;

  mr_wstrb_t          masks [COMP_BITS:0];
  unrolled_size_t     sizes [COMP_BITS:0];
  unrolled_ofst_t     offsets [COMP_BITS:0];

  // generate section number - go through non-empty sections only
  genvar n;
  for (n = 0; n < SEC_BITS; n++) begin : sec_comp_gen
    always_comb begin
      sec_comp[n] = ((|wr_trans.wstrb[(n * UNRL_MR_DATA_BYTES) +: UNRL_MR_DATA_BYTES]) & sec_mask[n]);
    end
  end

  // priority encode section comparators result
  generate
    if (SEC_BITS > 1) begin : sec_prio_enc_gen
      alexforencich_priority_encoder #(
        .WIDTH             (SEC_BITS),
        .LSB_HIGH_PRIORITY (1)
        )
      sec_alexforencich_priority_encoder (
        .input_unencoded  (sec_comp),
        .output_valid     (),
        .output_encoded   (sec_num),
        .output_unencoded ()
      );
    end else begin : no_sec_prio_enc_gen
      assign sec_num = 0;
    end
  endgenerate

  // generate micro-request write strobes
  always_comb begin
    sec_wstb = wr_trans.wstrb[(sec_num * UNRL_MR_DATA_BYTES) +: UNRL_MR_DATA_BYTES];
    wstb     = (sec_wstb & mask);
    mr_wstb  = (wstb & mr_mask);
  end

  // search wstb for longest "1" chain remaining - to generate micro-request
  //NOTE: the comparators for MR_WSTRB_BITS = 8 are shown here for reference:
  // comp[0]  = (wstb[7:0] == 8'b1111_1111);
  // comp[1]  = (wstb[3:0] == 4'b1111);
  // comp[2]  = (wstb[7:4] == 4'b1111);
  // comp[3]  = (wstb[1:0] == 2'b11);
  // comp[4]  = (wstb[3:2] == 2'b11);
  // comp[5]  = (wstb[5:4] == 2'b11);
  // comp[6]  = (wstb[7:6] == 2'b11);
  // comp[7]  = (wstb[0]   == 1'b1);
  // comp[8]  = (wstb[1]   == 1'b1);
  // comp[9]  = (wstb[2]   == 1'b1);
  // comp[10] = (wstb[3]   == 1'b1);
  // comp[11] = (wstb[4]   == 1'b1);
  // comp[12] = (wstb[5]   == 1'b1);
  // comp[13] = (wstb[6]   == 1'b1);
  // comp[14] = (wstb[7]   == 1'b1);
  //
  //NOTE: the masks for MR_WSTRB_BITS = 8 are shown here for reference:
  //  masks [COMP_BITS:0] =
  //     { 8'b0000_0000, 8'b1000_0000, 8'b0100_0000, 8'b0010_0000,
  //       8'b0001_0000, 8'b0000_1000, 8'b0000_0100, 8'b0000_0010,
  //       8'b0000_0001, 8'b1100_0000, 8'b0011_0000, 8'b0000_1100,
  //       8'b0000_0011, 8'b1111_0000, 8'b0000_1111, 8'b1111_1111
  //     };
  //
  //NOTE: the sizes for MR_WSTRB_BITS = 8 are shown here for reference:
  //   sizes [COMP_BITS:0] =
  //     { 4'd0, 4'd1, 4'd1, 4'd1, 4'd1, 4'd1, 4'd1, 4'd1,
  //       4'd1, 4'd2, 4'd2, 4'd2, 4'd2, 4'd4, 4'd4, 4'd8
  //     };
  //
  //NOTE: the offsets for MR_WSTRB_BITS = 8 are shown here for reference:
  //   offsets [COMP_BITS:0] =
  //     { 6'd0, 6'd7, 6'd6, 6'd5, 6'd4, 6'd3, 6'd2, 6'd1,
  //       6'd0, 6'd6, 6'd4, 6'd2, 6'd0, 6'd4, 6'd0, 6'd0
  //     };
  genvar l, i;
  for (l = 0; l < COMP_LEVELS; l++) begin : comp_levels_gen
    for (i = 0; i < (1 << l); i++) begin : masks_sizes_offsets_gen
      always_comb begin
        comp[(1 << l) - 1 + i]    = wstb[(i * ($bits (mr_wstrb_t) / (1 << l))) +: ($bits (mr_wstrb_t) / (1 << l))] == {($bits (mr_wstrb_t) / (1 << l)) {1'b1}};

        masks[(1 << l) - 1 + i]   = {($bits (mr_wstrb_t) / (1 << l)) {1'b1}} << (i * ($bits (mr_wstrb_t) / (1 << l)));
        sizes[(1 << l) - 1 + i]   = $bits (mr_wstrb_t) / (1 << l);
        offsets[(1 << l) - 1 + i] = i * ($bits (mr_wstrb_t) / (1 << l));
      end
    end
  end

  //NOTE: not really needed - avoid unknowns!
  always_comb begin
    masks[COMP_BITS]   = {$bits (mr_wstrb_t) {1'b0}};
    sizes[COMP_BITS]   = {$bits (unrolled_size_t)  {1'b0}};
    offsets[COMP_BITS] = {$bits (unrolled_addr_t)  {1'b0}};
  end

  // priority encode comparators result
  generate
    if (COMP_BITS > 1) begin : comp_prio_enc_gen
      alexforencich_priority_encoder #(
        .WIDTH             (COMP_BITS),
        .LSB_HIGH_PRIORITY (1)
      )
      alexforencich_priority_encoder_inst (
        .input_unencoded  (comp),
        .output_valid     (),
        .output_encoded   (comp_enc),
        .output_unencoded ()
      );
    end else begin : no_comp_prio_enc_gen
      assign comp_enc = 0;
    end
  endgenerate

  // generate micro-request size and address offset
  always_comb begin
    mr_size  = sizes[comp_enc];
    mr_ofst  = offsets[comp_enc];  // this offset is relative to the section
  end

  // generate micro-request write address
  always_comb begin
    mr_addr = wr_trans.addr + (sec_num * UNRL_MR_DATA_BYTES) + mr_ofst;
  end

  // generate bit mask - used to extract narrow data
  for (n = 0; n < MR_WSTRB_BITS; n++) begin : mr_bit_masks_gen
    always_comb begin
      mr_bmsk[(n * BITS_IN_BYTE) +: BITS_IN_BYTE] = {BITS_IN_BYTE {mr_wstb[n]}};
    end
  end

  // generate micro-request write data
  always_comb begin
    mr_data = wr_trans.data[(sec_num * UNRL_REQ_DATA_BITS) +: UNRL_REQ_DATA_BITS] & mr_bmsk;
  end

  // generate micro-request ID
  always_ff @(posedge clk or negedge rst_n) begin
    if (rst_n == 0) begin
      mr_id <= 0;
    end else begin
      if ((mr_last && wr_part_last) || !sel_wr) begin
        mr_id <= 0;
      end else if (mr_vld) begin
        mr_id <= mr_id + 1;  //NOTE: wrap around is OK!
      end
    end
  end

  // generate flag to indicate last micro-request
  always_comb begin
    mr_last = sec_last;
  end

  // indicate valid micro-request
  always_comb begin
    mr_vld = (sel_wr && !req_busy && !mr_stall);
  end

  // prepare for next micro-request
  always_comb begin
    mr_mask = masks[comp_enc];
  end

  // update mask for next micro-request
  always_ff @(posedge clk or negedge rst_n) begin
    if (rst_n == 0) begin
      mask <= {MR_WSTRB_BITS {1'b1}};
    end else begin
      if (sec_done) begin
        mask <= {MR_WSTRB_BITS {1'b1}};
      end else if (mr_vld) begin
        mask <= (mask & ~mr_mask);
      end
    end
  end

  // keep track of micro-request section status
  always_comb begin
    sec_done = (mr_vld && ((wstb & ~mr_mask) == {MR_WSTRB_BITS {1'b0}}));
    sec_last = (sec_done && ((sec_comp & sec_nxt_mask) == {SEC_BITS {1'b0}}));
  end

  // update section mask to select next section
  always_comb begin
    sec_nxt_mask = {SEC_BITS {1'b1}} << (sec_num + 1);
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (rst_n == 0) begin
      sec_mask <= {SEC_BITS {1'b1}};
    end else begin
      if (sec_last || !sel_wr) begin
        sec_mask <= {SEC_BITS {1'b1}};
      end else if (sec_done) begin
        sec_mask <= sec_nxt_mask;
      end
    end
  end
  // ----------------------------------------------------------------
endmodule
