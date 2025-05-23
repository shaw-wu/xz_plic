module apb4_plic_top #(
  //APB Parameters
  parameter PADDR_SIZE = 32,
  parameter PDATA_SIZE = 32,

  //PLIC Parameters
  parameter SOURCES           = 8,//35,  //Number of interrupt sources
  parameter TARGETS           = 1,   //Number of interrupt targets
  parameter PRIORITIES        = 8,   //Number of Priority levels
	parameter TARGET_BITS       = 1,
  parameter SOURCES_BITS      = 4, //$clog2(SOURCES+1), 0=reserved
  parameter PRIORITY_BITS     = 3, //$clog2(PRIORITIES)
  parameter MAX_PENDING_COUNT = 8,   //Max. number of 'pending' events
  parameter HAS_THRESHOLD     = 1,   //Is 'threshold' implemented?
  parameter HAS_CONFIG_REG    = 1    //Is the 'configuration' register implemented?
)
(
  input                         PRESETn,
                                PCLK,

  //AHB Slave Interface
  input                         PSEL,
  input                         PENABLE,
  input      [PADDR_SIZE  -1:0] PADDR,
  input                         PWRITE,
  input      [PDATA_SIZE/8-1:0] PSTRB,
  input      [PDATA_SIZE  -1:0] PWDATA,
  output reg [PDATA_SIZE  -1:0] PRDATA,
  output                        PREADY,
  output                        PSLVERR,
  output                        r_overflow,
	output												w_oberflow,
  input      [SOURCES     -1:0] src,       //Interrupt sources
  output     [TARGETS     -1:0] irq        //Interrupt Requests
);

  wire apb_we, apb_re;
	wire [4:0] wen;

  //Decoded registers
  wire [SOURCES      -1:0] el;
  wire                     ip;
  wire [PRIORITY_BITS-1:0] p  [SOURCES];
  wire [SOURCES      -1:0] ie [TARGETS];
  wire [PRIORITY_BITS-1:0] th [TARGETS];
  wire [SOURCES_BITS -1:0] id [TARGETS];

  wire [TARGETS      -1:0] claim, complete;

  assign PREADY  = 1'b1;  //always ready
  assign PSLVERR = 1'b0;  //Never an error

  // APB Read/Write
  assign apb_re = PSEL & ~PENABLE & ~PWRITE;
  assign apb_we = PSEL &  PENABLE &  PWRITE;
	assign wen = {apb_re || apb_we, {4{apb_we}} & PSTRB};
	
	wire [PADDR_SIZE-1:0] _WADDR;
	wire [PADDR_SIZE-1:0] _RADDR;
	assign _WADDR = wen[4] ? PADDR : BASE + 32'h03ff_fffc;
	assign _RADDR = wen[4] ? BASE + 32'h03ff_fffc : PADDR;

  // Hookup Dynamic Register block
  plic_dynamic_registers #(
		.ADDR_BITS    (PADDR_SIZE    ),
		.DATA_BITS    (PDATA_SIZE    ), 
		.WSTRB_BITS   (PDATA_SIZE/8  ), 
		.BASE         (32'h10000000  ), 
		.SOURCES      (SOURCES       ),
		.PRIORITY_BITS(PRIORITY_BITS ),
		.SOURCES_BITS (SOURCES_BITS  ),
		.TARGETS      (TARGETS       ), 
		.TARGET_BITS  (TARGET_BITS   )
  )
  dyn_register_inst (
    .rst_n		 ( PRESETn		), //Active low asynchronous reset
    .clk       ( PCLK     	), //System clock

    .wen       ( wen[3:0] 	), //write cycle
    .waddr     ( _WADDR    	), //write address
    .raddr     ( _RADDR    	), //read address
    .wdata     ( PWDATA   	), //write data
    .rdata     ( PRDATA   	), //read data
		.r_overflow( r_overflow ),
		.w_overflow( w_overflow ),
    .el				 ( el         ), //Edge/Level
    .ip        ( ip         ), //Interrupt Pending
    .ie        ( ie         ), //Interrupt Enable
    .p         ( p          ), //Priority
    .th        ( th         ), //Priority Threshold
    .id        ( id         ), //Interrupt ID
    .claim     ( claim      ), //Interrupt Claim
    .complete  ( complete   )  //Interrupt Complete
 );

genvar i;
generate 
	for (i = 0; i < TARGETS; i = i + 1) begin
		assign ie[i] = _ie[i][SOURCES : 1];
	end
		assign el = _el[SOURCES : 1];
endgenerate

  // Hookup PLIC Core
  plic_core #(
    .SOURCES           ( SOURCES           ),
    .TARGETS           ( TARGETS           ),
    .PRIORITIES        ( PRIORITIES        ),
    .MAX_PENDING_COUNT ( MAX_PENDING_COUNT ),
		.SOURCES_BITS      ( SOURCES_BITS      ),
		.PRIORITY_BITS     ( PRIORITY_BITS	   )
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

endmodule : apb4_plic_top

