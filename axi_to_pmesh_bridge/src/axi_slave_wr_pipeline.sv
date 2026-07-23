/* ------------------------------------------------------------------
 * Organization   : Barcelona Supercomputing Center
 * File           : axi_slave_wr_pipeline.sv
 * Description    : component of the axi_slave_wrapper_pipeline module 
 *                  and part of axi_to_pmesh_bridge which handles 
 *                  AXI write transactions from AXI Master
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
 * ON_FLY_WR_NUM              = number of in-flight write requests.
 * BRIDGE_SUPPORT_AXI_AXCACHE = support AXI AWCACHE signal.
 * ------------------------------------------------------------------
 * TODO:
 * ------------------------------------------------------------------
 */

module axi_slave_wr_pipeline
    import axi_to_pmesh_bridge_pkg::*;
#(
    parameter          ON_FLY_WR_NUM = 4,
    parameter unsigned BRIDGE_SUPPORT_AXI_AXCACHE = 0
)
(
    // Write FIFO signals
    output wire                         o_fifo_wr_rq    ,
    output wire  [WR_FIFO_WIDTH-1:0]    o_fifo_data     ,
    //input  wire                         i_fifo_empty    ,
    input  wire                         i_fifo_full     ,

    // AXI Write Signals
    input  wire                         S_AXI_ACLK      ,
    input  wire                         S_AXI_ARESETN   ,

    // Main write addr signals ----------------------
    output reg                          S_AXI_AWREADY   ,
    input  wire [AXI_ADDR_WIDTH-1:0]    S_AXI_AWADDR    ,
    input  wire                         S_AXI_AWVALID   ,
    input  wire [AXI_LEN_WIDTH-1:0]     S_AXI_AWLEN     ,
    input  wire [AXI_SIZE_WIDTH-1:0]    S_AXI_AWSIZE    ,
    // ----------------------------------------------

    input  wire  [AXI_ID_WIDTH-1:0]     S_AXI_AWID      ,
    input  wire  [AXI_BURST_WIDTH-1:0]  S_AXI_AWBURST   ,
    input  wire                         S_AXI_AWLOCK    ,
    input  wire  [AXI_CACHE_WIDTH-1:0]  S_AXI_AWCACHE   ,
    input  wire  [AXI_PROT_WIDTH-1:0]   S_AXI_AWPROT    ,
    input  wire  [AXI_QOS_WIDTH-1:0]    S_AXI_AWQOS     ,
    input  wire  [AXI_REGION_WIDTH-1:0] S_AXI_AWREGION  ,
    input  wire  [AXI_USER_WIDTH-1:0]   S_AXI_AWUSER    ,

    // Main write data signals ----------------------
    output wire                         S_AXI_WREADY    ,
    input  wire                         S_AXI_WVALID    ,
    input  wire  [AXI_DATA_WIDTH-1:0]   S_AXI_WDATA     ,
    input  wire  [AXI_WSTRB_WIDTH-1:0]  S_AXI_WSTRB     ,
    input  wire                         S_AXI_WLAST     ,
    input  wire  [AXI_USER_WIDTH-1:0]   S_AXI_WUSER    ,

    output reg                          S_AXI_BVALID    ,
    input  wire                         S_AXI_BREADY    ,
    // ----------------------------------------------

    output reg   [AXI_ID_WIDTH-1:0]     S_AXI_BID       ,
    output wire  [AXI_RESP_WIDTH-1:0]   S_AXI_BRESP     ,
    output wire  [AXI_USER_WIDTH-1:0]   S_AXI_BUSER     ,

    input  wire                         i_NOC_WACK      // ACK must be 1 only for 1 cycle
);

localparam ON_FLY_WR_NUM_WIDTH   = (ON_FLY_WR_NUM > 1) ? $clog2 (ON_FLY_WR_NUM) : 1;
localparam AXI_BYTE_WIDTH = AXI_DATA_WIDTH/8;

