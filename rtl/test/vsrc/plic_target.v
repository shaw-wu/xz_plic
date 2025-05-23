`timescale 1ns/1ps
module plic_target #(
  parameter SOURCES = 8,
  parameter PRIORITIES = 7,

  //These should be localparams, but that's not supported by all tools yet
  parameter SOURCES_BITS  = 3, //log(SOURCES) 
  parameter PRIORITY_BITS = 3
)
(
  input                          rst_ni,               //Active low asynchronous reset
                                 clk_i,                //System clock

  input      [SOURCES_BITS -1:0] id_i       [SOURCES], //Interrupt source
  input      [PRIORITY_BITS-1:0] priority_i [SOURCES], //Interrupt Priority

  input      [PRIORITY_BITS-1:0] threshold_i,          //Interrupt Priority Threshold

  output reg                     ireq_o,               //Interrupt Request (EIP)
  output reg [SOURCES_BITS -1:0] id_o                  //Interrupt ID
);
  //////////////////////////////////////////////////////////////////
  //
  // Constant
  //


  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  reg [SOURCES_BITS -1:0] id;
  reg [PRIORITY_BITS-1:0] pr;


  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  /** Select highest priority pending interrupt
   */
  plic_priority_index #(
    .SOURCES			( SOURCES				),
    .PRIORITIES  	( PRIORITIES   	),
    .HI          	( SOURCES -1   	),
    .LO          	( 0            	),
		.SOURCES_BITS	( SOURCES_BITS 	),
		.PRIORITY_BITS( PRIORITY_BITS )
  )
  priority_index_tree (
    .priority_i ( priority_i ),
    .idx_i      ( id_i       ),
    .priority_o ( pr         ),
    .idx_o      ( id         )
  );


  /** Generate output
  */
  always @(posedge clk_i,negedge rst_ni)
    if      (!rst_ni          ) ireq_o <= 1'b0;
    else if ( pr > threshold_i) ireq_o <= 1'b1;
    else                        ireq_o <= 1'b0;

  always @(posedge clk_i)
    id_o <= id;

endmodule 
