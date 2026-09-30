`timescale 1ns / 1ps

module ascon_connect_wb (
    input  wire         wb_clk_i,
    input  wire         wb_rst_i,

    input  wire [31:0]  wb_adr_i,
    input  wire [31:0]  wb_dat_i,
    output reg  [31:0]  wb_dat_o,
    input  wire         wb_we_i,
    input  wire [3:0]   wb_sel_i,
    input  wire         wb_stb_i,
    input  wire         wb_cyc_i,
    output wire         wb_stall_o,
    output reg          wb_ack_o,
    output wire         irq_done
);

    // ---------------- Registers ----------------
    reg [127:0] reg_key;
    reg [127:0] reg_nonce;
    reg [127:0] reg_tag_out;

    reg         ctrl_start;
    reg         ctrl_decrypt;
    reg         ctrl_is_ad;
    reg         ctrl_variant;   // 0: ASCON-128, 1: ASCON-128a
    reg         ctrl_soft_rst;  // CTRL[4]

    reg [5:0]   auto_byte_counter;  // so byte da nap vao word3..1 (chua tinh word cuoi)
    reg [5:0]   pad_missed_q;       // FIX 4: latch luc trigger, dua vao core
    reg         irq_done_reg;

    reg [31:0]  data_word3, data_word2, data_word1, data_word0;

    reg         fifo_in_wr;
    reg         input_is_last;

    wire [127:0] core_data_in = {data_word3, data_word2, data_word1, data_word0};
    wire         core_data_ready;
    wire [127:0] core_data_out;
    wire         core_out_valid;
    wire         core_tag_valid;
    wire [127:0] core_tag_result;

    // ---------------- Decode + Stall ----------------
    wire [7:0] addr = {wb_adr_i[7:2], 2'b00};

    wire is_data_reg     = (addr >= 8'h40) && (addr <= 8'h58);
    wire is_data_trigger = (addr == 8'h4C) || (addr == 8'h50) ||
                           (addr == 8'h54) || (addr == 8'h58);

    // FIX (stall): chan trigger khi core chua ready, va chan moi write vao
    // vung data khi fifo_in_wr dang len (core dang lay mau data_in)
    assign wb_stall_o = wb_cyc_i & wb_stb_i & wb_we_i &
                        ( (is_data_trigger & ~core_data_ready) |
                          (is_data_reg     &  fifo_in_wr) );

    wire req_accepted = wb_cyc_i & wb_stb_i & ~wb_stall_o;
    wire wr_accepted  = req_accepted &  wb_we_i;
    wire rd_accepted  = req_accepted & ~wb_we_i;

    // ---------------- ASCON core ----------------
    ascon_core u_core (
        .clk           (wb_clk_i),
        .rst_n         (!(wb_rst_i || ctrl_soft_rst)),
        .start         (ctrl_start),
        .decrypt_mode  (ctrl_decrypt),
        .variant       (ctrl_variant),
        .padding_missed(pad_missed_q),
        .key           (reg_key),
        .nonce         (reg_nonce),
        .data_in       (core_data_in),
        .data_valid    (fifo_in_wr),
        .data_last     (input_is_last),
        .is_ad         (ctrl_is_ad),
        .data_ready    (core_data_ready),
        .data_out      (core_data_out),
        .out_valid     (core_out_valid),
        .tag_valid     (core_tag_valid),
        .tag_out       (core_tag_result)
    );

    // ---------------- Helpers ----------------
    function [2:0] count_ones(input [3:0] sel);
        count_ones = sel[0] + sel[1] + sel[2] + sel[3];
    endfunction

    function [31:0] merge(input [31:0] old, input [31:0] nw, input [3:0] sel);
        merge = { sel[3] ? nw[31:24] : old[31:24],
                  sel[2] ? nw[23:16] : old[23:16],
                  sel[1] ? nw[15:8]  : old[15:8],
                  sel[0] ? nw[7:0]   : old[7:0] };
    endfunction

    // ---------------- Write path + control ----------------
    // FIX 1: wb_ack_o chi duoc drive o day (bo block ACK rieng)
    always @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            wb_ack_o          <= 1'b0;
            reg_key           <= 128'b0;
            reg_nonce         <= 128'b0;
            reg_tag_out       <= 128'b0;
            ctrl_start        <= 1'b0;
            ctrl_decrypt      <= 1'b0;
            ctrl_is_ad        <= 1'b0;
            ctrl_variant      <= 1'b0;
            ctrl_soft_rst     <= 1'b0;   // FIX 5
            auto_byte_counter <= 6'd0;
            pad_missed_q      <= 6'd0;
            data_word0        <= 32'b0;
            data_word1        <= 32'b0;
            data_word2        <= 32'b0;
            data_word3        <= 32'b0;
            fifo_in_wr        <= 1'b0;
            input_is_last     <= 1'b0;
            irq_done_reg      <= 1'b0;
        end else begin
            // defaults (xung 1 clock)
            ctrl_start    <= 1'b0;
            ctrl_soft_rst <= 1'b0;
            fifo_in_wr    <= 1'b0;                 // FIX 2
            wb_ack_o      <= req_accepted;         // FIX 1

            // FIX 3: chi xoa buffer o chu ky fifo_in_wr=1 (core lay mau canh clock nay)
            if (fifo_in_wr) begin
                data_word0 <= 32'b0;
                data_word1 <= 32'b0;
                data_word2 <= 32'b0;
                data_word3 <= 32'b0;
            end

            if (wr_accepted) begin
                case (addr)
                    8'h00: begin
                        irq_done_reg <= 1'b0;
                        if (wb_dat_i[0]) ctrl_start <= 1'b1;
                        ctrl_decrypt <= wb_dat_i[1];
                        ctrl_is_ad   <= wb_dat_i[2];
                        ctrl_variant <= wb_dat_i[3];
                        if (wb_dat_i[4]) ctrl_soft_rst <= 1'b1;
                    end

                    8'h10: reg_key[31:0]    <= wb_dat_i;
                    8'h14: reg_key[63:32]   <= wb_dat_i;
                    8'h18: reg_key[95:64]   <= wb_dat_i;
                    8'h1C: reg_key[127:96]  <= wb_dat_i;

                    8'h20: reg_nonce[31:0]   <= wb_dat_i;
                    8'h24: reg_nonce[63:32]  <= wb_dat_i;
                    8'h28: reg_nonce[95:64]  <= wb_dat_i;
                    8'h2C: reg_nonce[127:96] <= wb_dat_i;

                    8'h40: begin
                        data_word3 <= merge(data_word3, wb_dat_i, wb_sel_i);
                        auto_byte_counter <= auto_byte_counter + count_ones(wb_sel_i);
                    end
                    8'h44: begin
                        data_word2 <= merge(data_word2, wb_dat_i, wb_sel_i);
                        auto_byte_counter <= auto_byte_counter + count_ones(wb_sel_i);
                    end
                    8'h48: begin
                        data_word1 <= merge(data_word1, wb_dat_i, wb_sel_i);
                        auto_byte_counter <= auto_byte_counter + count_ones(wb_sel_i);
                    end

                    // 0x4C normal / 0x50 last: nap word0 + trigger
                    8'h4C, 8'h50: begin
                        data_word0    <= merge(data_word0, wb_dat_i, wb_sel_i);
                        fifo_in_wr    <= 1'b1;
                        input_is_last <= (addr == 8'h50);
                        // FIX 4: tinh ca byte cua word cuoi
                        pad_missed_q  <= 6'd16 - (auto_byte_counter + count_ones(wb_sel_i));
                        auto_byte_counter <= 6'd0;
                    end

                    // 0x54 last / 0x58 normal: trigger khong co data moi
                    8'h54, 8'h58: begin
                        fifo_in_wr    <= 1'b1;
                        input_is_last <= (addr == 8'h54);
                        pad_missed_q  <= 6'd16 - auto_byte_counter;
                        auto_byte_counter <= 6'd0;
                    end

                    default: ;
                endcase
            end

            // Soft reset: don trang thai wrapper (thang write cung chu ky)
            if (ctrl_soft_rst) begin
                auto_byte_counter <= 6'd0;
                pad_missed_q      <= 6'd0;
                fifo_in_wr        <= 1'b0;
                irq_done_reg      <= 1'b0;
                data_word0        <= 32'b0;
                data_word1        <= 32'b0;
                data_word2        <= 32'b0;
                data_word3        <= 32'b0;
            end

            // Dat cuoi cung de "set" thang "clear" (khong mat IRQ)
            if (core_tag_valid) begin
                reg_tag_out  <= core_tag_result;
                irq_done_reg <= 1'b1;
            end
        end
    end

    // ---------------- Read path ----------------
    always @(posedge wb_clk_i) begin
        if (wb_rst_i)
            wb_dat_o <= 32'b0;
        else if (rd_accepted) begin
            case (addr)
                8'h04: wb_dat_o <= {29'b0, core_out_valid, irq_done_reg, core_data_ready};
                8'h30: wb_dat_o <= reg_tag_out[31:0];
                8'h34: wb_dat_o <= reg_tag_out[63:32];
                8'h38: wb_dat_o <= reg_tag_out[95:64];
                8'h3C: wb_dat_o <= reg_tag_out[127:96];
                8'h40: wb_dat_o <= core_data_out[127:96];
                8'h44: wb_dat_o <= core_data_out[95:64];
                8'h48: wb_dat_o <= core_data_out[63:32];
                8'h4C: wb_dat_o <= core_data_out[31:0];
                default: wb_dat_o <= 32'b0;
            endcase
        end
    end

    assign irq_done = irq_done_reg;

endmodule