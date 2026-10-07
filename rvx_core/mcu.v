module mcu #(
    parameter CLOCK_FREQUENCY     = 50_000_000,
    parameter UART_BAUD_RATE      = 9600,
    parameter MEM_SIZE            = 8*1024, // 8 KB
    parameter MEMORY_INIT_FILE    = "",
    parameter GPIO_WIDTH          = 32,
    parameter SPI_NUM_CHIP_SELECT = 1,
    parameter BOOT_ADDRESS        = 32'h0000_0000,
    // Tham so ASCON
    parameter ASCON_RATE          = 64,
    parameter ASCON_ROUND_A       = 12,
    parameter ASCON_ROUND_B       = 6,
    parameter ASCON_L             = 40,
    parameter ASCON_Y             = 40
)(
    input  wire                         clk_i,
    input  wire                         rst_i,
    input  wire                         halt,
    input  wire                         uart_rx,
    output wire                         uart_tx,
    output wire                         spi_sclk,
    output wire                         spi_pico,
    input  wire                         spi_poci,
    output wire [SPI_NUM_CHIP_SELECT-1:0] spi_cs,
    input  wire [GPIO_WIDTH-1:0]        gpio_input,
    output wire [GPIO_WIDTH-1:0]        gpio_oe,
    output wire [GPIO_WIDTH-1:0]        gpio_output
    
);
    localparam NUM_SLAVES = 6; 
    wire [31:0] wb_m_adr_o, wb_m_dat_o, wb_m_dat_i;
    wire [3:0]  wb_m_sel_o;
    wire        wb_m_we_o, wb_m_cyc_o, wb_m_stb_o, wb_m_ack_i;
    wire [31:0] cpu_rw_address, cpu_read_data, cpu_write_data;
    wire        cpu_read_request, cpu_read_response, cpu_write_request, cpu_write_response;
    wire [3:0]  cpu_write_strobe;
    wire [NUM_SLAVES*32-1:0] wb_slaves_adr_o, wb_slaves_dat_o, wb_slaves_dat_i;
    wire [NUM_SLAVES*4-1:0]  wb_slaves_sel_o;
    wire [NUM_SLAVES-1:0]    wb_slaves_we_o, wb_slaves_cyc_o, wb_slaves_stb_o, wb_slaves_ack_i;
    wire irq_mtimer, irq_uart, irq_ascon;

    wire [31:0] ascon_p_adr, ascon_p_dat_w, ascon_p_dat_r;
    wire [3:0]  acon_p_sel;
    wire        ascon_p_we, ascon_p_cyc, ascon_p_stb, ascon_p_stall, ascon_p_ack;

    // RVX Core
    rvx_core_wb #(.BOOT_ADDRESS(BOOT_ADDRESS)) u_core (
        .clk_i(clk_i), .rst_i(rst_i), .halt(halt),
        .rw_address(cpu_rw_address), .read_data(cpu_read_data), 
        .read_request(cpu_read_request), .read_response(cpu_read_response), 
        .write_data(cpu_write_data), .write_strobe(cpu_write_strobe), 
        .write_request(cpu_write_request), .write_response(cpu_write_response),
        .irq_external(irq_uart | irq_ascon), 
        .irq_external_response(), .irq_timer(irq_mtimer), .irq_timer_response(),
        .irq_software(1'b0), .irq_software_response(), .irq_fast(16'd0), .irq_fast_response(),
        .real_time_clock (64'd0)
    );

    // CPU Adapter
    cpu_connect_wb u_cpu_adapter (
        .clk_i(clk_i), .rst_i(rst_i),
        .rw_address(cpu_rw_address), .read_request(cpu_read_request),
        .read_data(cpu_read_data), .read_response(cpu_read_response),
        .write_data(cpu_write_data), .write_strobe(cpu_write_strobe),
        .write_request(cpu_write_request), .write_response(cpu_write_response),
        .wb_adr_o(wb_m_adr_o), .wb_dat_o(wb_m_dat_o), .wb_dat_i(wb_m_dat_i),
        .wb_we_o (wb_m_we_o), .wb_sel_o(wb_m_sel_o), .wb_stb_o(wb_m_stb_o),
        .wb_cyc_o(wb_m_cyc_o),.wb_stall_i(1'b1), .wb_ack_i(wb_m_ack_i)
    );

    // Wishbone Interconnect
    rvx_wb_interconnect #(
        .NUM_SLAVES(NUM_SLAVES),
        .SLAVE_ADDR_BASE({32'h80050000, 32'h80040000, 32'h80030000, 32'h80010000, 32'h80000000, 32'h00000000}),
        .SLAVE_ADDR_END ({32'h8005FFFF, 32'h8004FFFF, 32'h8003FFFF, 32'h8001FFFF, 32'h8000FFFF, 32'h0000FFFF})
    ) u_interconnect (
        .clk_i(clk_i), 
        .rst_i(rst_i),
        .m_adr_i(wb_m_adr_o), 
        .m_dat_i(wb_m_dat_o), 
        .m_dat_o(wb_m_dat_i),
        .m_sel_i(wb_m_sel_o), 
        .m_we_i(wb_m_we_o),   
        .m_cyc_i(wb_m_cyc_o), 
        .m_stb_i(wb_m_stb_o), 
        .m_ack_o(wb_m_ack_i),
        .s_cyc_o(wb_slaves_cyc_o), 
        .s_stb_o(wb_slaves_stb_o), 
        .s_we_o(wb_slaves_we_o), 
        .s_sel_o(wb_slaves_sel_o), 
        .s_adr_o(wb_slaves_adr_o), 
        .s_dat_o(wb_slaves_dat_o), 
        .s_dat_i(wb_slaves_dat_i), 
        .s_ack_i(wb_slaves_ack_i)
    );

    // Slaves
    ram_connect_wb #(.MEMORY_SIZE(MEM_SIZE), .MEMORY_INIT_FILE(MEMORY_INIT_FILE)) u_ram (
        .clk_i(clk_i), .rst_i(rst_i),
        .wb_adr_i(wb_slaves_adr_o[0*32 +: 32]), 
        .wb_dat_i(wb_slaves_dat_o[0*32 +: 32]), 
        .wb_dat_o(wb_slaves_dat_i[0*32 +: 32]),
        .wb_sel_i(wb_slaves_sel_o[0*4 +: 4]), 
        .wb_we_i(wb_slaves_we_o[0]), 
        .wb_stb_i(wb_slaves_stb_o[0]), 
        .wb_cyc_i(wb_slaves_cyc_o[0]), 
        .wb_ack_o(wb_slaves_ack_i[0])
    );
    gpio_connect_wb #(.GPIO_WIDTH(GPIO_WIDTH)) u_gpio (
        .clk_i(clk_i), .rst_i(rst_i),
        .wb_adr_i(wb_slaves_adr_o[1*32 +: 32]), 
        .wb_dat_i(wb_slaves_dat_o[1*32 +: 32]), 
        .wb_dat_o(wb_slaves_dat_i[1*32 +: 32]),
        .wb_sel_i(wb_slaves_sel_o[1*4 +: 4]), 
        .wb_we_i(wb_slaves_we_o[1]), 
        .wb_stb_i(wb_slaves_stb_o[1]), 
        .wb_cyc_i(wb_slaves_cyc_o[1]), 
        .wb_ack_o(wb_slaves_ack_i[1]),
        .gpio_input(gpio_input), 
        .gpio_oe(gpio_oe), 
        .gpio_output(gpio_output)
    );
    mtimer_connect_wb u_mtimer (
        .clk_i(clk_i), .rst_i(rst_i),
        .wb_adr_i(wb_slaves_adr_o[2*32 +: 32]), 
        .wb_dat_i(wb_slaves_dat_o[2*32 +: 32]), 
        .wb_dat_o(wb_slaves_dat_i[2*32 +: 32]),
        .wb_sel_i(wb_slaves_sel_o[2*4 +: 4]), 
        .wb_we_i(wb_slaves_we_o[2]), 
        .wb_stb_i(wb_slaves_stb_o[2]), 
        .wb_cyc_i(wb_slaves_cyc_o[2]), 
        .wb_ack_o(wb_slaves_ack_i[2]),
        .irq_o(irq_mtimer)
    );
    uart_connect_wb #(.CLOCK_FREQUENCY(CLOCK_FREQUENCY), .UART_BAUD_RATE(UART_BAUD_RATE)) u_uart (
        .clk_i(clk_i), .rst_i(rst_i),
        .wb_adr_i(wb_slaves_adr_o[3*32 +: 32]), 
        .wb_dat_i(wb_slaves_dat_o[3*32 +: 32]), 
        .wb_dat_o(wb_slaves_dat_i[3*32 +: 32]),
        .wb_sel_i(wb_slaves_sel_o[3*4 +: 4]), 
        .wb_we_i(wb_slaves_we_o[3]), 
        .wb_stb_i(wb_slaves_stb_o[3]), 
        .wb_cyc_i(wb_slaves_cyc_o[3]), 
        .wb_ack_o(wb_slaves_ack_i[3]),
        .uart_rx(uart_rx), 
        .uart_tx(uart_tx), 
        .uart_irq(irq_uart)
    );
    spi_connect_wb #(.SPI_NUM_CHIP_SELECT(SPI_NUM_CHIP_SELECT)) u_spi (
        .clk_i(clk_i), 
        .rst_i(rst_i),
        .wb_adr_i(wb_slaves_adr_o[4*32 +: 32]), 
        .wb_dat_i(wb_slaves_dat_o[4*32 +: 32]), 
        .wb_dat_o(wb_slaves_dat_i[4*32 +: 32]),
        .wb_sel_i(wb_slaves_sel_o[4*4 +: 4]), 
        .wb_we_i(wb_slaves_we_o[4]), 
        .wb_stb_i(wb_slaves_stb_o[4]), 
        .wb_cyc_i(wb_slaves_cyc_o[4]), 
        .wb_ack_o(wb_slaves_ack_i[4]),
        .sclk(spi_sclk), 
        .pico(spi_pico), 
        .poci(spi_poci), 
        .cs(spi_cs)
    );

    
    ascon_wb_adapter u_ascon_adapter (
        .clk_i(clk_i), .rst_i(rst_i),
        .c_adr_i(wb_slaves_adr_o[5*32 +: 32]), .c_dat_i(wb_slaves_dat_o[5*32 +: 32]),
        .c_dat_o(wb_slaves_dat_i[5*32 +: 32]), .c_sel_i(wb_slaves_sel_o[5*4 +: 4]),
        .c_we_i(wb_slaves_we_o[5]), .c_cyc_i(wb_slaves_cyc_o[5]),
        .c_stb_i(wb_slaves_stb_o[5]), .c_ack_o(wb_slaves_ack_i[5]),
        .p_adr_o(ascon_p_adr), .p_dat_o(ascon_p_dat_w), .p_dat_i(ascon_p_dat_r),
        .p_sel_o(ascon_p_sel), .p_we_o(ascon_p_we), .p_cyc_o(ascon_p_cyc),
        .p_stb_o(ascon_p_stb), .p_stall_i(ascon_p_stall), .p_ack_i(ascon_p_ack)
    );

    ascon_connect_wb u_ascon (
        .wb_clk_i(clk_i), .wb_rst_i(rst_i),
        .wb_adr_i(ascon_p_adr), .wb_dat_i(ascon_p_dat_w), .wb_dat_o(ascon_p_dat_r),
        .wb_sel_i(ascon_p_sel), .wb_we_i(ascon_p_we),
        .wb_stb_i(ascon_p_stb), .wb_cyc_i(ascon_p_cyc),
        .wb_stall_o(ascon_p_stall), .wb_ack_o(ascon_p_ack),
        .irq_done(irq_ascon)
    );
endmodule