typedef enum {
    ST_IDLE,
    ST_WR_DATA,
    ST_FINAL
} states_t;

states_t                        state;
reg  [AXI_LEN_WIDTH-1:0]        s_noc_ack_cnt [ON_FLY_WR_NUM-1:0];
reg  [AXI_ID_WIDTH-1:0]         s_wid [ON_FLY_WR_NUM-1:0];
reg                             s_on_fly_id_busy [ON_FLY_WR_NUM-1:0];
reg                             s_bvalid [ON_FLY_WR_NUM-1:0];
reg  [ON_FLY_WR_NUM_WIDTH-1:0]  s_wr_rq_id;
reg  [ON_FLY_WR_NUM_WIDTH-1:0]  s_wr_ack_id;
reg  [ON_FLY_WR_NUM_WIDTH-1:0]  s_bvalid_id;
reg  [AXI_LEN_WIDTH:0]          s_N;
reg  [AXI_SIZE_WIDTH-1:0]       s_axi_awsize_reg;
reg  [7:0]                      s_size;
reg  [AXI_ADDR_WIDTH-1:0]       s_start_addr;
wire [AXI_ADDR_WIDTH-1:0]       s_addr_wr;
reg  [AXI_SIZE_WIDTH-1:0]       s_size_wr;
wire [AXI_ADDR_WIDTH-1:0]       s_addr_aligned;
wire [AXI_ADDR_WIDTH-1:0]       s_addr_N;
wire [AXI_ADDR_WIDTH-1:0]       s_addr_N_DW_align;
wire [AXI_ADDR_WIDTH-1:0]       s_addr_1_DW_align;
wire [AXI_BYTE_WIDTH-1:0]       s_lower_limit_1;
wire [AXI_BYTE_WIDTH-1:0]       s_upper_limit_1;
wire [AXI_BYTE_WIDTH-1:0]       s_lower_limit_N;
wire [AXI_BYTE_WIDTH-1:0]       s_upper_limit_N;
wire [AXI_BYTE_WIDTH-1:0]       s_lower_limit;
wire [AXI_BYTE_WIDTH-1:0]       s_upper_limit;
wire [AXI_WSTRB_WIDTH:0]        s_mask_1;
wire [AXI_WSTRB_WIDTH-1:0]      s_mask_2;
wire [AXI_WSTRB_WIDTH-1:0]      s_mask;
wire [AXI_WSTRB_WIDTH-1:0]      s_wstrb;
reg                             s_reading_en;

logic                           s_non_cache;

assign S_AXI_BRESP = 0;
assign S_AXI_BUSER = 0;

// ==================== AXI Addr calculation based on AMBA AXI protocol =======================================
// This equation determines the address of the first transfer in a burst:
// Start_Addr
//
// Aligned_Addr = INT(Start_Addr / Size)* Size
//
// this equation determines the address of any transfer after the first transfer in a burst:
// Address_N = Aligned_Addr + (N - 1)* Size
//
// These equations determine the byte lanes to use for the first transfer in a burst:
// Lower_Byte_Lane = Start_Addr             - (INT(Start_Addr/Data_Bytes)* Data_Bytes)
// Upper_Byte_Lane = Aligned_Addr + (Size-1)- (INT(Start_Addr/Data_Bytes)* Data_Bytes)
//
// These equations determine the byte lanes to use for all transfers after the first transfer in a burst:
// Lower_Byte_Lane = Address_N - (INT(Address_N / Data_Bytes)* Data_Bytes)
// Upper_Byte_Lane = Lower_Byte_Lane + Size - 1
// =============================================================================================================



assign s_addr_aligned    = ((s_start_addr >> s_axi_awsize_reg) << s_axi_awsize_reg);
assign s_addr_N          = (s_addr_aligned + ((s_N - 1) << s_axi_awsize_reg)); //N starts from 1
assign s_addr_1_DW_align = ((s_start_addr >> LOG2_AXI_DATA_BYTES) << LOG2_AXI_DATA_BYTES);
assign s_addr_N_DW_align = ((s_addr_N >> LOG2_AXI_DATA_BYTES) << LOG2_AXI_DATA_BYTES);

