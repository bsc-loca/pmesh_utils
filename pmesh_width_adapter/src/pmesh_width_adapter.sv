/* ------------------------------------------------------------------
 * Organization   : Barcelona Supercomputing Center
 * File           : pmesh_width_adapter.sv
 * Description    : module that receives a PMESH message of ADAPT_INPUT_NOC_BITS
 *                  width and outputs the same message with ADAPT_OUTPUT_NOC_BITS
 *                  width.
 * ------------------------------------------------------------------
 * COPYRIGHT
 *  Copyright (c) Barcelona Supercomputing Center, 2026.
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
 *  0.0.1      | Manjunath - manjunath.kalmath@bsc.es   | initial code version
 *             | lap - luis.plana@bsc.es                | initial code version
 * ------------------------------------------------------------------
 * PARAMETERS:
 * ADAPT_INPUT_NOC_BITS   = width, in bits, of the input PMESH NoC channel.
 * ADAPT_OUTPUT_NOC_BITS  = width, in bits, of theoutput PMESH NoC channel.
 * ADAPT_REGISTER_BYPASS  = introduce a register in the bypass - can help closing time.
 * ------------------------------------------------------------------
 * NOTES:
 * - the adapter is bypassed if the input and output witdhs are the same.
 *      the bypass can be combinatorial or registered.
 * - the adapter introduces latency, given that the message is rebuilt
 *      internally from input flits and then transmitted on the output.
 * - the adapter may apply backpressure to the input PMESH NoC channel.
 *      This happens when the output channel is narrower than the input one.
 * ------------------------------------------------------------------
 * TODO:
 * ------------------------------------------------------------------
 */

