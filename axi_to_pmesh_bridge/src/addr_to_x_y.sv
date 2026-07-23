// Copyright (c) 2019 multiple authors
// All rights reserved.

// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//     * Redistributions of source code must retain the above copyright
//       notice, this list of conditions and the following disclaimer.
//     * Redistributions in binary form must reproduce the above copyright
//       notice, this list of conditions and the following disclaimer in the
//       documentation and/or other materials provided with the distribution.
//     * Neither the name of the authors nor the
//       names of its contributors may be used to endorse or promote products
//       derived from this software without specific prior written permission.

// THIS SOFTWARE IS PROVIDED BY THE AUTHORS "AS IS" AND
// ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
// WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY
// DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
// (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
// LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
// ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
// SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
// ****************************************************************
// NOTE : 
// This code is taken, with minor modifications, from OpenPiton file axi_noc_bridge.sv
// https://github.com/PolyMTL-Gr2m/ara/blob/noc_bridge_fix/openpiton/axi_noc_bridge.sv
//                      
// Modifications have been made by lap - luis.plana@bsc.es in 2024
// ****************************************************************

// include OpenPiton macro definitions
`include "l2.tmp.h"
`include "define.tmp.h"

module addr_to_x_y (
  input  logic [`HOME_ID_WIDTH-1:0]                system_tile_count,
  input  logic [`HOME_ALLOC_METHOD_WIDTH-1:0]      home_alloc_method,
  input  logic [`PHY_ADDR_WIDTH-1:0]               axi2noc_req_address_s0,
  output logic [`NOC_X_WIDTH-1:0]                  lhid_s1_x,
  output logic [`NOC_Y_WIDTH-1:0]                  lhid_s1_y
);
  // ----------------------------------------------------------------
  // OpenPiton NoC destination coordinates calculation
  // ----------------------------------------------------------------
  logic [`HOME_ID_WIDTH-1:0]  lhid_s0;
  logic [`HOME_ID_WIDTH-1:0]  lhid_s1;
  logic [`HOME_ID_WIDTH-1:0]  home_addr_bits_s0;
  logic                       special_l2_addr_s0;

  l15_home_encoder    l15_home_encoder(
  .home_in        (home_addr_bits_s0),
  .num_homes      (system_tile_count),
  .lhid_out       (lhid_s0)
  );

  flat_id_to_xy lhid_to_xy (
      .flat_id(lhid_s1[`HOME_ID_WIDTH-1:0]),
      .x_coord(lhid_s1_x),
      .y_coord(lhid_s1_y)
  );

  assign lhid_s1 = lhid_s0;  // lap - replaces FF below
/* lap - not necessary
  always_ff@(posedge clk or negedge rst_n) begin
      if (!rst_n) lhid_s1 <= `HOME_ID_WIDTH'b0;
      else if (cal_dest_stage1) lhid_s1 <= lhid_s0;
      else lhid_s1 <= lhid_s1;
  end
/lap */

/*lap - not necessary
  always_comb
  begin
      cal_dest_stage0 = (flit_state_f == MSG_STATE_IDLE);
      cal_dest_stage1 = (flit_state_f == MSG_STATE_DEST_CAL);
      cal_dest_stage2 = (flit_state_f == MSG_STATE_HEADER);
  end
/lap */

  always_comb
  begin
      //special l2 addresses start with 0xA
      special_l2_addr_s0 = (axi2noc_req_address_s0[39:36] == 4'b1010);
  end

/* lap - not necessary
  always_comb begin
      unique case (type_fifo_out)
          MSG_TYPE_STORE: axi2noc_req_address_s0 = awaddr_buffer_q[`PHY_ADDR_WIDTH-1:0];
          MSG_TYPE_LOAD: axi2noc_req_address_s0 = araddr_buffer_q[`PHY_ADDR_WIDTH-1:0];
          MSG_TYPE_INVAL:axi2noc_req_address_s0 = `PHY_ADDR_WIDTH'b0;
          default: axi2noc_req_address_s0 = `PHY_ADDR_WIDTH'b0;
      endcase
  end
/lap */

  always_comb
  begin
      if (special_l2_addr_s0)
      begin
          home_addr_bits_s0 = axi2noc_req_address_s0[`HOME_ID_ADDR_POS_HIGH];
      end
      else
      begin
          unique case (home_alloc_method)
          `HOME_ALLOC_LOW_ORDER_BITS:
          begin
              home_addr_bits_s0 = axi2noc_req_address_s0[`HOME_ID_ADDR_POS_LOW];
          end
          `HOME_ALLOC_MIDDLE_ORDER_BITS:
          begin
              home_addr_bits_s0 = axi2noc_req_address_s0[`HOME_ID_ADDR_POS_MIDDLE];
          end
          `HOME_ALLOC_HIGH_ORDER_BITS:
          begin
              home_addr_bits_s0 = axi2noc_req_address_s0[`HOME_ID_ADDR_POS_HIGH];
          end
          `HOME_ALLOC_MIXED_ORDER_BITS:
          begin
              home_addr_bits_s0 = (axi2noc_req_address_s0[`HOME_ID_ADDR_POS_LOW] ^ axi2noc_req_address_s0[`HOME_ID_ADDR_POS_MIDDLE]);
          end
          default: home_addr_bits_s0 = `MSG_LHID_WIDTH'b0;
          endcase
      end
  end
  // ****************************************************************
endmodule