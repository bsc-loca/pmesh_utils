/* ------------------------------------------------------------------
 * Organization   : Barcelona Supercomputing Center
 * File           : axi_slave_wrapper_pipeline.sv
 * Description    : component of the axi_to_pmesh_bridge which handles 
 *                  AXI write and read transactions from AXI Master
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
 * ON_FLY_WR_NUM              = number of in-flight write requests.
 * BRIDGE_SUPPORT_AXI_AXCACHE = support AXI ARCACHE signal.
 * ------------------------------------------------------------------
 * TODO:
 * ------------------------------------------------------------------
 */

module axi_slave_wrapper_pipeline
    import axi_to_pmesh_bridge_pkg::*;
#(
    parameter          ON_FLY_WR_NUM = 4,
    parameter          ON_FLY_RD_NUM = 4,
    parameter unsigned BRIDGE_SUPPORT_AXI_AXCACHE = 0
)
(
    // Read Addrs FIFO signals
    output wire                          o_rd_addr_fifo_wr_rq ,
    output wire [RD_ADDR_FIFO_WIDTH-1:0] o_rd_addr_fifo_data  ,
    //input  wire                          i_rd_addr_fifo_empty ,
    input  wire                          i_rd_addr_fifo_full  ,

    // Read Data FIFO signals: this fifo should be show ahead
    output wire                          o_rd_data_fifo_rd_rq ,
    input  wire [RD_DATA_FIFO_WIDTH-1:0] i_rd_data_fifo_data  ,
    input  wire                          i_rd_data_fifo_empty ,

    // Write Addrs/Data FIFO signals
    output wire                          o_wr_fifo_wr_rq      ,
    output wire [WR_FIFO_WIDTH-1:0]      o_wr_fifo_data       ,
    //input  wire                          i_wr_fifo_empty      ,
    input  wire                          i_wr_fifo_full       ,

    // Write ACK from NOC Bridge
    input  wire                          i_NOC_WACK           ,  // ACK must be 1 only for 1 cycle

    // AXI SIGNALS
    input  wire                          S_AXI_ACLK           ,
    input  wire                          S_AXI_ARESETN        ,

    // AXI Read Signals
    output wire                          S_AXI_ARREADY        ,
    input  wire [AXI_ADDR_WIDTH-1:0]     S_AXI_ARADDR         ,
    input  wire                          S_AXI_ARVALID        ,
    input  wire [AXI_LEN_WIDTH-1:0]      S_AXI_ARLEN          ,
    input  wire [AXI_SIZE_WIDTH-1:0]     S_AXI_ARSIZE         ,
    input  wire [AXI_ID_WIDTH-1:0]       S_AXI_ARID           ,
    input  wire [AXI_BURST_WIDTH-1:0]    S_AXI_ARBURST        ,
    input  wire                          S_AXI_ARLOCK         ,
    input  wire [AXI_CACHE_WIDTH-1:0]    S_AXI_ARCACHE        ,
    input  wire [AXI_PROT_WIDTH-1:0]     S_AXI_ARPROT         ,
    input  wire [AXI_QOS_WIDTH-1:0]      S_AXI_ARQOS          ,
    input  wire [AXI_REGION_WIDTH-1:0]   S_AXI_ARREGION       ,
    input  wire [AXI_USER_WIDTH-1:0]     S_AXI_ARUSER         ,
    input  wire                          S_AXI_RREADY         ,
    output wire                          S_AXI_RVALID         ,
    output wire [AXI_DATA_WIDTH-1:0]     S_AXI_RDATA          ,
    output wire                          S_AXI_RLAST          ,
    output wire [AXI_USER_WIDTH-1:0]     S_AXI_RUSER          ,
    output wire [AXI_ID_WIDTH-1:0]       S_AXI_RID            ,
    output wire [AXI_RESP_WIDTH-1:0]     S_AXI_RRESP          ,

    // AXI Write Signals
    output wire                          S_AXI_AWREADY        ,
    input  wire [AXI_ADDR_WIDTH-1:0]     S_AXI_AWADDR         ,
    input  wire                          S_AXI_AWVALID        ,
    input  wire [AXI_LEN_WIDTH-1:0]      S_AXI_AWLEN          ,
    input  wire [AXI_SIZE_WIDTH-1:0]     S_AXI_AWSIZE         ,
    input  wire [AXI_ID_WIDTH-1:0]       S_AXI_AWID           ,
    input  wire [AXI_BURST_WIDTH-1:0]    S_AXI_AWBURST        ,
    input  wire                          S_AXI_AWLOCK         ,
    input  wire [AXI_CACHE_WIDTH-1:0]    S_AXI_AWCACHE        ,
    input  wire [AXI_PROT_WIDTH-1:0]     S_AXI_AWPROT         ,
    input  wire [AXI_QOS_WIDTH-1:0]      S_AXI_AWQOS          ,
    input  wire [AXI_REGION_WIDTH-1:0]   S_AXI_AWREGION       ,
    input  wire [AXI_USER_WIDTH-1:0]     S_AXI_AWUSER         ,
    output wire                          S_AXI_WREADY         ,
    input  wire                          S_AXI_WVALID         ,
    input  wire [AXI_DATA_WIDTH-1:0]     S_AXI_WDATA          ,
    input  wire [AXI_WSTRB_WIDTH-1:0]    S_AXI_WSTRB          ,
    input  wire                          S_AXI_WLAST          ,
    input  wire [AXI_USER_WIDTH-1:0]     S_AXI_WUSER          ,
    output wire                          S_AXI_BVALID         ,
    input  wire                          S_AXI_BREADY         ,
    output wire [AXI_ID_WIDTH-1:0]       S_AXI_BID            ,
    output wire [AXI_RESP_WIDTH-1:0]     S_AXI_BRESP          ,
    output wire [AXI_USER_WIDTH-1:0]     S_AXI_BUSER
);

