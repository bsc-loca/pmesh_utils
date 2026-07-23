/* ------------------------------------------------------------------
 * Organization   : Barcelona Supercomputing Center
 * File           : axi_slave_rd_pipeline.sv
 * Description    : component of the axi_slave_wrapper_pipeline module
 *                  and part of axi_to_pmesh_bridge which handles
 *                  AXI read transactions from AXI Master
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
 * ------------------------------------------------------------------
 * PARAMETERS:
 * ON_FLY_RD_NUM              = number of in-flight read requests.
 * BRIDGE_SUPPORT_AXI_AXCACHE = support AXI ARCACHE signal.
 * ------------------------------------------------------------------
 * TODO:
 * ------------------------------------------------------------------
 */

module axi_slave_rd_pipeline
    import axi_to_pmesh_bridge_pkg::*;
#(
    parameter          ON_FLY_RD_NUM = 4,
    parameter unsigned BRIDGE_SUPPORT_AXI_AXCACHE = 0
)
(
    // Read Addrs FIFO signals
    output wire                          o_addr_fifo_wr_rq    ,
    output wire [RD_ADDR_FIFO_WIDTH-1:0] o_addr_fifo_data     ,
    //input  wire                          i_addr_fifo_empty    ,
    input  wire                          i_addr_fifo_full     ,

    // Read Data FIFO signals: this fifo should be show ahead
    output wire                          o_data_fifo_rd_rq    ,
    input  wire [RD_DATA_FIFO_WIDTH-1:0] i_data_fifo_data     ,
    input  wire                          i_data_fifo_empty    ,

    // AXI Read Signals
    input  wire                          S_AXI_ACLK           ,
    input  wire                          S_AXI_ARESETN        ,

    // Main read addr signals ----------------------
    output reg                           S_AXI_ARREADY        ,
    input  wire  [AXI_ADDR_WIDTH-1:0]    S_AXI_ARADDR         ,
    input  wire                          S_AXI_ARVALID        ,
    input  wire  [AXI_LEN_WIDTH-1:0]     S_AXI_ARLEN          ,
    input  wire  [AXI_SIZE_WIDTH-1:0]    S_AXI_ARSIZE         ,
    // ---------------------------------------------

    input  wire  [AXI_ID_WIDTH-1:0]      S_AXI_ARID           ,
    input  wire  [AXI_BURST_WIDTH-1:0]   S_AXI_ARBURST        ,
    input  wire                          S_AXI_ARLOCK         ,
    input  wire  [AXI_CACHE_WIDTH-1:0]   S_AXI_ARCACHE        ,
    input  wire  [AXI_PROT_WIDTH-1:0]    S_AXI_ARPROT         ,
    input  wire  [AXI_QOS_WIDTH-1:0]     S_AXI_ARQOS          ,
    input  wire  [AXI_REGION_WIDTH-1:0]  S_AXI_ARREGION       ,
    input  wire  [AXI_USER_WIDTH-1:0]    S_AXI_ARUSER         ,

    // Main write data signals ---------------------
    input  wire                          S_AXI_RREADY         ,
    output wire                          S_AXI_RVALID         ,
    output wire [AXI_DATA_WIDTH-1:0]     S_AXI_RDATA          ,
    output wire                          S_AXI_RLAST          ,
    // ---------------------------------------------

    output wire [AXI_USER_WIDTH-1:0]     S_AXI_RUSER          ,
    output reg  [AXI_ID_WIDTH-1:0]       S_AXI_RID            ,
    output wire [AXI_RESP_WIDTH-1:0]     S_AXI_RRESP
);

localparam RD_BUFFER_FIFO_DEPTH  = ON_FLY_RD_NUM - 1; //fifo adds 1 extra depth;
localparam RD_CNTR_FIFO_DEPTH    = ON_FLY_RD_NUM - 1;

typedef enum {
    ST_IDLE,
    ST_PUSH_RD_ADDRS
} states_t;

states_t                     state;
reg  [AXI_LEN_WIDTH-1:0]     s_addr_trans_cnt;
reg  [AXI_LEN_WIDTH-1:0]     s_fifo_data_cnt;
wire [AXI_ADDR_WIDTH-1:0]    s_addr_rd;
reg  [AXI_SIZE_WIDTH-1:0]    s_size_rd;
reg                          s_send_data;
reg                          s_addrs_start;
reg  [AXI_LEN_WIDTH:0]       s_N;
reg  [AXI_SIZE_WIDTH-1:0]    s_axi_arsize_reg;
reg  [AXI_ADDR_WIDTH-1:0]    s_start_addr;
wire [AXI_ADDR_WIDTH-1:0]    s_addr_aligned;
wire [AXI_ADDR_WIDTH-1:0]    s_addr_N;