`include "define.tmp.h"

module pmesh_width_adapter
#(
  parameter unsigned ADAPT_INPUT_NOC_BITS  = 64,
  parameter unsigned ADAPT_OUTPUT_NOC_BITS = 64,
  parameter unsigned ADAPT_REGISTER_BYPASS = 0
)
(
  input  logic                              clk,
  input  logic                              rst_n,

  //NoC Interfaces
  //from the bridge
  input  logic                              input_noc_valid_in,
  input  logic  [ADAPT_INPUT_NOC_BITS -1:0] input_noc_data_in,
  output logic                              input_noc_ready_out,
  //to the bridge
  output logic                              output_noc_valid_out,
  output logic [ADAPT_OUTPUT_NOC_BITS -1:0] output_noc_data_out,
  input  logic                              output_noc_ready_in
);
  // ----------------------------------------------------------------
  // constants
  // ----------------------------------------------------------------
  localparam unsigned MSG_LEN_LOW_IDX           = 22;  // PMESH parameter
  localparam unsigned MSG_LEN_HI_IDX            = 29;  // PMESH parameter
  
  localparam unsigned MSG_MAX_HDR_BITS          = `MSG_HEADER_WIDTH;  // PMESH parameter
  localparam unsigned MSG_MAX_DATA_BITS         = 512;  // system parameter - usually a cache line
  localparam unsigned MSG_MAX_BITS              = MSG_MAX_HDR_BITS + MSG_MAX_DATA_BITS;
  localparam unsigned MSG_BITS_CNT_BITS         = $clog2 (MSG_MAX_BITS - 1) + 1;

  // PMESH messages are formed by fixed-size FIELDS (usually 64 bits)
  localparam unsigned MSG_FIELD_BITS            = `DATA_WIDTH;  // PMESH parameter
  localparam unsigned MSG_MAX_HDR_FIELDS        = MSG_MAX_DATA_BITS / MSG_FIELD_BITS;
  localparam unsigned MSG_MAX_DATA_FIELDS       = MSG_MAX_DATA_BITS / MSG_FIELD_BITS;

  // need to count message fields
  localparam unsigned MSG_MAX_FIELDS            = MSG_MAX_HDR_FIELDS + MSG_MAX_DATA_FIELDS;
  localparam unsigned MSG_FIELD_CNT_BITS        = $clog2 (MSG_MAX_FIELDS);

  // PMESH messages are split in one or more FLITS for transmission - depending on the NoC width
  // need to count message flits
  localparam unsigned MSG_MAX_FLITS             = MSG_MAX_FIELDS;  // maximises when one field per PMESH flit
  localparam unsigned MSG_FLIT_CNT_BITS         = $clog2 (MSG_MAX_FLITS);

  localparam unsigned INPUT_FIELDS_PER_FLIT     = ADAPT_INPUT_NOC_BITS  / MSG_FIELD_BITS;
  localparam unsigned OUTPUT_FIELDS_PER_FLIT    = ADAPT_OUTPUT_NOC_BITS / MSG_FIELD_BITS;

  // bypass adapter if input and output widths are the same
  localparam unsigned ADAPT_BYPASS              = (ADAPT_INPUT_NOC_BITS == ADAPT_OUTPUT_NOC_BITS);
  // ----------------------------------------------------------------

  // ----------------------------------------------------------------
  // types
  // ----------------------------------------------------------------
  typedef logic           [MSG_MAX_BITS - 1:0] message_t;
  typedef logic   [ADAPT_INPUT_NOC_BITS - 1:0] iflit_t;
  typedef logic  [ADAPT_OUTPUT_NOC_BITS - 1:0] oflit_t;

  typedef logic      [MSG_FLIT_CNT_BITS - 1:0] flit_cnt_t;
  typedef logic      [MSG_BITS_CNT_BITS - 1:0] flit_ptr_t;

  typedef logic     [MSG_FIELD_CNT_BITS - 1:0] fld_cnt_t;

   // task state
  typedef enum logic {
    TASK_IDLE,  // output not busy or input not valid
    TASK_PARK   // waiting for busy output
  } task_state_t;
  // ----------------------------------------------------------------

  generate

    if (ADAPT_BYPASS) begin : bypass

      if (!ADAPT_REGISTER_BYPASS) begin : bypass_comb

        // bypass input to output combinatorialy
        always_comb begin
          output_noc_valid_out = input_noc_valid_in;
          output_noc_data_out  = input_noc_data_in;
          input_noc_ready_out  = output_noc_ready_in;
        end

      end else begin : bypass_reg

        // bypass input to output through register
        logic          out_busy;

        task_state_t   state, state_nxt;

        iflit_t        flit_park;

        // indicate readiness to input
        always_ff @ (posedge clk or negedge rst_n) begin
          if (rst_n == 0) begin
            input_noc_ready_out <= 1'b1;
          end else begin
            if (state_nxt == TASK_PARK) begin
              input_noc_ready_out <= 1'b0;
            end else begin
              input_noc_ready_out <= 1'b1;
            end
          end
        end

        // output state
        always_comb begin
          out_busy = (output_noc_valid_out && !output_noc_ready_in);
        end

        // bypass state
        always_ff @ (posedge clk or negedge rst_n) begin
          if (rst_n == 0) begin
            state <= TASK_IDLE;
          end else begin
            state <= state_nxt;
          end
        end

        always_comb begin
          case (state)
            TASK_IDLE: begin
              if (input_noc_valid_in && out_busy) begin
                state_nxt = TASK_PARK;
              end else begin
                state_nxt = TASK_IDLE;
              end
            end

            TASK_PARK: begin
              if (!out_busy) begin
                state_nxt = TASK_IDLE;
              end else begin
                state_nxt = TASK_PARK;
              end
            end

            default:   begin  // should never happen
              state_nxt = TASK_IDLE;
            end
          endcase
        end

        // park input flit if output is busy
        always_ff @ (posedge clk or negedge rst_n) begin
          if (rst_n == 0) begin
            flit_park <= 0;
          end else begin
            if (out_busy) begin
              if (input_noc_valid_in && (state == TASK_IDLE)) begin
                flit_park <= input_noc_data_in;
              end
            end
          end
        end

        // send input flit to output NoC
        always_ff @ (posedge clk or negedge rst_n) begin
          if (rst_n == 0) begin
            output_noc_data_out  <= 0;
          end else begin
            // send out only if output not busy
            if (!out_busy) begin
              if (state == TASK_PARK) begin
                // parked flit - send
                output_noc_data_out <= flit_park;
              end else if (input_noc_valid_in) begin
                // new flit - send
                output_noc_data_out <= input_noc_data_in;
              end
            end
          end
        end

        // indicate output validity
        always_ff @ (posedge clk or negedge rst_n) begin
          if (rst_n == 0) begin
            output_noc_valid_out <= 1'b0;
          end else begin
            // update valid only if output not busy
            if (!out_busy) begin
              output_noc_valid_out <= (input_noc_valid_in || (state == TASK_PARK));
            end
          end
        end

      end

    end else begin : no_bypass

      // rebuild incoming message from input flits and send out in output flits
      message_t  message;

      // message handshake between input and output interfaces
      logic      message_valid;
      logic      message_ready;
      logic      message_busy;


      // ----------------------------------------------------------------
      // input interface
      // ----------------------------------------------------------------
      // receive and rebuild input message from flits

      fld_cnt_t  in_remaining_flds;
      fld_cnt_t  in_msg_len;

      iflit_t    iflit_park;
      flit_cnt_t iflit_cnt;
      flit_ptr_t iflit_ptr;
      logic      iflit_first;
      logic      iflit_last;
      logic      iflit_store;

      task_state_t state, state_nxt;

      // indicate readiness to input
      always_ff @ (posedge clk or negedge rst_n) begin
        if (rst_n == 0) begin
          input_noc_ready_out <= 1'b1;
        end else begin
          if (state_nxt == TASK_PARK) begin
            input_noc_ready_out <= 1'b0;
          end else begin
            input_noc_ready_out <= 1'b1;
          end
        end
      end

      // may need to wait if message register is busy
      always_comb begin
        message_busy = message_valid && !message_ready;
      end

      // get message length from correct source - input or parked flit
      //NOTE: in PMESH length in the message is really length - 1
      always_comb begin
        if (state == TASK_PARK) begin
          in_msg_len = iflit_park[MSG_LEN_LOW_IDX +: MSG_FIELD_CNT_BITS];
        end else begin
          in_msg_len = input_noc_data_in[MSG_LEN_LOW_IDX +: MSG_FIELD_CNT_BITS];
        end
      end

      // keep state
      always_ff @ (posedge clk or negedge rst_n) begin
        if (rst_n == 0) begin
          state <= TASK_IDLE;
        end else begin
          state <= state_nxt;
        end
      end

      always_comb begin
        case (state)
          TASK_IDLE: begin
            if (input_noc_valid_in && message_busy) begin
              state_nxt = TASK_PARK;
            end else begin
              state_nxt = TASK_IDLE;
            end
          end

          TASK_PARK: begin
            if (!message_busy) begin
              state_nxt = TASK_IDLE;
            end else begin
              state_nxt = TASK_PARK;
            end
          end

          default:   begin  // should never happen
            state_nxt = TASK_IDLE;
          end
        endcase
      end

      // conditions to accept input flit and store it
      always_comb begin
        iflit_store = (!message_busy && (input_noc_valid_in || (state == TASK_PARK)));
      end

      // input flit count and pointer
      always_ff @ (posedge clk or negedge rst_n) begin
        if (rst_n == 0) begin
          iflit_cnt <= 0;
          iflit_ptr <= 0;
        end else begin
          // store flitsend out only if not busy
            if (iflit_store) begin
              // flit received - count
              iflit_cnt <= (iflit_last ? 0 : (iflit_cnt + 1));
              iflit_ptr <= (iflit_last ? 0 : (iflit_ptr + ADAPT_INPUT_NOC_BITS));
            end
        end
      end

      // is this the first flit in a message?
      always_comb begin
        iflit_first = (iflit_cnt == 0);
      end

      // is this the last flit in a message?
      always_comb begin
        iflit_last = iflit_first ? (in_msg_len < INPUT_FIELDS_PER_FLIT) : (in_remaining_flds < INPUT_FIELDS_PER_FLIT);
      end

      // keep track of the number of fields yet to be received
      //NOTE: if fewer than INPUT_FIELDS_PER_FLIT then this is the last flit.
      always_ff @ (posedge clk or negedge rst_n) begin
        if (rst_n == 0) begin
          in_remaining_flds <= 0;
        end else begin
            if (iflit_store) begin
              if (iflit_first) begin
                in_remaining_flds <= in_msg_len - INPUT_FIELDS_PER_FLIT;
              end else begin
                in_remaining_flds <= in_remaining_flds - INPUT_FIELDS_PER_FLIT;
              end
            end
        end
      end

      // park input flit if output is busy
      always_ff @ (posedge clk or negedge rst_n) begin
        if (rst_n == 0) begin
          iflit_park <= 0;
        end else begin
          if (message_busy) begin
            if (input_noc_valid_in && (state == TASK_IDLE)) begin
              iflit_park <= input_noc_data_in;
            end
          end
        end
      end

      // append new flit to message
      always_ff @ (posedge clk or negedge rst_n) begin
        if (rst_n == 0) begin
          message <= 0;
        end else begin
          if (iflit_store) begin
            if (state == TASK_PARK) begin
              message[iflit_ptr +: ADAPT_INPUT_NOC_BITS] <= iflit_park;
            end else begin
              message[iflit_ptr +: ADAPT_INPUT_NOC_BITS] <= input_noc_data_in;
            end
          end
        end
      end

      // indicate message validity to output
      always_ff @ (posedge clk or negedge rst_n) begin
        if (rst_n == 0) begin
          message_valid <= 0;
        end else begin
          if (!message_busy) begin
            message_valid <= (iflit_store && iflit_last);
          end
        end
      end

      // ----------------------------------------------------------------
      // output interface
      // ----------------------------------------------------------------
      // send message - may need to split in flits!
      logic      out_busy;

      fld_cnt_t  out_remaining_flds;
      fld_cnt_t  out_msg_len;

      flit_cnt_t oflit_cnt;
      flit_ptr_t oflit_ptr;
      logic      oflit_first;
      logic      oflit_last;

      // output NoC status
      always_comb begin
        out_busy = (output_noc_valid_out && !output_noc_ready_in);
      end

      // report message buffer readinness to input interface
      always_comb begin
        message_ready = (!out_busy && oflit_last);
      end

      // message length - in a fixed position in the message
      //NOTE: in PMESH length in the message is really length - 1
      always_comb begin
        out_msg_len = message[MSG_LEN_LOW_IDX +: MSG_FIELD_CNT_BITS];
      end

      // output flit count and pointer
      always_ff @ (posedge clk or negedge rst_n) begin
        if (rst_n == 0) begin
          oflit_cnt <= 0;
          oflit_ptr <= 0;
        end else begin
          // send out only if not busy
          if (!out_busy) begin
            if (message_valid) begin
              // flit sent - count
              oflit_cnt <= (oflit_last ? 0 : (oflit_cnt + 1));
              oflit_ptr <= (oflit_last ? 0 : (oflit_ptr + ADAPT_OUTPUT_NOC_BITS));
            end
          end
        end
      end

      // is this the first flit in a message?
      always_comb begin
        oflit_first = (oflit_cnt == 0);
      end

      // is this the last flit in a message?
      always_comb begin
        oflit_last = oflit_first ? (out_msg_len < OUTPUT_FIELDS_PER_FLIT) : (out_remaining_flds < OUTPUT_FIELDS_PER_FLIT);
      end

      // keep track of the number of fields yet to be transmitted
      //NOTE: if fewer than OUTPUT_FIELDS_PER_FLIT then this is the last flit.
      always_ff @ (posedge clk or negedge rst_n) begin
        if (rst_n == 0) begin
          out_remaining_flds <= 0;
        end else begin
          if (!out_busy) begin
            if (message_valid) begin
              if (oflit_first) begin
                out_remaining_flds <= out_msg_len - OUTPUT_FIELDS_PER_FLIT;
              end else begin
                out_remaining_flds <= out_remaining_flds - OUTPUT_FIELDS_PER_FLIT;
              end
            end
          end
        end
      end

      // send message flit to output NoC
      always_ff @ (posedge clk or negedge rst_n) begin
        if (rst_n == 0) begin
          output_noc_valid_out <= 1'b0;
          output_noc_data_out  <= 0;
        end else begin
          // send out only if not busy
          if (!out_busy) begin
            if (message_valid) begin
              // new message ready - send flit out
              output_noc_valid_out <= 1'b1;
              output_noc_data_out  <= message[oflit_ptr +: ADAPT_OUTPUT_NOC_BITS];
            end else begin
              // no new message - indicate not valid
              output_noc_valid_out <= 1'b0;
            end
          end
        end
      end
    end

  endgenerate
  // ----------------------------------------------------------------
endmodule
