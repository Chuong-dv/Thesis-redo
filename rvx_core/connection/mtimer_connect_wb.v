// ----------------------------------------------------------------------------
// RVX MTIMER Wishbone Connection
// ----------------------------------------------------------------------------
// This module connects the Wishbone bus signals to the rvx_mtimer_wb peripheral.
// ----------------------------------------------------------------------------

module mtimer_connect_wb (
  // Global signals
  input  wire         clk_i,
  input  wire         rst_i,

  // Wishbone bus interface
  input  wire  [31:0] wb_adr_i,
  input  wire  [31:0] wb_dat_i,
  output wire  [31:0] wb_dat_o,
  input  wire   [3:0] wb_sel_i,
  input  wire         wb_we_i,
  input  wire         wb_cyc_i,
  input  wire         wb_stb_i,
  output wire         wb_stall_o,
  output wire         wb_ack_o,

  // IRQ output to CPU
  output wire         irq_o
);

  // --------------------------------------------------------------------------
  // Internal signals
  // --------------------------------------------------------------------------
  assign        wb_stall_o = 1'b0;
  wire          req_accepted = wb_stb_i & wb_cyc_i & ~wb_stall_o;
  wire          read_request;
  wire          read_response;
  wire          write_request;
  wire          write_response;
  wire  [31:0]  read_data;
  // --------------------------------------------------------------------------
  // Generate request signals
  // --------------------------------------------------------------------------
  assign read_request  = req_accepted & ~wb_we_i;
  assign write_request = req_accepted & wb_we_i;

  // Acknowledge comes when read/write response is ready
  assign wb_ack_o = wb_cyc_i & (read_response | write_response);

  // Data output to bus
  assign wb_dat_o = read_data;

  // --------------------------------------------------------------------------
  // Connect to rvx_mtimer_wb
  // --------------------------------------------------------------------------
  rvx_mtimer_wb u_mtimer (
    .clock          (clk_i),
    .reset          (rst_i),

    .rw_address     (wb_adr_i[4:0]),   // ch? c?n 5 bit th?p cho register map
    .read_data      (read_data),
    .read_request   (read_request),
    .read_response  (read_response),
    .write_data     (wb_dat_i),
    .write_strobe   (wb_sel_i),
    .write_request  (write_request),
    .write_response (write_response),

    .irq            (irq_o)
  );

endmodule