// Read BUFFER FIFO signals: this fifo should be show ahead
wire                             s_rd_buffer_fifo_rd_rq;
wire                             s_rd_buffer_fifo_wr_rq;
wire [RD_BUFFER_FIFO_WIDTH-1:0]  s_rd_buffer_fifo_data_in;
wire [RD_BUFFER_FIFO_WIDTH-1:0]  s_rd_buffer_fifo_data_out;
wire                             s_rd_buffer_fifo_empty;
wire                             s_rd_buffer_fifo_full;

// Read BUFFER FIFO signals: this fifo should be show ahead
wire                             s_rd_cnt_fifo_rd_rq;
wire                             s_rd_cnt_fifo_wr_rq;
wire [RD_CNTR_FIFO_WIDTH-1:0]    s_rd_cnt_fifo_data_in;
wire [RD_CNTR_FIFO_WIDTH-1:0]    s_rd_cnt_fifo_data_out;
//wire [AXI_LEN_WIDTH-1:0]         s_rd_cnt;
wire                             s_rd_cnt_fifo_empty;
wire                             s_rd_cnt_fifo_full;

wire  [AXI_ADDR_WIDTH-1:0]       s_AXI_ARADDR_F;
wire  [AXI_LEN_WIDTH-1:0]        s_AXI_ARLEN_F;
wire  [AXI_SIZE_WIDTH-1:0]       s_AXI_ARSIZE_F;
reg   s_parse_en;

logic                            s_non_cache;

assign S_AXI_RUSER = 0;
assign S_AXI_RRESP = 0;

assign s_addr_aligned    = ((s_start_addr >> s_axi_arsize_reg) << s_axi_arsize_reg);
assign s_addr_N          = (s_addr_aligned + ((s_N - 1) << s_axi_arsize_reg)); //N starts from 1
assign s_addr_rd         = (s_N > 1) ? s_addr_N : s_addr_aligned;
assign s_size_rd         = s_axi_arsize_reg;


assign S_AXI_ARREADY            = ~s_rd_buffer_fifo_full & ~s_rd_cnt_fifo_full;
assign s_rd_buffer_fifo_wr_rq   = S_AXI_ARVALID & S_AXI_ARREADY;
assign s_rd_buffer_fifo_data_in = {S_AXI_ARLEN,S_AXI_ARSIZE,S_AXI_ARADDR};
assign s_rd_buffer_fifo_rd_rq   = ~s_rd_buffer_fifo_empty & ~i_addr_fifo_full & s_parse_en;
assign {s_AXI_ARLEN_F,s_AXI_ARSIZE_F,s_AXI_ARADDR_F} = s_rd_buffer_fifo_data_out;

always_ff @(posedge S_AXI_ACLK) begin
    if (!S_AXI_ARESETN)
    begin
        state               <= ST_IDLE;
        s_addrs_start       <= 0;
        s_addr_trans_cnt    <= 0;
        //S_AXI_RID           <= 0;
        s_N                 <= 1;
        s_start_addr        <= 0;
        s_axi_arsize_reg    <= 0;
        s_parse_en          <= 0;
    end
    else
    begin

        case(state)
            ST_IDLE: begin
                s_parse_en <= 1;
                if (s_rd_buffer_fifo_rd_rq) begin
                    s_parse_en          <= 0;
                    s_addr_trans_cnt    <= s_AXI_ARLEN_F;
                    s_axi_arsize_reg    <= s_AXI_ARSIZE_F;
                    s_start_addr        <= s_AXI_ARADDR_F;
                    state               <= ST_PUSH_RD_ADDRS;
                    //S_AXI_RID           <= S_AXI_ARID;
                    s_N                 <= 1;
                    s_addrs_start       <= 1;
                end
            end

            ST_PUSH_RD_ADDRS: begin
                if (o_addr_fifo_wr_rq) begin
                    if (s_addr_trans_cnt == 0) begin
                        state               <= ST_IDLE;
                        s_addrs_start       <= 0;
                        s_parse_en          <= 1;
                    end else begin
                        s_addr_trans_cnt    <= s_addr_trans_cnt - 1;
                    end
                    s_N                     <= s_N + 1;
                end
            end

            default: begin
                state <= ST_IDLE;
            end
        endcase
    end
