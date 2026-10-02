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

    task automatic wait_status (input [31:0] mask);
        logic [31:0]status;
        int timeout =0;
        do begin
            wb_read (32'h00000004, status);
            if(++timeout > 1000) $fatal(1, "wait_status: ack timeout(masks:%h)", mask);
        end while((status & mask) !== mask);
    endtask

    //Vector hien tai
    logic [127:0]   key_v, nonce_v, tag_v;
    logic [255:0]   ad_v, pt_v, ct_v;
    int             adlen_v, ptlen_v;
    int             cnt, n_pass, n_fail;
    logic           vec_ok;

    //get byte
    function automatic logic [7:0] get_byte(input logic [255:0] v, input int len, input int i);
        return v[(len - 1 - i) * 8 +: 8];
    endfunction

    function automatic logic [63:0] pack64 (input logic [255:0] v, input int len, input int start, input int n);
        logic [63:0] r;
        r = 64'h0;
        for (int b = 0; b < n; b++)
            r[63 - 8*b -: 8] = get_byte(v, len, start + b);
        return r;
    endfunction

    function automatic logic [3:0] sel_of(input int k);
        return 4'b1111 << (4 - k);
    endfunction

    // 1 block (1-8 byte)
    //ascon-128: chi dung 2 word 0x40 va2 0x44. Trigger bang no data
    //0x58 = block thuong, 0x54 = block cuoi. wrapper tu tinh padding tu so byte da nap

    task automatic send_block (input logic [255:0] v, input int len, input int start, input int n, input bit last);
        logic [63:0] p;
        p = pack64(v, len, start, n);
        if(n > 0) wb_write(32'h40, p[63:32], sel_of(n > 4 ? 4:n));
        if(n > 4) wb_write(32'h44, p[31:0], sel_of(n - 4));
        wb_write(last ? 32'h54 : 32'h58, 32'h0, 4'hF);
    endtask

    //--Doc ket qua
    task automatic read_data64(output logic [63:0] v);
        logic [31:0] a, b;
        wb_read(32'h40, a); //[127:96]
        wb_read(32'h44, b); //[95:64]
        v = {a, b};
    endtask

    task automatic read_tag128(output logic [127:0] t);
        logic [31:0] a, b, c, d;
        wb_read(32'h30, a);
        wb_read(32'h34, b);
        wb_read(32'h38, c);
        wb_read(32'h3C, d);
        t = {d, c, b, a};
    endtask

    task automatic expect64 (input string what, input logic [63:0] got, input logic [63:0] expv, input int nbytes);
        logic [63:0] m;
        m = ~64'h0 << (64 - 8 * nbytes);
        if((got & m) !== (expv & m)) begin
            $display("[FAIL] #%0d adlen=%0d ptlen=%0d %s got=%h exp=%h", cnt, adlen_v, ptlen_v, what, got & m, expv & m);            
            vec_ok = 0;
        end
    endtask

    task automatic do_reset;
        rst = 1;
        repeat(4) @(posedge clk);
        #1; rst = 0;
    endtask

    // --Chay 1 vector (dung` cac bien *_v)
    task automatic run_vector;
        int nfull, remb, i;
        logic [63:0] got, expv;
        logic [127:0] got_tag;

        vec_ok = 1;
        do_reset;

        //1. Key & nonce
        for (int j = 0; j < 4; j++) begin
            wb_write(32'h10 + 4*j, key_v[32*j +: 32], 4'hF);
            wb_write(32'h20 + 4*j, nonce_v[32*j +: 32], 4'hF);
        end

        //2. start. bit0 = start, bit2 = is_ad
        wb_write(32'h00, (adlen_v > 0) ? 32'h5 : 32'h1, 4'hF);
        wait_status(32'h1);

        //3. bo qua neu AD = null
        if (adlen_v > 0) begin
            nfull = adlen_v / 8; remb = adlen_v % 8;
            for (i = 0; i < nfull; i++) begin
                send_block(ad_v, adlen_v, 8*i, 8, 0);
                wait_status(32'h1);
            end
            send_block(ad_v, adlen_v, 8*nfull, remb, 1);
            wait_status(32'h1);
            wb_write(32'h00, 32'h0, 4'hF);
        end

        //4. Plaintext
        nfull = ptlen_v / 8;
        remb = ptlen_v % 8;
        for (i = 0; i < nfull; i++) begin
            send_block(pt_v, ptlen_v, 8*i, 8, 0);
            wait_status(32'h1);
            read_data64(got);
            expv = pack64(ct_v, ptlen_v, 8*i, 8);
            expect64($sformatf("ct block %0d", i), got, expv, 8);
        end
        send_block(pt_v, ptlen_v, 8*nfull, remb, 1);
        wait_status(32'h2);

        //5.ciphertext
        if(remb > 0) begin
            read_data64(got);
            expv = pack64(ct_v, ptlen_v, 8*nfull, remb);
            expect64("ct last block", got, expv, remb);
        end
        read_tag128(got_tag);
        if (got_tag !== tag_v) begin
            $display("[FAIL] #%0d adlen = %0d ptlen = %0d tag got = %h exp = %h", cnt, adlen_v, ptlen_v, got_tag, tag_v);
            vec_ok = 0;
        end

        if(vec_ok) n_pass++;
        else n_fail++;
    endtask

    //---TIMEOUT 
    initial begin
        #500_000_000;
        $display("TIMEOUT");
        $finish;
    end

    //--initial chinh
    string  path;
    int     fd, r;

    initial begin
        wb_adr_i = 0;
        wb_dat_i = 0;
        wb_sel_i = 0;
        wb_we_i  = 0;
        wb_stb_i = 0;
        wb_cyc_i = 0;
        rst      = 1;
        cnt      = 0;
        n_pass   = 0;
        n_fail   = 0;

        if (!$value$plusargs("KAT=%s", path)) path = "kat128.txt";
        fd = $fopen (path, "r");
        if (fd == 0) $fatal(1, "khong mo duoc file KAT: %s", path);

        while (!$feof(fd)) begin
            r = $fscanf(fd, "%h %h %d %d %h %h %h %h\n",
                        key_v, nonce_v, adlen_v, ptlen_v, ad_v, pt_v, ct_v, tag_v);
            if (r == 8) begin
            cnt++;
            run_vector;
            end
        end
        $fclose(fd);
        
        $display("KAT SUMMARY: total=%0d pass=%0d fail=%0d", cnt, n_pass, n_fail);
        if (n_fail == 0 && cnt > 0) $display("TEST PASSED");
        else                        $display("TEST FAILED");
        $finish;

    end

endmodule
