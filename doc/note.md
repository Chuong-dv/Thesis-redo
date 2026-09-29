//CONFIGURATION
BOOT_ADDRESS        32'h00000000
CLOCK_FREQUENCY     50000000
UART_BAUD_RATE      9600
MEMORY_SIZE         8192
MEMORY_INIT_FILE    ""
GPIO WIDTH          32
SPI_NUM_CHIP_SELECT 1

//IO SIGNAL
logic clk
logic reset (active-high)
logic halt  (active-high)
logic uart_rx
logic uart_tx
logic gpio_input
logic gpio_oe
logic gpio_output
logic sclk
logic pico
logic poci
logic cs

//MEMORY MAP
RAM             0x00000000
UART_CONTROLLER 0x80000000
TIMER           0x80010000
GPIO_CONTROLLER 0x80020000
SPI_CONTROLLER  0x80030000

//SoC architecture