end

assign s_rd_cnt_fifo_wr_rq   = s_rd_buffer_fifo_wr_rq;
assign s_rd_cnt_fifo_data_in = {S_AXI_ARID,S_AXI_ARLEN};
assign s_rd_cnt_fifo_rd_rq  = ~s_rd_cnt_fifo_empty & (~s_send_data || (S_AXI_RREADY && S_AXI_RLAST));


always_ff @(posedge S_AXI_ACLK) begin
    if (!S_AXI_ARESETN)
    begin
        s_fifo_data_cnt     <= 0;
        s_send_data         <= 0;
        S_AXI_RID           <= 0;
    end else begin

        if (s_rd_cnt_fifo_rd_rq) begin
            s_send_data     <= 1;
        end else if (S_AXI_RREADY && S_AXI_RLAST) begin
            s_send_data     <= 0;
        end


        if (o_data_fifo_rd_rq && (s_fifo_data_cnt > 0)) begin
            s_fifo_data_cnt <= s_fifo_data_cnt - 1;
        end else if (s_rd_cnt_fifo_rd_rq) begin
            {S_AXI_RID,s_fifo_data_cnt} <= s_rd_cnt_fifo_data_out;
        end

    end
end

generate
    if (BRIDGE_SUPPORT_AXI_AXCACHE) begin : arcache_support_gen
        always_ff @(posedge S_AXI_ACLK) begin
            if (!S_AXI_ARESETN)
            begin
                s_non_cache <= 0;
            end
            else
            begin
                if ((state == ST_IDLE) && (s_rd_buffer_fifo_rd_rq)) begin
                    s_non_cache <= (S_AXI_ARCACHE[3:2] == 2'b00);
                end
            end
        end
    end else begin : no_arcache_support_gen
        always_comb begin
            s_non_cache = 0;
        end
    end
endgenerate

assign o_addr_fifo_wr_rq = ~i_addr_fifo_full & s_addrs_start;
assign o_addr_fifo_data  = {s_addr_rd, s_size_rd, s_non_cache};
assign S_AXI_RVALID      = ~i_data_fifo_empty & s_send_data;
assign S_AXI_RLAST       = (s_fifo_data_cnt == 0) ? S_AXI_RVALID : 0;
assign o_data_fifo_rd_rq = S_AXI_RVALID & S_AXI_RREADY;
assign S_AXI_RDATA       = i_data_fifo_data;


fifo_v3 #(
    .FALL_THROUGH   (1'b0)                     ,
    .DATA_WIDTH     (RD_BUFFER_FIFO_WIDTH)     ,
    .DEPTH          (RD_BUFFER_FIFO_DEPTH)
) read_buffer_fifo(
    .clk_i          (S_AXI_ACLK)               ,
    .rst_ni         (S_AXI_ARESETN)            ,
    .flush_i        (1'b0)                     ,
    .testmode_i     (1'b0)                     ,
    .full_o         (s_rd_buffer_fifo_full)    ,
    .empty_o        (s_rd_buffer_fifo_empty)   ,
    .usage_o        ()                         ,
    .data_i         (s_rd_buffer_fifo_data_in) ,
    .push_i         (s_rd_buffer_fifo_wr_rq)   ,
    .data_o         (s_rd_buffer_fifo_data_out),
    .pop_i          (s_rd_buffer_fifo_rd_rq)
);

fifo_v3 #(
    .FALL_THROUGH   (1'b0)                     ,
    .DATA_WIDTH     (RD_CNTR_FIFO_WIDTH)       ,
    .DEPTH          (RD_CNTR_FIFO_DEPTH)
) read_cnt_fifo(
    .clk_i          (S_AXI_ACLK)               ,
    .rst_ni         (S_AXI_ARESETN)            ,
    .flush_i        (1'b0)                     ,
    .testmode_i     (1'b0)                     ,
    .full_o         (s_rd_cnt_fifo_full)       ,
    .empty_o        (s_rd_cnt_fifo_empty)      ,
    .usage_o        ()                         ,
    .data_i         (s_rd_cnt_fifo_data_in)    ,
    .push_i         (s_rd_cnt_fifo_wr_rq)      ,
    .data_o         (s_rd_cnt_fifo_data_out)   ,
    .pop_i          (s_rd_cnt_fifo_rd_rq)
);

endmodule


