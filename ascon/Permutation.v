// ============================================================================
// File: ascon_permutation.v
// Description: Module Hoan vi ASCON (Optimized Timing for 100MHz+)
// Optimization: Registered Round Constants to reduce Combinational Path Delay.
// ============================================================================
module ascon_permutation (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [3:0]   rounds,   
    input  wire [319:0] state_in, 
    output reg  [319:0] state_out,
    output reg          done
);

    reg [319:0] current_state;
    reg [3:0]   round_cnt;
    reg         busy;
    
    // --- OPTIMIZATION START: Registered Round Constant ---
    // Thay vì tính toán t? h?p rc_idx = (12 - rounds) + cnt r?i tra Mux,
    // chúng ta n?p giá tr? ban ??u và tr? ?i 0x0F m?i vòng (vì h?ng s? ASCON gi?m ??u: F0, E1, D2...)
    // Vi?c này lo?i b? hoàn toàn ?? tr? c?a Adder và Mux kh?i ???ng Critical Path.
    
    reg [7:0]   round_const_reg;
    reg [7:0]   round_const_next; // Combinational logic cho giá tr? kh?i t?o

    // Tính toán giá tr? h?ng s? kh?i ?i?m (Ch? dùng khi Start, không ?nh h??ng Timing vòng l?p)
    wire [3:0] start_rc_idx = 4'd12 - rounds;
    
    always @(*) begin
        case(start_rc_idx)
            4'h0: round_const_next = 8'hf0;
            4'h1: round_const_next = 8'he1;
            4'h2: round_const_next = 8'hd2;
            4'h3: round_const_next = 8'hc3;
            4'h4: round_const_next = 8'hb4;
            4'h5: round_const_next = 8'ha5;
            4'h6: round_const_next = 8'h96;
            4'h7: round_const_next = 8'h87;
            4'h8: round_const_next = 8'h78;
            4'h9: round_const_next = 8'h69;
            4'ha: round_const_next = 8'h5a;
            4'hb: round_const_next = 8'h4b;
            default: round_const_next = 8'h00;
        endcase
    end

    // C?p nh?t thanh ghi h?ng s?
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            round_const_reg <= 8'd0;
        end else if (start) begin
            round_const_reg <= round_const_next; // N?p giá tr? ??u
        end else if (busy) begin
            round_const_reg <= round_const_reg - 8'h0f; // Các h?ng s? Ascon cách nhau 15 ??n v? (0x0F)
        end
    end

    wire [63:0] round_constant = {56'd0, round_const_reg};
    // --- OPTIMIZATION END ---

    // --- State Parts ---
    wire [63:0] x0_in = current_state[319:256];
    wire [63:0] x1_in = current_state[255:192];
    wire [63:0] x2_in = current_state[191:128];
    wire [63:0] x3_in = current_state[127:64];
    wire [63:0] x4_in = current_state[63:0];

    // --- 1. Constant Addition ---
    // Bây gi? round_constant ??n t? thanh ghi, ?? tr? g?n nh? b?ng 0.
    wire [63:0] x2_c = x2_in ^ round_constant;

    // --- 2. Substitution Layer (Standard Ascon S-box) ---
    // Intermediate XORs
    wire [63:0] x0_x = x0_in ^ x4_in;
    wire [63:0] x4_x = x4_in ^ x3_in;
    wire [63:0] x2_x = x2_c  ^ x1_in;

    // AND-NOT Layer
    wire [63:0] t0 = ~x0_x & x1_in;
    wire [63:0] t1 = ~x1_in & x2_x;
    wire [63:0] t2 = ~x2_x & x3_in;
    wire [63:0] t3 = ~x3_in & x4_x;
    wire [63:0] t4 = ~x4_x & x0_x;

    // Final XORs
    wire [63:0] y0 = x0_x ^ t1;
    wire [63:0] y1 = x1_in ^ t2;
    wire [63:0] y2 = x2_x ^ t3;
    wire [63:0] y3 = x3_in ^ t4;
    wire [63:0] y4 = x4_x ^ t0;

    // Result Assign
    wire [63:0] x0_s = y0 ^ y4;
    wire [63:0] x1_s = y0 ^ y1;
    wire [63:0] x2_s = ~y2;
    wire [63:0] x3_s = y2 ^ y3;
    wire [63:0] x4_s = y4;

    // --- 3. Linear Layer ---
    function [63:0] rotr64(input [63:0] val, input [5:0] amt);
        rotr64 = (val >> amt) | (val << (64 - amt));
    endfunction

    wire [63:0] x0_l = x0_s ^ rotr64(x0_s, 19) ^ rotr64(x0_s, 28);
    wire [63:0] x1_l = x1_s ^ rotr64(x1_s, 61) ^ rotr64(x1_s, 39);
    wire [63:0] x2_l = x2_s ^ rotr64(x2_s, 1)  ^ rotr64(x2_s, 6);
    wire [63:0] x3_l = x3_s ^ rotr64(x3_s, 10) ^ rotr64(x3_s, 17);
    wire [63:0] x4_l = x4_s ^ rotr64(x4_s, 7)  ^ rotr64(x4_s, 41);

    // --- Sequential Logic ---
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= 320'd0;
            state_out     <= 320'd0;
            round_cnt     <= 4'd0;
            busy          <= 1'b0;
            done          <= 1'b0;
        end else begin
            done <= 1'b0;
            if (!busy) begin
                if (start) begin
                    current_state <= state_in;
                    round_cnt     <= 4'd0;
                    busy          <= 1'b1;
                end
            end else begin
                current_state <= {x0_l, x1_l, x2_l, x3_l, x4_l};
                
                if (round_cnt == rounds - 1) begin
                    state_out <= {x0_l, x1_l, x2_l, x3_l, x4_l};
                    done      <= 1'b1;
                    busy      <= 1'b0;
                end else begin
                    round_cnt <= round_cnt + 1;
                end
            end
        end
    end
endmodule