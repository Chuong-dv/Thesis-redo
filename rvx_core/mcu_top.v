// ============================================================================
// Module: mcu_top
// Description: Module c?p cao nh?t cho Kit FPGA (DE2-115 / Cyclone IV)
// S? d?ng SW[5:1] làm ??a ch? nh? phân ?? duy?t 32 Word (1024-bit) d? li?u.
// ============================================================================

module mcu_top #(
    parameter CLOCK_FREQUENCY     = 50_000_000,
    parameter UART_BAUD_RATE      = 9600,
    parameter MEMORY_SIZE         = 8192,
    parameter MEMORY_INIT_FILE    = "", 
    parameter BOOT_ADDRESS        = 32'h00000000,
    parameter GPIO_WIDTH          = 32,
    parameter SPI_NUM_CHIP_SELECT = 1,
    // Tham s? c?u hình ASCON
    parameter ASCON_RATE          = 64, 
    parameter ASCON_ROUND_A       = 12,
    parameter ASCON_ROUND_B       = 6,
    parameter ASCON_L             = 40,
    parameter ASCON_Y             = 40
)(
    input  wire                            clk_i,
    input  wire                            rst_i,   // KEY[0] (Active Low)
    input  wire                            halt,    // SW[0]
    
    // [GIAO DIEN DIEU KHIEN SWITCH]
    // SW[17]: Chon che do hien thi (0: Xem TAG 128-bit, 1: Xem DATA 1024-bit)
    // SW[5:1]: CHON WORD (Mã nhi phân 5-bit ?? chon Word 0 den Word 31)
    //   Ví du: 00000 -> Word 0 (31:0), 00101 -> Word 5 (191:160)
    input  wire  [17:1]                    SW,      

    input  wire                            uart_rx,
    output wire                            uart_tx,
    output wire                            sclk,
    output wire                            pico,
    input  wire                            poci,
    output wire  [SPI_NUM_CHIP_SELECT-1:0] cs,
    inout  wire  [GPIO_WIDTH-1:0]          gpio

    
);
    
    // --- Quan lý chân GPIO ---
    wire [GPIO_WIDTH-1:0] gpio_input;
    wire [GPIO_WIDTH-1:0] gpio_output;
    wire [GPIO_WIDTH-1:0] gpio_oe;

    genvar i;
    generate
        for (i = 0; i < GPIO_WIDTH; i = i + 1) begin : gen_gpio
            assign gpio_input[i] = gpio[i];
            assign gpio[i]       = gpio_oe[i] ? gpio_output[i] : 1'bz;
        end
    endgenerate

    // --- Dong bo hóa Reset ---
    reg rst_sync, rst_debounced;
    always @(posedge clk_i) begin
        rst_sync       <= ~rst_i; 
        rst_debounced  <= rst_sync;
    end
    
    // --- Instance SoC MCU ---
    mcu #(
        .CLOCK_FREQUENCY(CLOCK_FREQUENCY),
        .UART_BAUD_RATE(UART_BAUD_RATE),
        .MEM_SIZE(MEMORY_SIZE),
        .MEMORY_INIT_FILE(MEMORY_INIT_FILE),
        .GPIO_WIDTH(GPIO_WIDTH),
        .SPI_NUM_CHIP_SELECT(SPI_NUM_CHIP_SELECT),
        .BOOT_ADDRESS(BOOT_ADDRESS),
        .ASCON_RATE(ASCON_RATE),
        .ASCON_ROUND_A(ASCON_ROUND_A),
        .ASCON_ROUND_B(ASCON_ROUND_B),
        .ASCON_L(ASCON_L),
        .ASCON_Y(ASCON_Y)
    ) u_mcu (
        .clk_i(clk_i),
        .rst_i(rst_debounced), 
        .halt(halt),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx),
        .spi_sclk(sclk),
        .spi_pico(pico),
        .spi_poci(poci),
        .spi_cs(cs),
        .gpio_input(gpio_input),
        .gpio_oe(gpio_oe),
        .gpio_output(gpio_output)
    );



endmodule