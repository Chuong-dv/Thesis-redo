`timescale 1ns / 1ps

module ascon_core (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,        
    input  wire         decrypt_mode, 
    input  wire         variant,        // 0: 128, 1: 128a
    input  wire [5:0]   padding_missed, // 0..15 (actually 0..16)
    input  wire [127:0] key,
    input  wire [127:0] nonce,
    input  wire [127:0] data_in,
    input  wire         data_valid,   
    input  wire         data_last,    
    input  wire         is_ad,        
    
    output reg          data_ready,   
    output reg [127:0]  data_out,
    output reg          out_valid,
    output reg          tag_valid,
    output reg [127:0]  tag_out
);

    wire [3:0] round_a = 4'd12;
    //coverage off
    wire [3:0] round_b = (variant) ? 4'd8 : 4'd6;
    //coverage on
    // IV Constants
    //coverage off
    wire [63:0] iv_val = (variant) ? 64'h80800c0800000000 : 64'h80400c0600000000;
    //coverage on
    wire [319:0] key_mask_init = {192'd0, key};
    wire [319:0] key_mask_final = (variant == 0) ? {64'd0, key, 128'd0} : {128'd0, key, 64'd0};

    // --- Padding Masks ---
    //coverage_off
    reg [127:0] mask_keep_data;
    reg [127:0] mask_padding_bit;
    //coverage_on
    always @(*) begin
        mask_keep_data = {128{1'b1}};
        mask_padding_bit = 128'd0;
        if (padding_missed > 0) begin
            mask_keep_data = mask_keep_data << (padding_missed * 8);
            mask_padding_bit[ (padding_missed * 8) - 1 ] = 1'b1;
        end
    end
    
    // FSM
    localparam S_IDLE       = 3'd0;
    localparam S_INIT_PERM  = 3'd1;
    localparam S_WAIT_DATA  = 3'd2; 
    localparam S_PROC_DATA  = 3'd3;
    localparam S_FINALIZE   = 3'd4;
    localparam S_DONE       = 3'd5;

    reg [2:0]   state_fsm;
    reg [319:0] state_reg;
    reg         domain_sep_done;
    reg         perm_start;
    reg [3:0]   perm_rounds;
    wire        perm_done;
    wire [319:0] perm_state_out;

    ascon_permutation u_perm (
        .clk(clk), .rst_n(rst_n),
        .start(perm_start), .rounds(perm_rounds),
        .state_in(state_reg), .state_out(perm_state_out), .done(perm_done)
    );

    reg [319:0] next_state;
    reg [127:0] padded_data_in;

    
    // Chi xuat khi KHONG phai block cuoi HOAC (la block cuoi NHUNG co du lieu thuc, padding_missed != 16)
    wire should_output_data = (!data_last || padding_missed != 6'd16);

    always @(*) begin
        padded_data_in = data_in; // Gia tri mac dinh
        // Chi ap dung padding khi dang o S_WAIT_DATA, co du lieu hop le va la block cuoi
        if (state_fsm == S_WAIT_DATA && data_valid && data_last && padding_missed > 0) begin
            padded_data_in = (data_in & mask_keep_data) | mask_padding_bit;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        
        if (!rst_n) begin
            //coverage off
            state_fsm <= S_IDLE;
            //coverage on   
            state_reg <= 320'd0;
            data_ready <= 0; out_valid <= 0; tag_valid <= 0;
            perm_start <= 0; domain_sep_done <= 0;
            tag_out <= 0; data_out <= 0;

            perm_rounds <= 4'd0;
        end else begin
         
            perm_start <= 0;
            out_valid <= 0; tag_valid <= 0;
            next_state = state_reg;

            case (state_fsm)
                S_IDLE: begin
                    data_ready <= 0;
                    domain_sep_done <= 0;
                    if (start) begin
                        state_reg <= {iv_val, key, nonce};
                        perm_start <= 1; perm_rounds <= round_a; state_fsm <= S_INIT_PERM;
                    end
                end

                S_INIT_PERM: begin
                    if (perm_done) begin
                        state_reg <= perm_state_out ^ key_mask_init;
                        state_fsm <= S_WAIT_DATA; data_ready <= 1;
                    end
                end

                S_WAIT_DATA: begin
                    if (data_valid) begin
                        data_ready <= 0;
                        
                        // Domain Separation
                        if (!is_ad && !domain_sep_done) begin
                            next_state[0] = next_state[0] ^ 1'b1;
                            domain_sep_done <= 1;
                        end

                        // Apply Padding Mask
                        //padded_data_in = data_in;
                        //if (data_last && padding_missed > 0) begin
                        //    padded_data_in = (data_in & mask_keep_data) | mask_padding_bit;
                        //end

                        if (is_ad) begin
                            // --- ASSOCIATED DATA ---
                            if (variant == 0) begin // Ascon-128
                                next_state[319:256] = next_state[319:256] ^ padded_data_in[127:64];
                                if (data_last && (padding_missed == 6'd8 || padding_missed == 6'd0)) begin
                                    next_state[255] = next_state[255] ^ 1'b1;
                                end
                            end else begin // Ascon-128a
                                next_state[319:192] = next_state[319:192] ^ padded_data_in;
                                if (data_last && padding_missed == 0) 
                                    next_state[191] = next_state[191] ^ 1'b1;
                            end
                            
                            state_reg <= next_state;
                            perm_start <= 1; perm_rounds <= round_b; state_fsm <= S_PROC_DATA;
                        end else begin
                            // --- ENCRYPT / DECRYPT ---
                            if (variant == 0) begin 
                                // === Ascon-128 (Rate 64) ===
                                if (!decrypt_mode) begin // ENCRYPT
                                    // [FIX] Ch? c?p nh?t data_out n?u c� d? li?u th?c
                                    if (should_output_data) begin
                                        data_out[127:64] <= next_state[319:256] ^ data_in[127:64];
                                        data_out[63:0]   <= 64'd0; 
                                    end
                                    
                                    if (data_last) begin
                                        next_state[319:256] = next_state[319:256] ^ padded_data_in[127:64];
                                        if (padding_missed == 6'd8 || padding_missed == 6'd0) begin
                                            next_state[255] = next_state[255] ^ 1'b1;
                                        end
                                    end else begin
                                        next_state[319:256] = next_state[319:256] ^ data_in[127:64];
                                    end

                                end else begin // DECRYPT
                                    if (should_output_data) begin
                                        data_out[127:64] <= next_state[319:256] ^ data_in[127:64];
                                        data_out[63:0]   <= 64'd0;
                                    end
                                    
                                    if (data_last) begin
                                        if (padding_missed > 8) begin
                                            next_state[319:256] = (data_in[127:64] & mask_keep_data[127:64]) | (next_state[319:256] & ~mask_keep_data[127:64]);
                                            next_state[319:256] = next_state[319:256] ^ mask_padding_bit[127:64];
                                            
                                        end else begin
                                            next_state[319:256] = data_in[127:64];
                                            next_state[255] = next_state[255] ^ 1'b1;
                                            
                                        end
                                    end else begin
                                        next_state[319:256] = data_in[127:64];
                                    end
                                end
                            end else begin 
                                // === Ascon-128a (Rate 128) ===
                                if (!decrypt_mode) begin // ENCRYPT
                                    if (should_output_data) begin
                                        data_out <= next_state[319:192] ^ data_in;
                                        
                                    end
                                    next_state[319:192] = next_state[319:192] ^ padded_data_in;
                                    
                                    if (data_last && padding_missed == 0)
                                        next_state[191] = next_state[191] ^ 1'b1;
                                end else begin // DECRYPT
                                    
                                    if (should_output_data) begin
                                        data_out <= next_state[319:192] ^ data_in;
                                    end
                                    
                                    if (data_last) begin
                                        
                                        if (padding_missed > 0) begin
                                            next_state[319:192] = (data_in & mask_keep_data) | (next_state[319:192] & ~mask_keep_data);
                                            next_state[319:192] = next_state[319:192] ^ mask_padding_bit;
                                            
                                        end else begin
                                            next_state[319:192] = data_in;
                                            next_state[191] = next_state[191] ^ 1'b1;
                                        end
                                    end else begin
                                        next_state[319:192] = data_in;
                                    end
                                end
                            end
                            
                            // [FIX] Ch? b?t out_valid n?u c� d? li?u th?c
                            if (should_output_data) begin
                                out_valid <= 1;
                            end

                            state_reg <= next_state;
                            
                            if (data_last && !is_ad) 
                                state_fsm <= S_FINALIZE;
                            else begin 
                                perm_start <= 1;
                                perm_rounds <= round_b; 
                                state_fsm <= S_PROC_DATA; 
                            end
                        end
                    end
                end

                S_PROC_DATA: begin
                    if (perm_done) begin
                        state_reg <= perm_state_out;
                        state_fsm <= S_WAIT_DATA; data_ready <= 1;
                    end
                end

                S_FINALIZE: begin
                    state_reg <= state_reg ^ key_mask_final;
                    perm_start <= 1; perm_rounds <= round_a; state_fsm <= S_DONE;
                end

                S_DONE: begin
                    if (perm_done) begin
                        tag_out <= perm_state_out[127:0] ^ key;
                        tag_valid <= 1; state_fsm <= S_IDLE; 
                    end
                end

                default: begin
                    state_fsm <= S_IDLE;
                end
            endcase
        end
    end
endmodule