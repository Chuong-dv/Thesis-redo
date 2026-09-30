`timescale 1ns/1ps

module wb_ascon_tb;
    logic clk, rst;
    logic [31:0] wb_adr_i, wb_dat_i, wb_dat_o;
    logic wb_we_i;
    logic [3:0] wb_sel_i;
    logic wb_stb_i, wb_cyc_i, wb_stall_o, wb_ack_o, irq_done;


    ascon_connect_wb ascon_wb (
        .wb_clk_i(clk),
        .wb_rst_i(rst),

        .wb_adr_i(wb_adr_i),
        .wb_dat_i(wb_dat_i),
        .wb_dat_o(wb_dat_o),
        .wb_we_i(wb_we_i),
        .wb_sel_i(wb_sel_i),
        .wb_stb_i(wb_stb_i),
        .wb_cyc_i(wb_cyc_i),
        .wb_stall_o(wb_stall_o),
        .wb_ack_o(wb_ack_o),
        .irq_done(irq_done)

    );

    initial begin
        clk = 0;
        forever #10 clk = ~clk;
    end

    initial begin
        rst = 1;
        #20 
        rst = 0;
    end

    task automatic wb_write(input [31:0] addr, input [31:0] data, input [3:0] sel);
        int timeout;

        @(posedge clk); #1;
        wb_adr_i    = addr;
        wb_dat_i    = data;
        wb_sel_i    = sel;
        wb_we_i     = 1;
        wb_stb_i    = 1;
        wb_cyc_i    = 1;

        timeout = 0;
        do begin
            @(posedge clk);
            if(++timeout > 1000) $fatal(1, "wb_write: stall timeout, addr = %0h", addr);
        end while (wb_stall_o);

        #1; wb_stb_i = 0;

        timeout = 0;
        do begin
            @(posedge clk);
            if(++timeout > 1000) $fatal(1, "wb_write: ack timeout, addr = %0h", addr);
        end while (!wb_ack_o);

        #1;
        wb_cyc_i = 0;
        wb_we_i  = 0;   
    endtask

    task automatic wb_read(input [31:0] addr, output [31:0] data_o);
        int timeout;

        @(posedge clk); #1;
        wb_adr_i    = addr;
        wb_dat_i    = 0;
        wb_sel_i    = 4'hF;
        wb_we_i     = 0;
        wb_stb_i    = 1;
        wb_cyc_i    = 1;

        timeout = 0;
        do begin
            @(posedge clk);
            if(++timeout > 1000) $fatal(1, "wb_read: stall timeout, addr = %0h", addr);
        end while (wb_stall_o);

        #1; wb_stb_i = 0;
        
        

        timeout = 0;
        do begin
            @(posedge clk);
            if(++timeout > 1000) $fatal(1, "wb_read: ack timeout, addr = %0h", addr);
        end while (!wb_ack_o);
        data_o      = wb_dat_o;
        #1;
        
        wb_cyc_i = 0;
    endtask
    logic [31:0] data;
    initial begin
        wb_write(32'h04, 32'h5A5A5A5A, 4'hF);
        wb_read(32'h04, data);
        $display("data out: %0h", data);
        $finish;
    end
    
endmodule