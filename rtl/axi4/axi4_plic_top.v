//PLIC Port : AXI4
//Surport burst mode and R/W chanel independent transmission.
`timescale 1ns/1ps
module axi4_plic_top #(
  //AXI Parameters
  parameter ADDR_BITS = 32,
  parameter DATA_BITS = 32,
	parameter LOGSIZE_BITS = 3,
	parameter LEN_BITS = 8,
	parameter BURST_BITS = 2,
  parameter RESP_BITS = 2,
	parameter WSTRB_BITS = 4,
  //PLIC Parameters
  parameter SOURCES           = 8, //Number of interrupt sources
  parameter TARGETS           = 1, //Number of interrupt targets
	parameter TARGET_BITS      = 1,
  parameter SOURCES_BITS  = 4, //$clog2(SOURCES+1), 0=reserved
  parameter PRIORITY_BITS = 3, //$clog2(PRIORITIES)
  parameter PRIORITIES        = 8, //Number of Priority levels
  parameter MAX_PENDING_COUNT = 8 //Max. number of 'pending' events
)(
  input                         PRESETn,
                                PCLK,
	//AXI4
	input [ADDR_BITS-1:0]    araddr,
	input									   arvalid,
	output									 arready,
	input [LOGSIZE_BITS-1:0] arsize,
  input [LEN_BITS-1:0]     arlen,
	input [BURST_BITS-1:0]   arburst,
	output reg [DATA_BITS-1:0] rdata,
	output                     rvalid,
	input                      rready,
	output										 rlast,
	output reg [RESP_BITS-1:0] rresp,
	input [ADDR_BITS-1:0]    awaddr,
	input                    awvalid,
	output                   awready,
	input [LOGSIZE_BITS-1:0] awsize,
  input [LEN_BITS-1:0]     awlen,
	input [BURST_BITS-1:0]   awburst,
	input [DATA_BITS-1:0]  wdata,
	input                  wvalid,
	output                 wready,
	input [WSTRB_BITS-1:0] wstrb,
	input                  wlast,
	output                     bvalid,
	input                      bready,
	output reg [RESP_BITS-1:0] bresp,
  input      [SOURCES     -1:0] src,       //Interrupt sources
  output reg [TARGETS     -1:0] irq,        //Interrupt Requests
	output r_overflow,
	output w_overflow
);


  //Decoded registers
	wire [SOURCES-1      :0] el;
  wire [SOURCES-1      :0] ip;
  wire [PRIORITY_BITS-1:0] p  [SOURCES];
  wire [SOURCES-1      :0] ie [TARGETS];
  wire [PRIORITY_BITS-1:0] th [TARGETS];
  wire [SOURCES_BITS -1:0] id [TARGETS];

  wire [TARGETS      -1:0] claim,
                          complete;

/* verilator lint_off UNUSEDSIGNAL */
  wire [SOURCES      :0] _el;
  wire [SOURCES      :0] _ie [TARGETS];
/* verilator lint_off UNUSEDSIGNAL */

  //总线信号锁存
	reg [LOGSIZE_BITS-1:0] reg_arsize;
	reg [BURST_BITS-1:0]   reg_arburst;
	reg [ADDR_BITS-1:0]    reg_araddr;
	reg [LEN_BITS-1:0]     reg_arlen;
	reg [LEN_BITS-1:0]     r_count;
	reg [LOGSIZE_BITS-1:0] reg_awsize;
	reg [BURST_BITS-1:0]   reg_awburst;
	reg [ADDR_BITS-1:0]    reg_awaddr;
	reg [LEN_BITS-1:0]     reg_awlen;
	reg [DATA_BITS-1:0]    reg_wdata;
	reg [WSTRB_BITS-1:0]   reg_wstrb;
	reg										 reg_wlast;

	//寄存器数据/控制信号
	wire [DATA_BITS-1:0] wire_rdata /* verilator public */;
	wire [WSTRB_BITS-1:0] wen;

	//读写地址偏移（突发传输）
	reg [ADDR_BITS-1:0]   r_offset, w_offset;

	//读状态机
	parameter READ_IDLE = 1'b0;
	parameter READ_WAIT_READY = 1'b1;
	reg read_state;

	//写状态机
	parameter WRITE_IDLE  = 2'b00;
	parameter WRITE_DATA  = 2'b01;
	parameter WRITE_DELAY = 2'b10;
	parameter WRITE_RESP  = 2'b11;
	reg [1:0] write_state;

	/*读状态机*/
	//状态转移规则
	always @(posedge PCLK or negedge PRESETn) begin
		if (!PRESETn) begin
			read_state <= READ_IDLE;
		end else begin
			case (read_state) 
				READ_IDLE : begin
					if (arvalid) begin
						read_state <= READ_WAIT_READY;
					end else begin
						read_state <= READ_IDLE;
					end
				end
				READ_WAIT_READY : begin
					if (rready & (r_count == 1)) begin
						read_state <= READ_IDLE;
					end else begin
						read_state <= READ_WAIT_READY;
					end
				end
				default : read_state <= READ_IDLE;
			endcase
		end
	end
				
	//读事务处理
	always @(posedge PCLK or negedge PRESETn) begin
	  if (!PRESETn) begin
      reg_araddr  <= {ADDR_BITS{1'b0}};
			reg_arsize  <= {LOGSIZE_BITS{1'b0}};
			reg_arlen <= {LEN_BITS{1'b0}};
			r_count   <= {LEN_BITS{1'b0}};
			reg_arburst <= {BURST_BITS{1'b0}};
			rdata  <= {DATA_BITS{1'b0}};
		end else begin	
			case (read_state)
				READ_IDLE : begin
					if (arvalid) begin 
						reg_araddr  <= araddr;
						reg_arsize  <= arsize;
						reg_arlen   <= arlen;
						r_count     <= arlen + 1;
						reg_arburst <= arburst;
					end else begin
						reg_araddr  <= {ADDR_BITS{1'b0}};
						reg_arsize  <= {LOGSIZE_BITS{1'b0}};
						reg_arlen <= {LEN_BITS{1'b0}};
						r_count   <= {LEN_BITS{1'b0}};
						reg_arburst <= {BURST_BITS{1'b0}};
					end
				end
				READ_WAIT_READY : begin
					rresp <= 2'b0;
					rdata <= wire_rdata;
					if (rready) begin 
						reg_araddr <= reg_araddr + r_offset;
						r_count  <= r_count - 1;
					end
				end
				default : rdata <= 0;
			endcase
		end
	end

  /*写状态机*/
	//状态转移规则
	always @(posedge PCLK or negedge PRESETn) begin
		if (!PRESETn) begin
			write_state <= WRITE_IDLE;
		end else begin
			case (write_state) 
				WRITE_IDLE : begin
					if (awvalid) begin
						write_state <= WRITE_DATA;
					end else begin
						write_state <= WRITE_IDLE;
					end
				end
				WRITE_DATA : begin
					if (wvalid) begin
						write_state <= WRITE_DELAY;
					end else begin
						write_state <= WRITE_DATA;
					end	
				end
				WRITE_DELAY: begin
					if (reg_wlast) begin
						write_state <= WRITE_RESP;	
					end else begin
						write_state <= WRITE_DATA;
					end
				end
				WRITE_RESP : begin
					if (bready) begin
						write_state <= WRITE_IDLE;
					end else begin
						write_state <= WRITE_RESP;
					end
				end
				default : write_state <= WRITE_IDLE;
			endcase
		end
	end

	//写事务处理
	always @(posedge PCLK or negedge PRESETn) begin
	  if (!PRESETn) begin
			reg_awsize <= {LOGSIZE_BITS{1'b0}};
			reg_awburst <= {BURST_BITS{1'b0}};
			reg_awaddr <= {ADDR_BITS{1'b0}};
			reg_awlen  <= {LEN_BITS{1'b0}};
			reg_wdata <= {DATA_BITS{1'b0}};
			reg_wstrb <= {WSTRB_BITS{1'b0}};
			reg_wlast <= 0;
		end else begin	
			case (write_state) 
				WRITE_IDLE : begin
					if (awvalid) begin
						reg_awsize  <= awsize;
						reg_awburst <= awburst;
      			reg_awaddr  <= awaddr;
						reg_awlen   <= awlen;
					end else begin
						reg_awsize  <= {LOGSIZE_BITS{1'b0}};
						reg_awburst <= {BURST_BITS{1'b0}};
      			reg_awaddr  <= {ADDR_BITS{1'b0}};
						reg_awlen   <= {LEN_BITS{1'b0}};
					end
				end
				WRITE_DATA : begin
					if (wvalid) begin 
						reg_wdata <= wdata;
						reg_wlast <= wlast;
						reg_wstrb <= wstrb;
					end
				end
				WRITE_DELAY : begin
					reg_awaddr <= reg_awaddr + w_offset;
				end
				WRITE_RESP : begin
					if (bready) begin
						bresp <= 2'b0;
					end
				end
			endcase
		end
	end

	/*信号赋值*/
	//握手信号
	assign arready = (read_state == READ_IDLE);
	assign rvalid  = (read_state == READ_WAIT_READY);
	assign awready = (write_state == WRITE_IDLE);
	assign wready  = (write_state == WRITE_DATA);
	assign bvalid  = (write_state == WRITE_RESP);

	assign rlast = (r_count == 0);
	
	//寄存器写使能
	assign wen = {WSTRB_BITS{write_state == WRITE_DELAY}} & reg_wstrb;

	//地址偏移量
	always @(*) begin
		case (reg_arburst)
			2'b00 : r_offset = 32'h00000000;
			2'b01 : r_offset = 32'h00000001 << reg_arsize;
			2'b10 : r_offset = {24'b0,(reg_arlen + 8'b1)} << reg_arsize;
			default : r_offset = 32'h00000000;
		endcase
	end
	always @(*) begin
		case (reg_awburst)
			2'b00 : w_offset = 32'h00000000;
			2'b01 : w_offset = 32'h00000001 << reg_awsize;
			2'b10 : w_offset = {24'b0,(reg_awlen + 8'b1)} << reg_awsize;
			default : w_offset = 32'h00000000;
		endcase
	end

plic_regfile #(
	.ADDR_BITS    (ADDR_BITS     ),
	.DATA_BITS    (DATA_BITS     ), 
	.WSTRB_BITS   (WSTRB_BITS    ), 
	.BASE         (32'h10000000  ), 
	.SOURCES      (SOURCES       ),
	.PRIORITY_BITS(PRIORITY_BITS ),
	.SOURCES_BITS (SOURCES_BITS  ),
	.TARGETS      (TARGETS       ), 
	.TARGET_BITS  (TARGET_BITS   )
) r0(
	.clk       (PCLK			 ),
	.rstn      (PRESETn    ),
	.raddr     (reg_araddr ),
	.waddr     (reg_awaddr ),
	.rdata     (wire_rdata ),
	.wdata     (reg_wdata  ),
	.wen       (wen        ),
	.r_overflow(r_overflow ),
	.w_overflow(w_overflow ),
  .el        ( _el       ),
  .ip        ( ip        ),
  .ie        ( _ie       ),
  .p				 ( p         ),
  .th        ( th        ),
  .id        ( id        ),
  .claim     ( claim     ),
  .complete  ( complete  )
);

genvar i;
generate 
	for (i = 0; i < TARGETS; i = i + 1) begin
		assign ie[i] = _ie[i][SOURCES : 1];
	end
		assign el = _el[SOURCES : 1];
endgenerate

  plic_core #(
    .SOURCES           ( SOURCES           ),
    .TARGETS           ( TARGETS           ),
    .PRIORITIES        ( PRIORITIES        ),
    .MAX_PENDING_COUNT ( MAX_PENDING_COUNT ),
		.SOURCES_BITS      ( SOURCES_BITS      ),
		.PRIORITY_BITS     ( PRIORITY_BITS     )
  )
  plic_core_inst (
    .rst_n     ( PRESETn  ),
    .clk       ( PCLK     ),

    .src       ( src      ),
    .el        ( el       ),
    .ip        ( ip       ),
    .ie        ( ie       ),
    .ipriority ( p        ),
    .threshold ( th       ),

    .ireq      ( irq      ),
    .id        ( id       ),
    .claim     ( claim    ),
    .complete  ( complete )
  );

endmodule