assign s_lower_limit_1 = (LOG2_AXI_DATA_BYTES == 0) ? {AXI_BYTE_WIDTH{1'b0}} : {{AXI_BYTE_WIDTH-LOG2_AXI_DATA_BYTES{1'b0}}, s_start_addr[LOG2_AXI_DATA_BYTES-1:0]};
assign s_upper_limit_1 = s_addr_aligned[LOG2_AXI_DATA_BYTES-1:0] + (s_size-1);
assign s_lower_limit_N = (LOG2_AXI_DATA_BYTES == 0) ? {AXI_BYTE_WIDTH{1'b0}} : {{AXI_BYTE_WIDTH-LOG2_AXI_DATA_BYTES{1'b0}}, s_addr_N[LOG2_AXI_DATA_BYTES-1:0]};
assign s_upper_limit_N = s_lower_limit_N + (s_size-1);
assign s_lower_limit   = (s_N > 1) ? s_lower_limit_N : s_lower_limit_1;
assign s_upper_limit   = (s_N > 1) ? s_upper_limit_N : s_upper_limit_1;

//assign s_mask    = ((1 << (s_upper_limit + 1)) - 1) & ~((1 << s_lower_limit) - 1);
assign s_mask_1 = (1 << (s_upper_limit + 1)) - 1;
assign s_mask_2 = ~((1 << s_lower_limit) - 1);
assign s_mask = s_mask_1[AXI_WSTRB_WIDTH-1:0] & s_mask_2;
    
assign s_wstrb   = s_mask & S_AXI_WSTRB;
assign s_addr_wr = (s_N > 1) ? s_addr_N_DW_align : s_addr_1_DW_align;
assign s_size_wr = s_axi_awsize_reg;

always_ff @(posedge S_AXI_ACLK) begin
    if (!S_AXI_ARESETN)
    begin
        state               <= ST_IDLE;
        S_AXI_AWREADY       <= 0;
        s_reading_en        <= 0;
        //S_AXI_BID           <= 0;
        s_N                 <= 1;
        s_start_addr        <= 0;
        s_size              <= 0;
        s_axi_awsize_reg    <= 0;
    end
    else
    begin

        case(state)
            ST_IDLE: begin
                if ((~i_fifo_full) && (s_on_fly_id_busy[s_wr_rq_id] == 0)) begin
                    S_AXI_AWREADY       <= 1'b1;
                    if (S_AXI_AWVALID) begin
                        if (S_AXI_AWREADY) begin
                            S_AXI_AWREADY   <= 1'b0;
                        end
                        s_size              <= 1 << S_AXI_AWSIZE; // BURST is only incremental for now
                        s_axi_awsize_reg    <= S_AXI_AWSIZE;
                        s_N                 <= 1;
                        s_start_addr        <= S_AXI_AWADDR;
                        //S_AXI_BID           <= S_AXI_AWID;                       
                        state               <= ST_WR_DATA;
                        s_reading_en        <= 1'b1;
                    end
                end
            end
            ST_WR_DATA: begin
                S_AXI_AWREADY           <= 1'b0;
                if (S_AXI_WVALID && S_AXI_WREADY) begin
                    if (S_AXI_WLAST) begin
                        state           <= ST_IDLE;
                        s_reading_en    <= 1'b0;
                    end
                    s_N                 <= s_N + 1;
                end
            end
            default: begin
                state <= ST_IDLE;
            end
        endcase

    end
end

