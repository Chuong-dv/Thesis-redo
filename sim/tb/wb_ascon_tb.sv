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

    int ack_cnt;
    always @(posedge clk) if (wb_ack_o) ack_cnt <= ack_cnt + 1;

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

    task automatic wb_write2(input [31:0] a1, input [31:0] d1, input [3:0] s1, input [31:0] a2, input [31:0] d2, input [3:0] s2);
        int timeout;

        @(posedge clk);
        #1;
        ack_cnt = 0;
        wb_adr_i    = a1;
        wb_dat_i    = d1;
        wb_sel_i    = s1;
        wb_we_i     = 1;
        wb_cyc_i = 1;
        wb_stb_i = 1;
        timeout     = 0;
        do begin
            @(posedge clk);
            if(++timeout > 1000) $fatal(1, "write2: stall timeout, addr = %0h", a1);
        end while (wb_stall_o);
        #1;
        wb_stb_i = 1;
        wb_adr_i    = a2;
        wb_dat_i    = d2;
        wb_sel_i    = s2;
        timeout     = 0;
        do begin
            @(posedge clk);
            if(++timeout > 1000) $fatal(1, "write2: stall timeout, addr = %0h", a2);
        end while (wb_stall_o);
        #1; wb_stb_i = 0;
        timeout     = 0;
        do begin
            @(posedge clk);
            if(++timeout > 1000) $fatal(1, "wb_write: ack timeout, addr = %0h", a2);
        end while (ack_cnt < 2);
        #1;
        wb_cyc_i = 0;
        wb_we_i = 0;
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
    bit             no_wait;
    int             stall_cnt;
    bit             dec;
    logic           vec_ok;
    int             last_stall;
    bit             var_a;
    int             rate;

    //ack counter
    
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

    function automatic logic [127:0] pack128 (input logic [255:0] v, input int len, input int start, input int n);
        logic [127:0] r;
        r = 128'h0;
        for (int b = 0; b < n; b++)
            r[127 - 8*b -: 8] = get_byte(v, len, start + b);
        return r;
    endfunction

    function automatic logic [3:0] sel_of(input int k);
        return 4'b1111 << (4 - k);
    endfunction

    // 1 block (1-8 byte)
    //ascon-128: chi dung 2 word 0x40 va2 0x44. Trigger bang no data
    //0x58 = block thuong, 0x54 = block cuoi. wrapper tu tinh padding tu so byte da nap

    task automatic send_block (input logic [255:0] v, input int len, input int start, input int n, input bit last);
        logic [127:0] p;
        int k;
        p = pack128(v, len, start, n);
        for (int j = 0; j < 3; j++) begin
            k = n - 4*j;
            if (k > 4) k = 4;
            if (k > 0) wb_write(32'h40 + 4*j, p[127 - 32*j -: 32], sel_of(k));
        end
        k = n - 12;
        if(k > 4) k = 4;
        if(k > 0) wb_write(last ? 32'h50 : 32'h4C, p[31:0], sel_of(k));
        else wb_write(last ? 32'h54 : 32'h58, 32'h0, 4'hF);
    endtask


    task automatic read_data128(output logic[127:0] v);
        logic [31:0] a, b, c, d;
        wb_read(32'h40, a); 
        wb_read(32'h44, b); 
        wb_read(32'h48, c); 
        wb_read(32'h4C, d); 
        v = {a, b, c, d};
    endtask

    task automatic read_tag128(output logic [127:0] t);
        logic [31:0] a, b, c, d;
        wb_read(32'h30, a);
        wb_read(32'h34, b);
        wb_read(32'h38, c);
        wb_read(32'h3C, d);
        t = {d, c, b, a};
    endtask

    task automatic expect128 (input string what, input logic [127:0] got, input logic [127:0] expv, input int nbytes);
        logic [127:0] m;
        m = ~128'h0 << (128 - 8 * nbytes);
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
        logic [127:0] got, expv;
        logic [127:0] got_tag;

        vec_ok = 1;
        stall_cnt = 0;
        do_reset;

        //1. Key & nonce
        for (int j = 0; j < 4; j++) begin
            wb_write(32'h10 + 4*j, key_v[32*j +: 32], 4'hF);
            wb_write(32'h20 + 4*j, nonce_v[32*j +: 32], 4'hF);
        end

        //2. start. bit0 = start, bit2 = is_ad
        wb_write(32'h00, ((adlen_v > 0) ? 32'h5 : 32'h1) | (dec ? 32'h2 : 32'h0) | (var_a ? 32'h8 : 32'h0), 4'hF);
        wait_status(32'h1);

        //3. bo qua neu AD = null
        if (adlen_v > 0) begin
            nfull = adlen_v / rate; remb = adlen_v % rate;
            for (i = 0; i < nfull; i++) begin
                send_block(ad_v, adlen_v, rate*i, rate, 0);
                wait_status(32'h1);
            end
            send_block(ad_v, adlen_v, rate*nfull, remb, 1);
            wait_status(32'h1);
            wb_write(32'h00, (dec ? 32'h2 : 32'h0) | (var_a ? 32'h8 : 32'h0), 4'hF);
        end

        //4. Plaintext
        nfull = ptlen_v / rate;
        remb = ptlen_v % rate;
        for (i = 0; i < nfull; i++) begin
            send_block(dec ? ct_v:pt_v, ptlen_v, rate*i, rate, 0);
            if(!no_wait) begin
                wait_status(32'h1);
                read_data128(got);
                expv = pack128(dec ? pt_v : ct_v, ptlen_v, rate*i, rate);
                expect128($sformatf("%s block %0d",dec ? "pt" : "ct", i), got, expv, rate);
            end
        end
        send_block(dec ? ct_v:pt_v, ptlen_v, rate*nfull, remb, 1);
        wait_status(32'h2);

        //5.ciphertext
        if(remb > 0) begin
            read_data128(got);
            expv = pack128(dec ? pt_v:ct_v, ptlen_v, rate*nfull, remb);
            expect128($sformatf("%s last block", dec ? "pt" : "ct") , got, expv, remb);
        end
        read_tag128(got_tag);
        if (got_tag !== tag_v) begin
            $display("[FAIL] #%0d adlen = %0d ptlen = %0d tag got = %h exp = %h", cnt, adlen_v, ptlen_v, got_tag, tag_v);
            vec_ok = 0;
        end

        if (no_wait && ptlen_v >= rate && stall_cnt == 0) begin
            $display("[FAIL] #%0d ptlen=%0d khong co stall nao", cnt, ptlen_v);
            vec_ok = 0;
        end

        if (stall_cnt != last_stall) begin
            $display("[INFO] ptlen=%0d adlen=%0d stall_cnt=%0d", ptlen_v, adlen_v, stall_cnt);
            last_stall = stall_cnt;
        end

        if(vec_ok) n_pass++;
        else n_fail++;
    endtask

    //--Task Kiem tra
    task automatic check32(string what, logic [31:0] got, logic [31:0] expv);
        if(got !== expv) begin
            $display("[FAIL] %s got=%h exp=%h", what, got, expv);
            n_fail++;
        end else begin
            $display("[PASS] %s got=%h", what, got);
            n_pass++;
        end
    endtask

    task automatic check128(string what, logic [127:0] got, logic [127:0] expv);
        if (got !== expv) begin
            $display("[FAIL] %s got=%h exp=%h", what, got, expv);
            n_fail++;
        end else begin
            $display("[PASS] %s", what);
            n_pass++;
        end
    endtask

    //Task kiem tra irq
    task automatic test_irq_clear;
        logic [31:0] status;
        logic [127:0] got_tag;
        key_v   = 128'h000102030405060708090A0B0C0D0E0F;
        nonce_v = 128'h101112131415161718191A1B1C1D1E1F;
        do_reset;
        for (int j = 0; j < 4; j++) begin
            wb_write(32'h10 + 4*j, key_v[32*j +: 32], 4'hF);
            wb_write(32'h20 + 4*j, nonce_v[32*j +: 32], 4'hF);
        end
        wb_write(32'h0, 32'h1, 4'hF);
        wait_status(32'h1);
        wb_write(32'h54, 32'h0, 4'hF);
        wait_status(32'h2);
        wb_read(32'h4, status);
        check32("irq bi truoc khi xoa", status & 32'h2, 32'h2);
        check32("chan irq_done", {31'h0,irq_done}, 32'h1);
        wb_write(32'h0, 32'h0, 4'hF);
        wb_read(32'h4, status);
        check32("irq sau khi tat", status & 32'h2, 32'h0);
        check32("chan irq_done tat", {31'h0, irq_done}, 32'h0);
        read_tag128(got_tag);

        check128("tag con nguyen sau khi xoa irq", got_tag, 128'h38CCA290D1F2EF3DF9C8531946499037);

    endtask

    //Check soft reset
    task automatic test_soft_reset;
        logic [31:0] status;
        logic [127:0] got_tag;
        key_v   = 128'h000102030405060708090A0B0C0D0E0F;
        nonce_v = 128'h101112131415161718191A1B1C1D1E1F;
        do_reset;
        for (int j = 0; j < 4; j++) begin
            wb_write(32'h10 + 4*j, key_v[32*j +: 32], 4'hF);
            wb_write(32'h20 + 4*j, nonce_v[32*j +: 32], 4'hF);
        end
        wb_write(32'h0, 32'h1, 4'hF);
        wait_status(32'h1);
        wb_write(32'h40, 32'hDEADBEEF, 4'hF);
        wb_write(32'h00, 32'h10, 4'hF);
        wb_read(32'h04, status);
        check32("kiem tra trang thai", status & 32'h3, 32'h0);
        for (int k = 0; k < 4; k++) begin
            wb_write(32'h10 + 4*k, key_v[32*k +: 32], 4'hF);
            wb_write(32'h20 + 4*k, nonce_v[32*k +: 32], 4'hF);
        end
        wb_write(32'h0, 32'h1, 4'hF);
        wait_status(32'h1);
        wb_write(32'h54, 32'h0, 4'hF);
        wait_status(32'h2);
        read_tag128(got_tag);

        check128("tag dung sau soft reset", got_tag, 128'h38CCA290D1F2EF3DF9C8531946499037);
    endtask

    task automatic test_double_trigger;
        logic [31:0] status;
        logic [127:0] got_tag;
        key_v   = 128'h000102030405060708090A0B0C0D0E0F;
        nonce_v = 128'h101112131415161718191A1B1C1D1E1F;
        do_reset;
        for (int j = 0; j < 4; j++) begin
            wb_write(32'h10 + 4*j, key_v[32*j +: 32], 4'hF);
            wb_write(32'h20 + 4*j, nonce_v[32*j +: 32], 4'hF);
        end
        wb_write(32'h0, 32'h1, 4'hF);
        wait_status(32'h1);
        wb_write(32'h40, 32'h00010203, 4'hF);
        wb_write(32'h44, 32'h04050607, 4'hF);
        wb_write2(32'h58, 0, 4'hF, 32'h54, 0, 4'hF);
        wait_status(32'h2);
        read_tag128(got_tag);
        check128("tag con nguyen sau khi double trigger", got_tag, 128'h3B49F7BDCCFC50AAB0439D2B44847EAC);
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
    string  test_name;
    
    //Stall count
    always @(posedge clk) begin
        if(wb_cyc_i && wb_stb_i && wb_stall_o) stall_cnt++;
    end

    initial begin
        wb_adr_i = 0;
        wb_dat_i = 0;
        wb_sel_i = 0;
        wb_we_i  = 0;
        wb_stb_i = 0;
        wb_cyc_i = 0;
        rst      = 1;
        cnt      = 0;
        last_stall = -1;
        n_pass   = 0;
        n_fail   = 0;
        if(!$value$plusargs("TEST=%s", test_name)) test_name = "kat";

        dec      = (test_name == "decrypt"  || test_name == "v128a_dec");
        var_a    = (test_name == "v128a"    || test_name == "v128a_dec");
        rate = var_a ? 16:8;

        $display("MODE: test=%s dec=%0d", test_name, dec);
        if (test_name == "kat" || test_name == "stall" || test_name == "decrypt" || test_name == "v128a" || test_name == "v128a_dec") begin
            no_wait = (test_name == "stall");
            if (!$value$plusargs("KAT=%s", path)) path = "kat128.txt";
            fd = $fopen(path, "r");
            if (fd == 0) $fatal(1, "khong mo duoc file KAT: %s", path);
            while (!$feof(fd)) begin
                r = $fscanf(fd, "%h %h %d %d %h %h %h %h\n",
                            key_v, nonce_v, adlen_v, ptlen_v, ad_v, pt_v, ct_v, tag_v);
                if (r == 8) begin cnt++; run_vector; end
            end
            $fclose(fd);
        end
        else if (test_name == "irq_clear") test_irq_clear;
        else if (test_name == "soft_reset") test_soft_reset;
        else if (test_name == "double_trigger") test_double_trigger;
        else $fatal(1, "TEST khong ton tai: %s", test_name);
        
        $display("KAT SUMMARY: total=%0d pass=%0d fail=%0d", cnt, n_pass, n_fail);
        if (n_fail == 0 && (n_pass + n_fail) > 0)   $display("TEST PASSED");
        else                                        $display("TEST FAILED");
        $finish;

    end

endmodule
