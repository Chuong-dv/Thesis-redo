// rvx_wb_interconnect.v
// Generic Wishbone interconnect support NUM_SLAVES slaves.
// - m_adr_i/m_dat_i : master -> interconnect
// - s_adr_o/s_dat_o : interconnect -> all slaves (replicated)
// - s_dat_i          : concatenated slaves -> interconnect (NUM_SLAVES*32)
// - s_ack_i          : ack from each slave
//
module rvx_wb_interconnect #(
  parameter NUM_SLAVES = 6,
  parameter [NUM_SLAVES*32-1:0] SLAVE_ADDR_BASE = 0,
  parameter [NUM_SLAVES*32-1:0] SLAVE_ADDR_END  = 0
)(
  input  wire                      clk_i,
  input  wire                      rst_i,

  // Master side (single master)
  input  wire  [31:0]              m_adr_i,
  input  wire  [31:0]              m_dat_i,
  output reg   [31:0]              m_dat_o,
  input  wire  [3:0]               m_sel_i,
  input  wire                      m_we_i,
  input  wire                      m_cyc_i,
  input  wire                      m_stb_i,
  output wire                      m_ack_o,

  // Slave side (flattened buses)
  output wire [NUM_SLAVES-1:0]     s_cyc_o,
  output wire [NUM_SLAVES-1:0]     s_stb_o,
  output wire [NUM_SLAVES-1:0]     s_we_o,
  output wire [NUM_SLAVES*4-1:0]   s_sel_o,
  output wire [NUM_SLAVES*32-1:0]  s_adr_o,
  output wire [NUM_SLAVES*32-1:0]  s_dat_o,
  input  wire [NUM_SLAVES-1:0]     s_ack_i,
  input  wire [NUM_SLAVES*32-1:0]  s_dat_i
);

  // one-hot select signals (registered)
  reg  [NUM_SLAVES-1:0] slave_sel_reg;
  wire [NUM_SLAVES-1:0] slave_sel_comb;
  reg                    invalid_sel;   // ghi nh?n truy c?p ngo?i v?ng

  genvar gi;
  generate
    for (gi = 0; gi < NUM_SLAVES; gi = gi + 1) begin : GEN_SEL_COMB
      // extract base/end per slave from the parameter vectors
      // Note: SLAVE_ADDR_BASE and SLAVE_ADDR_END are bitpacked [N*32-1:0]
      wire [31:0] base = SLAVE_ADDR_BASE[gi*32 +: 32];
      wire [31:0] endd = SLAVE_ADDR_END[gi*32 +: 32];
      assign slave_sel_comb[gi] = (m_adr_i >= base) && (m_adr_i <= endd);
    end
  endgenerate

  // Register the selected slave at the beginning of a transaction
  always @(posedge clk_i or posedge rst_i) begin
    if (rst_i) begin
      slave_sel_reg <= {NUM_SLAVES{1'b0}};
      invalid_sel   <= 1'b0;
    end else begin
      // latch selection on first valid cycle of transaction
      if (m_cyc_i && m_stb_i && !(|slave_sel_reg) && !invalid_sel) begin
        if (|slave_sel_comb) begin
          slave_sel_reg <= slave_sel_comb;
        end else begin
          invalid_sel <= 1'b1;
        end
      end
      // clear when transaction ends
      if (!m_cyc_i) begin
        slave_sel_reg <= {NUM_SLAVES{1'b0}};
        invalid_sel   <= 1'b0;
      end
    end
  end

  // Drive slave side control signals: only the selected slave(s) see cyc/stb/we
  assign s_cyc_o = {NUM_SLAVES{m_cyc_i}} & slave_sel_reg;
  assign s_stb_o = {NUM_SLAVES{m_stb_i}} & slave_sel_reg;
  assign s_we_o  = {NUM_SLAVES{m_we_i}}  & slave_sel_reg;

  // replicate sel/adr/dat to all slaves (each slave will mask off using its sel)
  assign s_sel_o = {NUM_SLAVES{m_sel_i}};  // repeated 4-bit field
  assign s_adr_o = {NUM_SLAVES{m_adr_i}};  // repeated 32-bit field
  assign s_dat_o = {NUM_SLAVES{m_dat_i}};  // repeated 32-bit field

  // master ack is OR of ack_i from selected slave(s)
  assign m_ack_o = (invalid_sel & m_cyc_i & m_stb_i) | (|(s_ack_i & slave_sel_reg));

  // multiplex data back from selected slave into m_dat_o
  // use a combinational loop
  integer idx;
  always @(*) begin
    if (invalid_sel) begin
      m_dat_o = 32'h0;
    end else begin
      m_dat_o = 32'h0;
      for (idx = 0; idx < NUM_SLAVES; idx = idx + 1) begin
        if (slave_sel_reg[idx]) begin
          m_dat_o = s_dat_i[idx*32 +: 32];
        end
      end
    end
  end

endmodule
