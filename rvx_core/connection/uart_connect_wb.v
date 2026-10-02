module uart_connect_wb #(
    parameter CLOCK_FREQUENCY = 50000000,
    parameter UART_BAUD_RATE  = 9600
)(  
    //Wishbone system signal
    input  wire         clk_i,
    input  wire         rst_i,

    //Wishbone pipeline (B4) Interface
    input  wire [31:0]  wb_adr_i,
    input  wire [31:0]  wb_dat_i,
    output wire [31:0]  wb_dat_o,
    input  wire         wb_we_i,
    input  wire [3:0]   wb_sel_i,
    input  wire         wb_stb_i,
    input  wire         wb_cyc_i,
    output wire          wb_stall_o,
    output wire          wb_ack_o,

    //UART External Pins & interrupt
    input  wire         uart_rx,
    output wire         uart_tx,
    output wire         uart_irq
);

  // ------------------------------------------------------------
  // Wishbone signals
  // ------------------------------------------------------------
  assign wb_stall_o = 1'b0;

  wire req_accepted = wb_cyc_i & wb_stb_i & ~wb_stall_o;

  wire read_request = req_accepted & ~wb_we_i;
  wire write_request = req_accepted & wb_we_i;

  wire [4:0] addr5 = wb_adr_i[4:0];

  // Data from UART core
  wire [31:0] uart_read_data;
  wire        uart_irq_int;
  wire        uart_read_resp;
  wire        uart_write_resp;

  // ------------------------------------------------------------
  // Instantiate UART core
  // ------------------------------------------------------------
  rvx_uart_wb #(
    .CLOCK_FREQUENCY(CLOCK_FREQUENCY),
    .UART_BAUD_RATE(UART_BAUD_RATE)
  ) uart_core (
    .clock          (clk_i),
    .reset          (rst_i),
    .rw_address     (addr5),
    .read_data      (uart_read_data),
    .read_request   (read_request),
    .read_response  (uart_read_resp),        // not used
    .write_data     (wb_dat_i[7:0]),
    .write_request  (write_request),
    .write_response (uart_write_resp),        // not used
    .uart_rx        (uart_rx),
    .uart_tx        (uart_tx),
    .uart_irq       (uart_irq_int),
    .uart_irq_response(1'b0)   // optional
  );

  assign wb_dat_o = uart_read_data;
  assign uart_irq = uart_irq_int;

  //Wishbone ack
  assign wb_ack_o = wb_cyc_i & (uart_read_resp | uart_write_resp);
endmodule
