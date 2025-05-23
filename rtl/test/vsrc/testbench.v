`timescale 1ns/1ps
module testbench(
	output reg  [31:0] PRDATA,
	output reg  PREADY,	
	output reg  PSLVERR,	
	output reg  r_overflow,
	output reg  w_overflow,
	output irq
);

	reg rstn	 ;
	reg clk    ;
	reg PSEL   ;
	reg PENABLE;
	reg [31:0] PADDR	 ;
	reg PWRITE ;
	reg [3:0] PSTRB  ;
	reg [31:0] PWDATA ;
	reg [7:0]  src;

	wire [31:0] _PRDATA;
	wire _PREADY			 ;	
	wire _PSLVERR			 ;	
	wire _r_overflow	 ;
	wire _w_overflow	 ;
	wire _irq					 ;

always @(*) begin
	PRDATA     = _PRDATA;
	PREADY     = _PREADY;
	PSLVERR    = _PSLVERR;
	r_overflow = _r_overflow;
	w_overflow = _w_overflow;
	irq        = _irq;
end

apb4_plic_top l1(
	.PRESETn	 (rstn),
	.PCLK			 (clk),
	.PSEL			 (PSEL),
	.PENABLE	 (PENABLE),
	.PADDR		 (PADDR),
	.PWRITE		 (PWRITE),
	.PSTRB		 (PSTRB),
	.PWDATA		 (PWDATA),
	.PRDATA		 (_PRDATA),
	.PREADY		 (_PREADY),
	.PSLVERR   (_PSLVERR),
	.src       (src),
	.irq       (_irq),
	.r_overflow(_r_overflow),
	.w_overflow(_w_overflow)
);

initial begin
	clk = 1;
	forever begin
		#1 clk = ~clk;
	end
end

initial begin
	src = 0;
	rstn = 0;
	#100
	rstn = 1;
	//priority set
	#20
	PSEL = 1;
	PADDR = 32'h1000_0004;
	PWRITE = 1;
	PSTRB  = 4'b1111;
	#2
	PWDATA = 32'd6;
	PENABLE = 1;
	#2
	PENABLE = 0;
	PADDR = 32'h1000_0008;
	#2
	PENABLE = 1;
	PWDATA = 32'd7;
	#2
	PENABLE = 0;
	PADDR = 32'h1000_000c;
	#2
	PENABLE = 1;
	PWDATA = 32'd5;
	#2
	PENABLE = 0;
	PADDR = 32'h1000_0010;
	#2
	PENABLE = 1;
	PWDATA = 32'd4;
	#2
	PENABLE = 0;
	PADDR = 32'h1000_0014;
	#2
	PENABLE = 1;
	PWDATA = 32'd3;
	#2
	PENABLE = 0;
	PADDR = 32'h1000_0018;
	#2
	PENABLE = 1;
	PWDATA = 32'd2;
	#2
	PENABLE = 0;
	PADDR = 32'h1000_001c;
	#2
	PENABLE = 1;
	PWDATA = 32'd1;
	#2
	PENABLE = 0;
	PADDR = 32'h1000_0020;
	#2
	PENABLE = 1;
	PWDATA = 32'd0;
	//enable set
	#2
	PENABLE = 0;
	PADDR = 32'h1000_2000;
	#2
	PENABLE = 1;
	PWDATA = 32'h0000_01fe;
	//threshold set
	#2
	PENABLE = 0;
	PADDR = 32'h1020_0000;
	#2
	PENABLE = 1;
	PWDATA = 32'd0;
	#2
	PENABLE = 0;
	PWRITE = 0;
	#10
	src = 8'b0000_0010;
  #10	
	PADDR = 32'h1020_0004;
	#2
	PENABLE = 1;
	#10
	PENABLE = 0;
	PWRITE = 1;
	#2
	PENABLE = 1;
	PWDATA = 32'd2;
	#2
	PENABLE = 0;
	#10
	src = 8'b0000_0110;
  #10	
	PWRITE = 0;
	PADDR = 32'h1020_0004;
	#2
	PENABLE = 1;
	#10
	PENABLE = 0;
	PWRITE = 1;
	#2
	PENABLE = 1;
	PWDATA = 32'd3;
	#2
	PENABLE = 0;
	#50 $finish;
end

endmodule