always_ff @(posedge S_AXI_ACLK) begin
    if (!S_AXI_ARESETN)
    begin
        integer i;
        for (i = 0; i < ON_FLY_WR_NUM; i = i + 1) begin : init_gen
            s_noc_ack_cnt[i]    <= 0;
            s_on_fly_id_busy[i] <= 0;
            s_bvalid[i]         <= 0;
            s_wid[i]            <= 0;
        end
        S_AXI_BVALID            <= 0;
        S_AXI_BID               <= 0;
        s_wr_rq_id              <= 0;
        s_wr_ack_id             <= 0;
        s_bvalid_id             <= 0;
    end
    else
    begin
        if ((state == ST_IDLE) && (~i_fifo_full) && S_AXI_AWVALID) begin
            if (s_on_fly_id_busy[s_wr_rq_id] == 0) begin
                s_noc_ack_cnt[s_wr_rq_id]      <= S_AXI_AWLEN;
                s_wid[s_wr_rq_id]              <= S_AXI_AWID;
                s_on_fly_id_busy[s_wr_rq_id]   <= 1;
                if (s_wr_rq_id == (ON_FLY_WR_NUM - 1)) begin
                    s_wr_rq_id  <= 0;
                end else begin
                    s_wr_rq_id  <= s_wr_rq_id + 1;
                end
            end
        end

                
        if ((s_bvalid[s_bvalid_id]) || ((s_bvalid_id == s_wr_ack_id) && (i_NOC_WACK) && (s_noc_ack_cnt[s_bvalid_id] == 0))) begin
            S_AXI_BID      <= s_wid[s_bvalid_id];
            S_AXI_BVALID   <= 1;
            if (S_AXI_BREADY && S_AXI_BVALID) begin
                S_AXI_BVALID                  <= 0;
                s_bvalid[s_bvalid_id]         <= 0;
                s_on_fly_id_busy[s_bvalid_id] <= 0;
                if (s_bvalid_id == (ON_FLY_WR_NUM - 1)) begin
                    s_bvalid_id <= 0;
                    if (s_bvalid[0] || ((i_NOC_WACK) && (s_noc_ack_cnt[0] == 0))) begin
                        S_AXI_BVALID  <= 1;
                        S_AXI_BID     <= s_wid[0];
                    end
                end else begin
                    s_bvalid_id <= s_bvalid_id + 1;
                    if (s_bvalid[s_bvalid_id + 1]  || ((i_NOC_WACK) && (s_noc_ack_cnt[s_bvalid_id + 1] == 0))) begin
                        S_AXI_BVALID  <= 1;
                        S_AXI_BID     <= s_wid[s_bvalid_id + 1];
                    end
                end   
            end
        end 
            
        if (i_NOC_WACK) begin
            if (s_noc_ack_cnt[s_wr_ack_id] == 0) begin
                s_bvalid[s_wr_ack_id] <= 1;
                if (s_wr_ack_id == (ON_FLY_WR_NUM - 1)) begin
                    s_wr_ack_id <= 0;
                end else begin
                    s_wr_ack_id <= s_wr_ack_id + 1;
                end
            end else begin
                s_noc_ack_cnt[s_wr_ack_id] <= s_noc_ack_cnt[s_wr_ack_id] - 1;
            end
        end
                                
    end
end

generate
    if (BRIDGE_SUPPORT_AXI_AXCACHE) begin : awcache_support_gen
        always_ff @(posedge S_AXI_ACLK) begin
            if (!S_AXI_ARESETN)
            begin
                s_non_cache <= 0;
            end
            else
            begin
                if ((state == ST_IDLE) && (~i_fifo_full) && (s_on_fly_id_busy[s_wr_rq_id] == 0) && S_AXI_AWVALID) begin
                    s_non_cache <= (S_AXI_AWCACHE[3:2] == 2'b00);
                end
            end
        end
    end else begin : no_awcache_support_gen
        always_comb begin
            s_non_cache = 0;
        end
    end
endgenerate

assign S_AXI_WREADY = ~i_fifo_full & s_reading_en;
assign o_fifo_wr_rq = S_AXI_WREADY & S_AXI_WVALID;
assign o_fifo_data  = {s_addr_wr, S_AXI_WDATA, s_size_wr, s_wstrb, s_non_cache};

endmodule


