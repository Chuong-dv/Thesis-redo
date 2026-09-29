// ----------------------------------------------------------------------------
// Description:
//   Connects the simple rvx_core interface to the Wishbone bus.
//   RE-DEVELOPED: Optimized FSM and signal latching for stability.
//   This version replaces the user's `cpu2wb.v`.
// ----------------------------------------------------------------------------

module cpu_connect_wb (
    input  wire        clk_i,
    input  wire        rst_i,

    // CPU interface
    input  wire [31:0] rw_address,
    input  wire        read_request,
    output reg  [31:0] read_data,
    output reg         read_response,
    input  wire [31:0] write_data,
    input  wire [3:0]  write_strobe,
    input  wire        write_request,
    output reg         write_response,

    // Wishbone Master interface
    output reg  [31:0] wb_adr_o,
    output reg  [31:0] wb_dat_o,
    input  wire [31:0] wb_dat_i,
    output reg         wb_we_o,
    output reg  [3:0]  wb_sel_o,
    output reg         wb_stb_o,
    output reg         wb_cyc_o,
    input  wire        wb_stall_i,
    input  wire        wb_ack_i
);

    // FSM states
    localparam STATE_IDLE       = 1'b0;
    localparam STATE_WAIT_ACK   = 1'b1;

    reg state;

    always @(posedge clk_i or posedge rst_i) begin
        if (rst_i) begin
            state           <= STATE_IDLE;
            read_response   <= 1'b0;
            write_response  <= 1'b0;
            wb_stb_o        <= 1'b0;
            wb_cyc_o        <= 1'b0;
            wb_adr_o        <= 32'b0;
            wb_dat_o        <= 32'b0;
            wb_we_o         <= 1'b0;
            wb_sel_o        <= 4'b0;
            read_data       <= 32'b0;
        end else begin
            // Default assignments
            read_response   <= 1'b0;
            write_response  <= 1'b0;

            case (state)
                STATE_IDLE: begin
                    if (read_request || write_request) begin
                        wb_stb_o <= 1'b1;
                        wb_cyc_o <= 1'b1;
                        wb_adr_o <= rw_address;
                        wb_we_o  <= write_request;
                        wb_dat_o <= write_data;
                        wb_sel_o <= write_strobe;

                        state    <= STATE_WAIT_ACK;
                    end
                end

                STATE_WAIT_ACK: begin
                    if (!wb_stall_i) begin
                        wb_stb_o <= 1'b0;
                    end
                    if (wb_ack_i) begin
                        wb_stb_o <= 1'b0;
                        wb_cyc_o <= 1'b0;

                        if (wb_we_o) begin // Was a write
                            write_response <= 1'b1;
                        end else begin // Was a read
                            read_data     <= wb_dat_i;
                            read_response <= 1'b1;
                        end

                        state <= STATE_IDLE;
                    end
                end

                default: begin
                    state <= STATE_IDLE;
                end
            endcase
        end
    end
endmodule
