// Adapter: slave Wishbone "co dien" (stb giu den khi ack) -> slave Wishbone B4 pipelined (co stall).
// Dat giua rvx_wb_interconnect (slot ASCON) va ascon_connect_wb.
// - Dua stb len phia pipelined DUNG MOT LAN cho moi giao dich (giu cho den khi stall = 0).
// - Sau khi duoc nhan, ha stb, cho ack cua wrapper roi chuyen ack nguoc lai cho interconnect.
module ascon_wb_adapter (
    input  wire        clk_i,
    input  wire        rst_i,

    // phia interconnect (co dien)
    input  wire [31:0] c_adr_i,
    input  wire [31:0] c_dat_i,
    output wire [31:0] c_dat_o,
    input  wire [3:0]  c_sel_i,
    input  wire        c_we_i,
    input  wire        c_cyc_i,
    input  wire        c_stb_i,
    output wire        c_ack_o,

    // phia ascon_connect_wb (pipelined)
    output wire [31:0] p_adr_o,
    output wire [31:0] p_dat_o,
    input  wire [31:0] p_dat_i,
    output wire [3:0]  p_sel_o,
    output wire        p_we_o,
    output wire        p_cyc_o,
    output wire        p_stb_o,
    input  wire        p_stall_i,
    input  wire        p_ack_i
);
    reg waiting;   // request da duoc wrapper nhan, dang cho ack

    assign p_adr_o = c_adr_i;
    assign p_dat_o = c_dat_i;
    assign p_sel_o = c_sel_i;
    assign p_we_o  = c_we_i;
    assign p_cyc_o = c_cyc_i;
    assign p_stb_o = c_cyc_i & c_stb_i & ~waiting;

    assign c_dat_o = p_dat_i;
    assign c_ack_o = waiting & p_ack_i;

    always @(posedge clk_i) begin
        if (rst_i)
            waiting <= 1'b0;
        else if (p_stb_o & ~p_stall_i)
            waiting <= 1'b1;
        else if (c_ack_o)
            waiting <= 1'b0;
    end
endmodule