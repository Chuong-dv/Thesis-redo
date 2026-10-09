`timescale 1ns/1ps
module tb_core;
    logic clk = 0, rst = 1;
    always #10 clk = ~clk;

    wire [31:0] rw_address, write_data, read_data;
    wire [3:0]  write_strobe;
    wire        read_request, write_request, read_response, write_response;

    rvx_core_wb #(.BOOT_ADDRESS(32'h8000_0000)) core (
        .clk_i(clk), .rst_i(rst), .halt(1'b0),
        .rw_address(rw_address), .read_data(read_data),
        .read_request(read_request), .read_response(read_response),
        .write_data(write_data), .write_strobe(write_strobe),
        .write_request(write_request), .write_response(write_response),
        .irq_external(1'b0), .irq_external_response(),
        .irq_timer(1'b0),    .irq_timer_response(),
        .irq_software(1'b0), .irq_software_response(),
        .irq_fast(16'd0),    .irq_fast_response(),
        .real_time_clock(64'd0)
    );

    rvx_ram_wb #(.MEMORY_SIZE(65536), .MEMORY_INIT_FILE("")) mem (
        .clock(clk), .reset(rst),
        .rw_address(rw_address & 32'h0000_FFFF),
        .read_data(read_data), .read_request(read_request), .read_response(read_response),
        .write_data(write_data), .write_strobe(write_strobe),
        .write_request(write_request), .write_response(write_response)
    );
    
    string hex;
    logic [31:0] tohost;
    initial begin
        #1;                                              // sau initial zero-fill cua RAM
        if (!$value$plusargs("HEX=%s", hex))     $fatal(1, "thieu +HEX=");
        if (!$value$plusargs("TOHOST=%h", tohost)) $fatal(1, "thieu +TOHOST=");
        for (int i = 0; i < 16384; i++) mem.ram[i] = 32'h0;
        $readmemh(hex, mem.ram);
        repeat (4) @(posedge clk);
        #1 rst = 1'b0;
    end

    always @(posedge clk)
    begin
        if(write_request && rw_address == tohost) begin
            if(write_data == 32'h1) $display ("TEST PASSED");
            else                    $display ("TEST FAILED: tohost = %h (fail o buoc %0h)", write_data, write_data >> 1);
        $finish;
        end
    end

    always @(posedge clk)
    if (core.current_state == 4'b0100)     // STATE_TRAP_TAKEN
        $display("[%0t] TRAP: mcause=%0d mtval=%h mepc=%h",
                 $time, core.csr_mcause_code, core.csr_mtval, core.csr_mepc);
endmodule
