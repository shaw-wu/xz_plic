/* verilator lint_off UNUSEDSIGNAL */
`timescale 1ns/1ps
module plic_regfile #(
	parameter ADDR_BITS = 32,
	parameter DATA_BITS = 32,
	parameter ARSIZE_BITS = 3,
	parameter WSTRB_BITS = 4,
	parameter BASE = 32'h10000000,
	parameter REG_NUM = 1024,
	parameter SOURCES = 8,
	parameter PRIORITY_BITS = 3,
	parameter SOURCES_BITS = 3,
	parameter TARGETS = 1
)(
	input clk,
	input rstn,
	input  [ADDR_BITS-1:0]   raddr,
	input  [ADDR_BITS-1:0]   waddr,
	output [DATA_BITS-1:0]   rdata,
	input  [DATA_BITS-1:0]   wdata,
	input  [WSTRB_BITS-1:0]  wen,
	output r_overflow,
	output w_overflow,
  output     [SOURCES      -1:0] el,           //Edge/Level sensitive for each source
  input      [SOURCES      -1:0] ip,           //Interrupt Pending for each source

  output     [SOURCES      -1:0] ie[TARGETS],  //Interrupt enable per source, for each target
  output reg [PRIORITY_BITS-1:0] p [SOURCES],  //Priority for each source
  output reg [PRIORITY_BITS-1:0] th[TARGETS],  //Priority Threshold for each target

  input      [SOURCES_BITS -1:0] id[TARGETS],  //Interrupt ID for each target
  output reg [TARGETS      -1:0] claim,        //Interrupt Claim
  output reg [TARGETS      -1:0] complete      //Interrupt Complete
);

//寄存器分块（32bits为单位）
localparam TOTAL_SOURCES = SOURCES + 1;
localparam PENDING_BLOCKS = (TOTAL_SOURCES + 31) / 32;
localparam PENDING_LAST_BITS = (TOTAL_SOURCES % 32 == 0) ? 32 : (TOTAL_SOURCES % 32);
localparam EDGE_BLOCKS = (TOTAL_SOURCES + 31) / 32;
localparam EDGE_LAST_BITS = (TOTAL_SOURCES % 32 == 0) ? 32 : (TOTAL_SOURCES % 32);
localparam ENABLE_BLOCK_I = TARGETS;
localparam ENABLE_BLOCK_J = (TOTAL_SOURCES + 31) / 32;
localparam ENABLE_LAST_BITS = (TOTAL_SOURCES % 32 == 0) ? 32 : (TOTAL_SOURCES % 32);
localparam TARGET_BLOCK = TARGETS;

//地址映射
wire [ADDR_BITS-1:0] map_raddr;
assign map_raddr = raddr - BASE;
wire [ADDR_BITS-1:0] map_waddr;
assign map_waddr = waddr - BASE;
wire [15:0] addr_t;
assign addr_t = map_raddr[27:12] - 16'h2000;

//寄存器文件
reg [DATA_BITS-1:0] priority   [0:SOURCES]                              ; //0x0000_0000 ~ 0x0000_0ffc (4096Byte,1024 of sources)
																													                //0x0000_0000 source 0 does not exist
reg [DATA_BITS-1:0] pending	   [0:PENDING_BLOCK-1  ]                    ; //0x0000_1000 ~ 0x0000_107c (1024bits mask)
reg [DATA_BITS-1:0] edge_level [0:EDGE_BLOCK-1     ]										; //0x0000_1100 ~ 0x001f_117c (4096Byte,1024 of sources) (use reserved bits)
reg [DATA_BITS-1:0] enable     [0:ENABLE_BLOCK_I-1 ][0:ENABLE_BLOCK_J-1]; //0x0000_2000 ~ 0x0000_217c (1024*15871bits mask)
reg [DATA_BITS-1:0] target     [0:TARGET_BLOCK][0:1]                    ; //0x0020_0000 ~ 0x03ff_f004 (96*15871bits, 15871 of targets) 
																														              //0x0020_0000 ~ 0x0020_0004, 0x0201_000 ~ 0x3fff_004

//寻址空间
localparam PRIORITY_START   = 32'h0000_0000;
localparam PRIORITY_END     = 32'h0000_0000 + SOURCES * 4;
localparam PENDING_START    = 32'h0000_1000;
localparam PENDING_END      = 32'h0000_1000 + (SOURCES - 1) / 32;
localparam EDGE_START				= 32'h0000_1100;
localparam EDGE_END      		= 32'h0000_1100 + (SOURCES - 1) / 32;
localparam ENABLE_START     = 32'h0000_2000;
localparam ENABLE_END       = 32'h0020_1000 + (TARGETS - 1) * 128 + 124;
localparam ENABLE_START_O   = 32'h0000_0000;
localparam ENABLE_END_O     = 32'h0000_0000 + (SOURCES - 1) / 32;
localparam TARGET_START     = 32'h0020_0000;
localparam TARGET_END       = 32'h0020_0000 + (TARGETS - 1) * 4096 + 4;
localparam TARGET_START_O   = 32'h0000_0000;
localparam TARGET_END_O     = 32'h0000_0004;

//地址溢出判断
reg r_priority_overflow;
reg r_pending_overflow;
reg r_edge_overflow;
reg r_enable_overflow;
reg r_target_overflow;
reg w_priority_overflow;
reg w_pending_overflow;
reg w_edge_overflow;
reg w_enable_overflow;
reg w_target_overflow;

wire r_addr_overflow;
assign r_addr_overflow = r_priority_overflow && r_pending_overflow && r_enable_overflow && r_target_overflow && r_edge_overflow;
assign r_overflow = r_addr_overflow;
wire w_addr_overflow;
assign w_addr_overflow = w_priority_overflow && w_pending_overflow && w_enable_overflow && w_target_overflow && w_edge_overflow;
assign w_overflow = w_addr_overflow;

always @(*) begin
	//r_priority_overflow
	if (map_raddr >= PRIORITY_START && map_raddr <= PRIORITY_END) r_priority_overflow = 0;
	else                                                          r_priority_overflow = 1;
	//r_pending_overflow
	if (map_raddr >= PENDING_START && map_raddr <= PENDING_END)   r_pending_overflow = 0;
	else                                                          r_pending_overflow = 1;
	//r_edge_overflow
	if (map_raddr >= EDGE_START && map_raddr <= EDGE_END)         r_edge_overflow = 0;
	else                                                          r_edge_overflow = 1;
	//r_enable_overflow
	if ( map_raddr                 >= ENABLE_START   &&  map_raddr                 <= ENABLE_END   &&	
		  (map_raddr & 32'h0000007f) >= ENABLE_START_O && (map_raddr & 32'h0000007f) <= ENABLE_END_O    ) r_enable_overflow = 0;
	else                                                                                                r_enable_overflow = 1;
	//r_target_overflow
	if ( map_raddr                 >= TARGET_START   &&  map_raddr                 <= TARGET_END   &&	
		  (map_raddr & 32'h00000003) >= TARGET_START_O && (map_raddr & 32'h00000003) <= TARGET_END_O    ) r_target_overflow = 0;
	else                                                                                                r_target_overflow = 1;
	//w_priority_overflow
	if (map_waddr >= PRIORITY_START && map_waddr <= PRIORITY_END) w_priority_overflow = 0;
	else                                                          w_priority_overflow = 1;
	//w_pending_overflow
	if (map_waddr >= PENDING_START && map_waddr <= PENDING_END)   w_pending_overflow = 0;
	else                                                          w_pending_overflow = 1;
	//w_edge_overflow
	if (map_waddr >= EDGE_START && map_waddr <= EDGE_END)         w_edge_overflow = 0;
	else                                                          w_edge_overflow = 1;
	//w_enable_overflow
	if ( map_waddr                 >= ENABLE_START   &&  map_waddr                 <= ENABLE_END   &&	
		  (map_waddr & 32'h0000007f) >= ENABLE_START_O && (map_waddr & 32'h0000007f) <= ENABLE_END_O    ) w_enable_overflow = 0;
	else                                                                                                w_enable_overflow = 1;
	//w_target_overflow
	if ( map_waddr                 >= TARGET_START   &&  map_waddr                 <= TARGET_END   &&	
		  (map_waddr & 32'h00000003) >= TARGET_START_O && (map_waddr & 32'h00000003) <= TARGET_END_O    ) w_target_overflow = 0;
	else                                                                                                w_target_overflow = 1;
end

//读数据
reg [DATA_BITS-1:0] rdata_r;
always @(*) begin
	if (r_addr_overflow)           rdata_r = 0;//不在寻址空间 / 保留值和未使用区域的硬连线
	if      (!r_priority_overflow) rdata_r = priority  [map_raddr                ];
	else if (!r_pending_overflow ) rdata_r = pending   [map_raddr - PENDING_START];
	else if (!r_edge_overflow    ) rdata_r = edge_level[map_raddr - EDGE_START   ];
	else if (!r_enable_overflow  ) rdata_r = enable    [(map_raddr - ENABLE_START) >> 7][map_raddr & 32'h0000007f];
	else if (!r_target_overflow  ) begin 	
		if ((map_raddr & 32'h00000003) == 32'h00000000) rdata_r = target [(map_raddr - TARGET_START) >> 32'h00001000][31: 0];
		else                                           rdata_r = id[addr_t];
	end
end
assign rdata = rdata_r
				
//source0 硬连线
integer k;
always @(*) begin
	for (k = 0; k < TARGETS; k = k + 1) begin
		enable[k][0][0] = 0;
	end
	edge_level [0][0] = 0;
	priority[0] = 0;
end
wire [SOURCES:0] ex_ip;
assign ex_ip = {ip, 0};

//写数据
wire [31:0] mask_wdata;
assign mask_wdata = {{8{wen[3]}}, {8{wen[2]}}, {8{wen[1]}}, {8{wen[0]}}};

integer i, j;
always @(posedge clk or negedge rstn) begin
	if (!rstn) begin
    for (i = 0; i <= SOURCES; i = i + 1) begin
      priority[i] <= {DATA_BITS{1'b0}};
    end
    for (i = 0; i < PENDING_BLOCK; i = i + 1) begin
      pending[i] <= {DATA_BITS{1'b0}};
    end
    for (i = 0; i < EDGE_BLOCK; i = i + 1) begin
      edge_level[i] <= {DATA_BITS{1'b0}};
    end
    for (i = 0; i < ENABLE_BLOCK_I; i = i + 1) begin
      for (j = 0; j < ENABLE_BLOCK_J; j = j + 1) begin
        enable[i][j] <= {DATA_BITS{1'b0}};
      end
    end
    for (i = 0; i < TARGET_BLOCK; i = i + 1) begin
      for (j = 0; j < 2; j = j + 1) begin
        target[i][j] <= {DATA_BITS{1'b0}};
      end
    end
	end else begin
		//pending(readonly)
		for (i = 0; i < PENDING_BLOCKS; i = i + 1) begin
			if(i == PENDING_BLOCKS - 1) 
				pending[i][PENDING_LAST_BITS-1:1] <= ex_ip[i*32+PENDING_LAST_BITS-1:i*32];
			else 
				pending[i] <= ex_ip[i*32+31:i*32];
		end
		if (wen != 0)begin
			if      (!w_priority_overflow) priority  [ map_waddr                ] <= wdata & mask_wdata;
			if      (!w_edge_overflow    ) edge_level[ map_waddr - EDGE_START   ] <= wdata & mask_wdata;
			else if (!w_enable_overflow  ) enable    [(map_waddr - ENABLE_START) >> 7][map_waddr & 32'h0000007f] <= wdata & mask_wdata;
			else if (!w_target_overflow  ) begin 	
				if (((map_waddr - TARGET_START) & 32'h00000003) == 32'h00000000) target[(map_waddr - TARGET_START) >> 32'h00001000][31: 0] <= wdata & mask_wdata;
				else                                                             target[(map_waddr - TARGET_START) >> 32'h00001000][63:32] <= wdata & mask_wdata;
			end
		end
	end
end

//PLIC核心通路
genvar m, n;
generate
	//edge_level
	for (n = 0; n < EDGE_BLOCK; n = n + 1) begin
		if (n == EDGE_LAST_BITS - 1)
			assign el[n*32+EDGE_LAST_BITS-1:n*32] = edge_level[m][n][EDGE_LAST_BITS-1:0];
		else 
			assign el[m][n*32+31:n*32] = edge_level[m][n];
	end
	//enable
	for (m = 0; m < ENABLE_BLOCK_I; m = m + 1) begin
		for (n = 0; n < ENABLE_BLOCK_J; n = n + 1) begin
			if (n == ENABLE_BLOCK_J - 1)
				assign ie[m][n*32+ENABLE_LAST_BITS-1:n*32] = enable[m][n][ENABLE_LAST_BITS-1:0];
			else 
				assign ie[m][n*32+31:n*32] = enable[m][n];
		end
	end
	//priority
	for (m = 0; m < TOTAL_SOURCES; m = m + 1)begin
		assign p[m] = priority[m][PRIORITY_BITS-1:0];
	end
	//threshold
	for (m = 0; m < TARGET_BLOCK; m = m + 1) begin
		assign th[m] = target[m][0][PRIORITY_BITS-1:0];
	end
endgenerate

endmodule
