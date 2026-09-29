// ----------------------------------------------------------------------------
// Copyright (c) 2020-2025 RVX contributors
//
// This work is licensed under the MIT License, see LICENSE file for details.
// SPDX-License-Identifier: MIT
// ----------------------------------------------------------------------------

module rvx_gpio_wb #(

  parameter GPIO_WIDTH = 32

  )(

  // Global signals

  input   wire                  clock,
  input   wire                  reset,

  // IO interface

  input  wire   [4:0]           rw_address,
  output reg    [31:0]          read_data,
  input  wire                   read_request,
  output reg                    read_response,
  input  wire   [31:0]          write_data,
  input  wire   [3:0]           write_strobe,
  input  wire                   write_request,
  output reg                    write_response,

  // GPIO signals

  input  wire   [GPIO_WIDTH-1:0]  gpio_input,
  output reg    [GPIO_WIDTH-1:0]  gpio_oe,
  output reg    [GPIO_WIDTH-1:0]  gpio_output

  );

  // Register Map
  localparam REG_INPUT  = 5'h00;  // GPIO Input register (read-only)
  localparam REG_OE     = 5'h04;  // GPIO Output Enable register
  localparam REG_OUTPUT = 5'h08;  // GPIO Output register

  wire valid_write_request = write_request == 1'b1 && &write_strobe == 1'b1;

  // Read/Write response generation
  always @(posedge clock) begin
    if (reset) begin
      read_response  <= 1'b0;
      write_response <= 1'b0;
    end
    else begin
      read_response  <= read_request;
      write_response <= write_request;
    end
  end

  // Read data multiplexer
  always @(posedge clock) begin
    if (reset)
      read_data <= 32'h00000000;
    else if (read_request == 1'b1) begin
      case (rw_address)
        REG_INPUT:  read_data <= gpio_input;
        REG_OE:     read_data <= gpio_oe;
        REG_OUTPUT: read_data <= gpio_output;
        default:    read_data <= 32'h00000000;
      endcase
    end
    else
      read_data <= 32'h00000000;
  end

  // GPIO Output Enable register
  always @(posedge clock) begin
    if (reset)
      gpio_oe <= {GPIO_WIDTH{1'b0}};
    else if (rw_address == REG_OE && valid_write_request == 1'b1)
      gpio_oe <= write_data[GPIO_WIDTH-1:0];
    else
      gpio_oe <= gpio_oe;
  end

  // GPIO Output register
  always @(posedge clock) begin
    if (reset)
      gpio_output <= {GPIO_WIDTH{1'b0}};
    else if (rw_address == REG_OUTPUT && valid_write_request == 1'b1)
      gpio_output <= write_data[GPIO_WIDTH-1:0];
    else
      gpio_output <= gpio_output;
  end

endmodule
