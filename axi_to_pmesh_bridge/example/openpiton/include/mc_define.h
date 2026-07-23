// Modified by Barcelona Supercomputing Center on March 3rd, 2022
// ========== Copyright Header Begin ============================================
// Copyright (c) 2015 Princeton University
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//     * Redistributions of source code must retain the above copyright
//       notice, this list of conditions and the following disclaimer.
//     * Redistributions in binary form must reproduce the above copyright
//       notice, this list of conditions and the following disclaimer in the
//       documentation and/or other materials provided with the distribution.
//     * Neither the name of Princeton University nor the
//       names of its contributors may be used to endorse or promote products
//       derived from this software without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY PRINCETON UNIVERSITY "AS IS" AND
// ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
// WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL PRINCETON UNIVERSITY BE LIABLE FOR ANY
// DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
// (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
// LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
// ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
// SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
// ========== Copyright Header End ============================================

`define MIG_WR_CMD  3'b000
`define MIG_RD_CMD  3'b001
`define MIG_RMW_CMD  3'b011

`ifdef ALVEO_BOARD
    `define BOARD_MEM_SIZE_MB       8192 // Valid for HBM and DDR4
    `define WORDS_PER_BURST         8
    `define WORD_SIZE               8 // in bytes
    `define MIG_APP_ADDR_WIDTH      31
    `define MIG_APP_CMD_WIDTH       3
    `define MIG_APP_DATA_WIDTH      512
    `define MIG_APP_MASK_WIDTH      64

    `define DDR3_DQ_WIDTH           72
    `define DDR3_DQS_WIDTH          18
    `define DDR3_ADDR_WIDTH         17
    `define DDR3_BA_WIDTH           2
    `define DDR3_DM_WIDTH           8
    `define DDR3_CK_WIDTH           1
    `define DDR3_CKE_WIDTH          1
    `define DDR3_CS_WIDTH           1
    `define DDR3_BG_WIDTH           2
    `define DDR3_ODT_WIDTH          1
`else
    `define BOARD_MEM_SIZE_MB       1024
    `define MIG_APP_ADDR_WIDTH      29
    `define WORDS_PER_BURST         8
    `define WORD_SIZE               8 // in bytes
    `define MIG_APP_CMD_WIDTH       3
    `define MIG_APP_DATA_WIDTH      512
    `define MIG_APP_MASK_WIDTH      64

    `define DDR3_DQ_WIDTH           64
    `define DDR3_DQS_WIDTH          8
    `define DDR3_ADDR_WIDTH         15
    `define DDR3_BA_WIDTH           3
    `define DDR3_DM_WIDTH           8
    `define DDR3_CK_WIDTH           1
    `define DDR3_CKE_WIDTH          1
    `define DDR3_CS_WIDTH           1
    `define DDR3_ODT_WIDTH          1
`endif