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

    // --- Nguon du lieu va cau hinh ---
    reg [127:0] reg_key;
    reg [127:0] reg_nonce;
    reg [127:0] reg_tag_out;
    
    // Control bitfields
    reg         ctrl_start;
    reg         ctrl_decrypt;
    reg         ctrl_is_ad;
    reg         ctrl_variant; // 0: ASCON-128, 1: ASCON-128a
    reg         ctrl_soft_rst; // CRTL[4]: soft reset

    reg [4:0]   auto_byte_counter; 
    reg         irq_done_reg;

    // Data Buffers np tu CPU (Su dung cho np du lieu tung byte)
    reg [31:0]  data_word3; 
    reg [31:0]  data_word2; 
    reg [31:0]  data_word1; 
    reg [31:0]  data_word0; 

    // --- Khoi tao ASCON Core ---
    wire [127:0] core_data_in = {data_word3, data_word2, data_word1, data_word0};
    reg          fifo_in_wr;
    reg          input_is_last;
    wire         core_data_ready;
    wire [127:0] core_data_out;
    wire         core_out_valid;
    wire         core_tag_valid;
    wire [127:0] core_tag_result;
   
    // --- Logic Giao Tiep Wishbone ---
    wire [7:0] addr = {wb_adr_i[7:2], 2'b00};

    wire is_data_trigger = (addr == 8'h4C) || (addr == 8'h50) || (addr == 8'h54) || (addr == 8'h58);
    
    assign wb_stall_o = wb_cyc_i & wb_stb_i & wb_we_i & is_data_trigger & !core_data_ready;

    wire req_accepted = wb_cyc_i & wb_stb_i & ~wb_stall_o;
    
    

    ascon_core u_core (
        .clk(wb_clk_i),
        .rst_n(!(wb_rst_i || ctrl_soft_rst)),
        .start(ctrl_start),
        .decrypt_mode(ctrl_decrypt),
        .variant(ctrl_variant),
        .padding_missed(6'd16 - {1'b0, auto_byte_counter}),
        .key(reg_key),
        .nonce(reg_nonce),
        .data_in(core_data_in),
        .data_valid(fifo_in_wr),
        .data_last(input_is_last),
        .is_ad(ctrl_is_ad),
        .data_ready(core_data_ready),
        .data_out(core_data_out),
        .out_valid(core_out_valid),
        .tag_valid(core_tag_valid),
        .tag_out(core_tag_result)
    );

    // Ham dem so bit 1 trong byte-select (Tinh padding tu dong)
    function [2:0] count_ones(input [3:0] sel);
        count_ones = sel[0] + sel[1] + sel[2] + sel[3];
    endfunction
    
    //Wishbone ACK
    always @(posedge wb_clk_i) begin
        if (wb_rst_i)
            wb_ack_o <= 1'b0;
        else
            wb_ack_o <= req_accepted & wb_cyc_i; // ACK trễ 1 chu kỳ clock
    end

    always @(posedge wb_clk_i) begin
        if (wb_rst_i) begin
            wb_ack_o     <= 0;
            wb_dat_o     <= 0;
            reg_key      <= 0;
            reg_nonce    <= 0;
            reg_tag_out  <= 0;
            ctrl_start   <= 0;
            ctrl_decrypt <= 0;
            ctrl_is_ad   <= 0;
            ctrl_variant <= 0;
            auto_byte_counter <= 0; 
            data_word0 <= 0; data_word1 <= 0; data_word2 <= 0; data_word3 <= 0;
            fifo_in_wr   <= 0;
            input_is_last<= 0;
            irq_done_reg <= 0;
        end else begin
            ctrl_start   <= 0;
            ctrl_soft_rst<= 0;
            wb_ack_o     <= 0;
            
            // Tu dong luu Tag khi core bao xong
            if (core_tag_valid) begin
                reg_tag_out  <= core_tag_result;
                irq_done_reg <= 1'b1;
            end
            
            

    // 3. Xử lý Lệnh từ CPU (Chỉ lọt vào đây khi bus đã handshake thành công)
    if (req_accepted) begin
        if (wb_we_i) begin
            case (addr)
                8'h00: begin 
                    irq_done_reg <= 0; // Clear IRQ
                    if (wb_dat_i[0]) ctrl_start <= 1; // Sẽ sinh xung 1 clock
                        ctrl_decrypt    <= wb_dat_i[1];
                        ctrl_is_ad      <= wb_dat_i[2];
                        ctrl_variant    <= wb_dat_i[3];
                    if (wb_dat_i[4]) ctrl_soft_rst <= 1; // Sẽ sinh xung 1 clock
                end
                        
                        // Nạp Key
                8'h10: reg_key[31:0]   <= wb_dat_i;
                8'h14: reg_key[63:32]  <= wb_dat_i;
                8'h18: reg_key[95:64]  <= wb_dat_i;
                8'h1C: reg_key[127:96] <= wb_dat_i;

                        // Nạp Nonce
                8'h20: reg_nonce[31:0]   <= wb_dat_i;
                8'h24: reg_nonce[63:32]  <= wb_dat_i;
                8'h28: reg_nonce[95:64]  <= wb_dat_i;
                8'h2C: reg_nonce[127:96] <= wb_dat_i;

                        // Nạp Data Words
                8'h40: begin 
                    if(wb_sel_i[0]) data_word3[7:0]   <= wb_dat_i[7:0];
                    if(wb_sel_i[1]) data_word3[15:8]  <= wb_dat_i[15:8];
                    if(wb_sel_i[2]) data_word3[23:16] <= wb_dat_i[23:16];
                    if(wb_sel_i[3]) data_word3[31:24] <= wb_dat_i[31:24];
                    auto_byte_counter <= auto_byte_counter + count_ones(wb_sel_i);
                end
                8'h44: begin 
                    if(wb_sel_i[0]) data_word2[7:0]   <= wb_dat_i[7:0];
                    if(wb_sel_i[1]) data_word2[15:8]  <= wb_dat_i[15:8];
                    if(wb_sel_i[2]) data_word2[23:16] <= wb_dat_i[23:16];
                    if(wb_sel_i[3]) data_word2[31:24] <= wb_dat_i[31:24];
                    auto_byte_counter <= auto_byte_counter + count_ones(wb_sel_i);
                end
                8'h48: begin 
                    if(wb_sel_i[0]) data_word1[7:0]   <= wb_dat_i[7:0];
                    if(wb_sel_i[1]) data_word1[15:8]  <= wb_dat_i[15:8];
                    if(wb_sel_i[2]) data_word1[23:16] <= wb_dat_i[23:16];
                    if(wb_sel_i[3]) data_word1[31:24] <= wb_dat_i[31:24];
                    auto_byte_counter <= auto_byte_counter + count_ones(wb_sel_i);
                end
                        
                // 0x4C: Trigger Normal Data (Dữ liệu cuối nạp qua 0x4C)
                8'h4C: begin 
                    if(wb_sel_i[0]) data_word0[7:0]   <= wb_dat_i[7:0];
                    if(wb_sel_i[1]) data_word0[15:8]  <= wb_dat_i[15:8];
                    if(wb_sel_i[2]) data_word0[23:16] <= wb_dat_i[23:16];
                    if(wb_sel_i[3]) data_word0[31:24] <= wb_dat_i[31:24];
                    // Lệnh này được lọt vào chắc chắn là vì đã ko bị STALL
                    fifo_in_wr        <= 1; // Kích hoạt ghi FIFO 1 clock
                    input_is_last     <= 0;
                    auto_byte_counter <= 0; // Reset bộ đếm sau khi nạp xong
                    data_word1 <= 0; data_word2 <= 0; data_word3 <= 0; // Xóa buffer
                end

                // 0x50: Trigger Last Data
                8'h50: begin
                    if(wb_sel_i[0]) data_word0[7:0]   <= wb_dat_i[7:0];
                    if(wb_sel_i[1]) data_word0[15:8]  <= wb_dat_i[15:8];
                    if(wb_sel_i[2]) data_word0[23:16] <= wb_dat_i[23:16];
                    if(wb_sel_i[3]) data_word0[31:24] <= wb_dat_i[31:24];
                    fifo_in_wr        <= 1;
                    input_is_last     <= 1;
                    auto_byte_counter <= 0;
                    data_word1 <= 0; data_word2 <= 0; data_word3 <= 0;
                end
                        
                // 0x54: Trigger Last No Data
                8'h54: begin
                    fifo_in_wr        <= 1;
                    input_is_last     <= 1;
                    auto_byte_counter <= 0;
                end

                // 0x58: Trigger Normal No Data
                8'h58: begin
                    fifo_in_wr        <= 1;
                    input_is_last     <= 0;
                    auto_byte_counter <= 0;
                end
            endcase
            end else begin
                // Đọc thanh ghi
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
        end
    end

    assign irq_done = irq_done_reg;

endmodule
