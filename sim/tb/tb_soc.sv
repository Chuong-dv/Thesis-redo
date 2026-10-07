`timescale 1ns/1ps
module tb_soc;
    localparam [31:0] MAILBOX = 32'h0000_1FF0;
    logic clk, rst;
    mcu #(
            .MEMORY_INIT_FILE("fw/fw.hex")
        ) 
        dut(
            .clk_i(clk),
            .rst_i(rst),
            .halt(1'b0),
            .uart_rx(1'b1),
            .uart_tx(),
            .spi_sclk(),
            .spi_pico(),
            .spi_poci(1'b0),
            .spi_cs(),

            .gpio_input(0),
            .gpio_oe(),
            .gpio_output()


    );

    initial begin
       clk = 0;
       forever #10 clk = ~clk; 
    end

    

    initial begin
        int f;
        f = $fopen("fw/fw.hex", "r");
        if (f == 0) $fatal(1, "khong mo duoc fw.hex");
        $fclose(f);
    end
    
    always @(posedge clk) begin
        if (dut.wb_m_cyc_o && dut.wb_m_ack_i && dut.wb_m_we_o && dut.wb_m_adr_o == MAILBOX) begin
            $display("[%0t] MAILBOX = %h", $time, dut.wb_m_dat_o);
            if (dut.wb_m_dat_o == 32'h600DF00D) begin
                $display("TEST PASSED"); $finish;
            end
            if(dut.wb_m_dat_o[31:26] == 16'hBAD0) begin
                $display("TEST FAILED (ma loi %0d)", dut.wb_m_dat_o[15:0]); $finish;
            end
            if ($isunknown(dut.wb_m_dat_o)) begin
                $display("TEST FAILED (mailbox co X/Z)"); $finish;
            end
        end
    end

    initial begin
        #200_000;
        $display("TEST FAILED");
        $finish;
    end

    initial begin
        
        rst = 1'b1;
        repeat(4) @(posedge clk);
        #1;rst = 1'b0;
    end
endmodule