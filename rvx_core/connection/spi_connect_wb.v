module spi_connect_wb #(
  parameter SPI_NUM_CHIP_SELECT = 1
)(
  //System Signal 
  input  wire                          clk_i,
  input  wire                          rst_i,
  
  //Wishbone Interface
  input  wire [31:0]                   wb_adr_i,
  input  wire [31:0]                   wb_dat_i,
  output wire [31:0]                   wb_dat_o,
  input  wire [3:0]                    wb_sel_i,
  input  wire                          wb_we_i,
  input  wire                          wb_cyc_i,
  input  wire                          wb_stb_i,
  output wire                          wb_stall_o,
  output wire                          wb_ack_o,

  output wire                          sclk,
  output wire                          pico,
  input  wire                          poci,
  output wire [SPI_NUM_CHIP_SELECT-1:0] cs
);

  // Wishbone handshake
  assign wb_stall_o  = 1'b0;
  wire req_accepted  = wb_stb_i & wb_cyc_i & ~wb_stall_o;
  wire read_request  = req_accepted & ~wb_we_i;
  wire write_request = req_accepted &  wb_we_i;

  wire [31:0] read_data;
  wire read_response;
  wire write_response;

  assign wb_ack_o = wb_cyc_i & (read_response | write_response);
  assign wb_dat_o = read_data;

  // SPI core instantiation
  rvx_spi_wb #(
    .SPI_NUM_CHIP_SELECT(SPI_NUM_CHIP_SELECT)
  ) spi_core (
    .clock          (clk_i),
    .reset          (rst_i),
    .rw_address     (wb_adr_i[4:0]),
    .read_data      (read_data),
    .read_request   (read_request),
    .read_response  (read_response),
    .write_data     (wb_dat_i[7:0]),
    .write_strobe   (wb_sel_i),
    .write_request  (write_request),
    .write_response (write_response),
    .sclk           (sclk),
    .pico           (pico),
    .poci           (poci),
    .cs             (cs)
  );

endmodule
