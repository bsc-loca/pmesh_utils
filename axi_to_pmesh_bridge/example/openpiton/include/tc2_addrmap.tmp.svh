
// /home/lplana/devel/zetta-tc2/piton/verif/env/manycore/devices_zetta-tc2.xml
localparam int         NIOSections          = 2;
localparam logic[2-1:0][39:0] InitIOBase       = {40'h0, 40'h8800000000};
localparam logic[2-1:0][39:0] InitIOEnd        = {40'h8000000000, 40'hFFFFFFFFFF};
localparam int         NMappedSections      = 1;
localparam logic[1-1:0][39:0] InitMappedBase   = {40'h0};
localparam logic[1-1:0][39:0] InitMappedEnd    = {40'hFFFFFFFFFF};
localparam logic[39:0] InitBROMBase         = 40'h100000000;
localparam logic[39:0] InitBROMEnd          = 40'h100010000;
localparam logic[39:0] InitDMBase           = 40'hE000580000;
localparam WriteCoalescingEn = 1'b1;
localparam WriteCoalescingTh = 32'd2;
