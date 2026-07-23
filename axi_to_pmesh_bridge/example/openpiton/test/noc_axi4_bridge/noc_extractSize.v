// Created by Barcelona Supercomputing Center

`include "define.tmp.h"
`include "noc_axi4_bridge_define.vh"

module noc_extractSize (
  input  wire [`MSG_HEADER_WIDTH         -1:0] header,
  output wire [`MSG_DATA_SIZE_WIDTH      -1:0] size_log,
  output wire [$clog2(`AXI4_DATA_WIDTH/8)-1:0] offset
);
  wire [`PHY_ADDR_WIDTH-1:0] virt_addr = header[`MSG_ADDR];
  wire uncacheable = (header[`MSG_TYPE] == `MSG_TYPE_NC_LOAD_REQ)      ||
                     (header[`MSG_TYPE] == `MSG_TYPE_NC_STORE_REQ)     ||
                     (header[`MSG_TYPE] == `MSG_TYPE_LOAD_NOSHARE_REQ) ||
                     (header[`MSG_TYPE] == `MSG_TYPE_SWAPWB_REQ);
  assign size_log = uncacheable ? header[`MSG_DATA_SIZE] - 1 : $clog2(`AXI4_DATA_WIDTH/8);
  assign offset   = uncacheable ? virt_addr[$clog2(`AXI4_DATA_WIDTH/8)-1:0] : 0;
endmodule
