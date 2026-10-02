module ram_connect_wb #(
    parameter MEMORY_SIZE      = 8192,
    parameter MEMORY_INIT_FILE = ""
)(
    //System Signal
    input  wire         clk_i,
    input  wire         rst_i,

    //Wishbone interface
    input  wire [31:0]  wb_adr_i,
    input  wire [31:0]  wb_dat_i,
    output wire [31:0]  wb_dat_o,
    input  wire         wb_we_i,
    input  wire [3:0]   wb_sel_i,
    input  wire         wb_stb_i,
    input  wire         wb_cyc_i,
    output wire         wb_stall_o,
    output wire         wb_ack_o
);

    // RAM interface
    wire [31:0] ram_rdata;
    
    //Handshake
    wire req_valid      = wb_cyc_i & wb_stb_i & ~wb_stall_o;
    wire ram_read_req   = req_valid & ~wb_we_i;
    wire ram_write_req  = req_valid &  wb_we_i;

    rvx_ram_wb #(
        .MEMORY_SIZE(MEMORY_SIZE),
        .MEMORY_INIT_FILE(MEMORY_INIT_FILE)
    ) ram_inst (
        .clock(clk_i),
        .reset(rst_i),
        .rw_address(wb_adr_i),
        .read_data(ram_rdata),
        .read_request(ram_read_req),
        .read_response(ram_read_resp),
        .write_data(wb_dat_i),
        .write_strobe(wb_sel_i),
        .write_request(ram_write_req),
        .write_response(ram_write_resp)
    );

    // ------------------------------
    // Simple Wishbone logic
    // ------------------------------
    //Stall
    assign wb_stall_o = 1'b0;

    //Internal wire

    assign wb_dat_o = ram_rdata;

    assign wb_ack_o = wb_cyc_i & (ram_read_resp | ram_write_resp);
endmodule
