module gpio_connect_wb #(
  parameter GPIO_WIDTH = 32
)(
  //System Signal
  input  wire                     clk_i,
  input  wire                     rst_i,

  //Wishbone interface
  input  wire [31:0]              wb_adr_i,
  input  wire [31:0]              wb_dat_i,
  output wire [31:0]              wb_dat_o,
  input  wire [3:0]               wb_sel_i,
  input  wire                     wb_we_i,
  input  wire                     wb_cyc_i,
  input  wire                     wb_stb_i,
  output wire                     wb_stall_o,
  output wire                     wb_ack_o,


  //GPIO port
  input  wire [GPIO_WIDTH-1:0]    gpio_input,
  output wire [GPIO_WIDTH-1:0]    gpio_oe,
  output wire [GPIO_WIDTH-1:0]    gpio_output
);

  // Translate firmware addresses to hardware
  wire [4:0] addr5;
  assign addr5 = (wb_adr_i[5:0]==6'h1C || wb_adr_i[5:0]==6'h24) ? 5'h04 :
                 (wb_adr_i[5:0]==6'h20 || wb_adr_i[5:0]==6'h14) ? 5'h08 :
                 wb_adr_i[5:0];
  assign wb_stall_o = 1'b0;
  wire req_accepted = wb_cyc_i & wb_stb_i & ~wb_stall_o;

  wire read_request  = req_accepted & ~wb_we_i;
  wire write_request = req_accepted &  wb_we_i;
  wire gpio_write_resp;
  wire gpio_read_resp;

  assign wb_ack_o = wb_cyc_i & (gpio_read_resp | gpio_write_resp);
  

  // Connect to core
  rvx_gpio_wb #(
    .GPIO_WIDTH(GPIO_WIDTH)
  ) u_gpio (
    .clock          (clk_i),
    .reset          (rst_i),
    .rw_address     (addr5),
    .read_data      (wb_dat_o),
    .read_request   (read_request),
    .read_response  (gpio_read_resp),  // not used
    .write_data     (wb_dat_i),
    .write_strobe   (wb_sel_i),
    .write_request  (write_request),
    .write_response (gpio_write_resp),  // not used
    .gpio_input     (gpio_input),
    .gpio_oe        (gpio_oe),
    .gpio_output    (gpio_output)
  );

endmodule