axi_slave_wr_pipeline #(
    .ON_FLY_WR_NUM(ON_FLY_WR_NUM),
    .BRIDGE_SUPPORT_AXI_AXCACHE(BRIDGE_SUPPORT_AXI_AXCACHE)
)
axi_slave_wr(
    .o_fifo_wr_rq      (o_wr_fifo_wr_rq     ),
    .o_fifo_data       (o_wr_fifo_data      ),
    //.i_fifo_empty      (i_wr_fifo_empty     ),
    .i_fifo_full       (i_wr_fifo_full      ),
    .S_AXI_ACLK        (S_AXI_ACLK          ),
    .S_AXI_ARESETN     (S_AXI_ARESETN       ),
    .S_AXI_AWREADY     (S_AXI_AWREADY       ),
    .S_AXI_AWADDR      (S_AXI_AWADDR        ),
    .S_AXI_AWVALID     (S_AXI_AWVALID       ),
    .S_AXI_AWLEN       (S_AXI_AWLEN         ),
    .S_AXI_AWSIZE      (S_AXI_AWSIZE        ),
    .S_AXI_AWID        (S_AXI_AWID          ),
    .S_AXI_AWBURST     (S_AXI_AWBURST       ),
    .S_AXI_AWLOCK      (S_AXI_AWLOCK        ),
    .S_AXI_AWCACHE     (S_AXI_AWCACHE       ),
    .S_AXI_AWPROT      (S_AXI_AWPROT        ),
    .S_AXI_AWQOS       (S_AXI_AWQOS         ),
    .S_AXI_AWREGION    (S_AXI_AWREGION      ),
    .S_AXI_AWUSER      (S_AXI_AWUSER        ),
    .S_AXI_WREADY      (S_AXI_WREADY        ),
    .S_AXI_WVALID      (S_AXI_WVALID        ),
    .S_AXI_WDATA       (S_AXI_WDATA         ),
    .S_AXI_WSTRB       (S_AXI_WSTRB         ),
    .S_AXI_WLAST       (S_AXI_WLAST         ),
    .S_AXI_WUSER       (S_AXI_WUSER         ),
    .S_AXI_BVALID      (S_AXI_BVALID        ),
    .S_AXI_BREADY      (S_AXI_BREADY        ),
    .S_AXI_BID         (S_AXI_BID           ),
    .S_AXI_BRESP       (S_AXI_BRESP         ),
    .S_AXI_BUSER       (S_AXI_BUSER         ),
    .i_NOC_WACK        (i_NOC_WACK          )
);

axi_slave_rd_pipeline #(
    .ON_FLY_RD_NUM(ON_FLY_RD_NUM),
    .BRIDGE_SUPPORT_AXI_AXCACHE(BRIDGE_SUPPORT_AXI_AXCACHE)
)
axi_slave_rd(
    .o_addr_fifo_wr_rq (o_rd_addr_fifo_wr_rq),
    .o_addr_fifo_data  (o_rd_addr_fifo_data ),
    //.i_addr_fifo_empty (i_rd_addr_fifo_empty),
    .i_addr_fifo_full  (i_rd_addr_fifo_full ),
    .o_data_fifo_rd_rq (o_rd_data_fifo_rd_rq),
    .i_data_fifo_data  (i_rd_data_fifo_data ),
    .i_data_fifo_empty (i_rd_data_fifo_empty),
    .S_AXI_ACLK        (S_AXI_ACLK          ),
    .S_AXI_ARESETN     (S_AXI_ARESETN       ),
    .S_AXI_ARREADY     (S_AXI_ARREADY       ),
    .S_AXI_ARADDR      (S_AXI_ARADDR        ),
    .S_AXI_ARVALID     (S_AXI_ARVALID       ),
    .S_AXI_ARLEN       (S_AXI_ARLEN         ),
    .S_AXI_ARSIZE      (S_AXI_ARSIZE        ),
    .S_AXI_ARID        (S_AXI_ARID          ),
    .S_AXI_ARBURST     (S_AXI_ARBURST       ),
    .S_AXI_ARLOCK      (S_AXI_ARLOCK        ),
    .S_AXI_ARCACHE     (S_AXI_ARCACHE       ),
    .S_AXI_ARPROT      (S_AXI_ARPROT        ),
    .S_AXI_ARQOS       (S_AXI_ARQOS         ),
    .S_AXI_ARREGION    (S_AXI_ARREGION      ),
    .S_AXI_ARUSER      (S_AXI_ARUSER        ),
    .S_AXI_RREADY      (S_AXI_RREADY        ),
    .S_AXI_RVALID      (S_AXI_RVALID        ),
    .S_AXI_RDATA       (S_AXI_RDATA         ),
    .S_AXI_RLAST       (S_AXI_RLAST         ),
    .S_AXI_RUSER       (S_AXI_RUSER         ),
    .S_AXI_RID         (S_AXI_RID           ),
    .S_AXI_RRESP       (S_AXI_RRESP         )
);

endmodule


