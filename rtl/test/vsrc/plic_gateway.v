`timescale 1ns/1ps
module plic_gateway #(
  parameter MAX_PENDING_COUNT = 16
)
(
  input      rst_n,    //Active low asynchronous reset
             clk,      //System clock

  input      src,      //Interrupt source
  input      edge_lvl, //(rising) edge or level triggered

  output     ip,       //interrupt pending
  input      claim,    //interrupt claimed
  input      complete  //interrupt handling completed
);


  //////////////////////////////////////////////////////////////////
  //
  // Constants
  //
  localparam SAFE_MAX_PENDING_COUNT = (MAX_PENDING_COUNT >= 0) ? MAX_PENDING_COUNT : 0;
  localparam COUNT_BITS = $clog2(SAFE_MAX_PENDING_COUNT+1);
  localparam LEVEL = 1'b0,
             EDGE  = 1'b1;


  //////////////////////////////////////////////////////////////////
  //
  // Variables
  //
  reg                  src_dly, src_edge;
  reg [COUNT_BITS-1:0] nxt_pending_cnt, pending_cnt;
  reg                  decr_pending;
  reg [           1:0] ip_state;


  //////////////////////////////////////////////////////////////////
  //
  // Module Body
  //

  /** detect rising edge on interrupt source
   */
  always @(posedge clk,negedge rst_n)
    if (!rst_n)
    begin
        src_dly  <= 1'b0;
        src_edge <= 1'b0;
    end
    else
    begin
        src_dly  <= src;
        src_edge <= src & ~src_dly;
    end


  /** generate pending-counter
   */
	always @(*) begin
    case ({decr_pending,src_edge})
      2'b00: nxt_pending_cnt = pending_cnt; //do nothing
      2'b01: if (pending_cnt < SAFE_MAX_PENDING_COUNT)
               nxt_pending_cnt = pending_cnt +'h1;
             else
               nxt_pending_cnt = pending_cnt;
      2'b10: if (pending_cnt > 0)
               nxt_pending_cnt = pending_cnt -'h1;
             else
               nxt_pending_cnt = pending_cnt;
      2'b11: nxt_pending_cnt = pending_cnt; //do nothing
    endcase
	end


  always @(posedge clk,negedge rst_n)
    if      (!rst_n           ) pending_cnt <= 'h0;
    else if ( edge_lvl != EDGE) pending_cnt <= 'h0;
    else                        pending_cnt <= nxt_pending_cnt;


  /** generate interrupt pending
   *  1. assert IP
   *  2. target 'claims IP'
   *     clears IP bit
   *     blocks IP from asserting again
   *  3. target 'completes' 
   */
  always @(posedge clk,negedge rst_n)
    if (!rst_n)
    begin
        ip_state     <= 2'b00;
        decr_pending <= 1'b0;
    end
    else
    begin
        decr_pending <= 1'b0; //strobe signal

        case (ip_state)
          //wait for interrupt request from source
          2'b00  : if ((edge_lvl == EDGE  && |nxt_pending_cnt) ||
                       (edge_lvl == LEVEL && src             ))
                   begin
                       ip_state     <= 2'b01;
                       decr_pending <= 1'b1; //decrement 
                   end

          //wait for 'interrupt claim'
          2'b01  : if (claim   ) ip_state <= 2'b10;

          //wait for 'interrupt completion'
          2'b10  : if (complete) ip_state <= 2'b00;

          //oops ...
          default: ip_state <= 2'b00;
        endcase
    end

  //IP-bit is ip_state LSB
  assign ip = ip_state[0];

endmodule
