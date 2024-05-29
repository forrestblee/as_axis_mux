module beam_mux #(
   parameter int DWIDTH = 32
)
  (
   input  logic              clk, // 300 MHz
   input  logic              rst, // synchronous
   input  logic [1:0]        dac_sel,
   input  logic [DWIDTH-1:0] axis_S_source_tdata,
   input  logic              axis_S_source_tvalid,
   output logic              axis_S_source_tready,
   input  logic              axis_S_source_tlast,
   
   output logic [DWIDTH-1:0] axis_M_dac1_tdata,
   output logic              axis_M_dac1_tvalid,

   output logic [DWIDTH-1:0] axis_M_dac2_tdata,
   output logic              axis_M_dac2_tvalid,
   
   output logic [DWIDTH-1:0] axis_M_dac3_tdata,
   output logic              axis_M_dac3_tvalid

  );
   typedef enum {ROUNDROBIN, DAC1, DAC2, DAC3} TMODE;
   typedef enum {IDLE, TRANSMITTING, LAST_TRANS} STATE;
    
   // state machine variables
   TMODE trans_mode, next_tmode;
   logic[2:0] roundrobin_sel;
   STATE state, next_state;
   
   // AXIS variables
   logic[DWIDTH-1:0] axis_dac_tdata_buffer;
   logic             axis_dac_tvalid_buffer;
   logic             S_source_burst_start;
   logic             S_source_burst_end;

   assign S_source_burst_active = (axis_S_source_tready & axis_S_source_tvalid);
   assign S_source_burst_end =   (S_source_burst_active & axis_S_source_tlast);

   // STATE state machine /////////////////////////////////////////////////////
   always @(posedge clk)
   begin
      if (rst)
         state <= IDLE;
      else
         state <= next_state;
   end

   always_comb begin
      case (state)
         IDLE:
            if (S_source_burst_active)    // transaction starting or ongoing
               next_state = TRANSMITTING;
         TRANSMITTING:
            if (S_source_burst_end)       // transaction ending
               next_state = LAST_TRANS;
         LAST_TRANS:
            if (S_source_burst_active) 
               next_state = TRANSMITTING; // queue up another transaction
            else  
               next_state = IDLE;         // else go to idle
         default:
            next_state = next_state; // default state
      endcase
   end
   ////////////////////////////////////////////////////////////////////////////

   // MODE state machine //////////////////////////////////////////////////////
   always @(posedge clk)
   begin
      if (rst)
         trans_mode <= ROUNDROBIN;
      else
         trans_mode <= next_tmode;
   end

   always_comb begin
      next_tmode = next_tmode; // default state
      if (  state == LAST_TRANS // end of burst
         || state == IDLE) 
         case(dac_sel)
            2'b00:
               next_tmode = ROUNDROBIN;
            2'b01:
               next_tmode = DAC1;
            2'b10:
               next_tmode = DAC2;
            2'b11:
               next_tmode = DAC3;
            
         endcase
   end
   
   always @(posedge clk)
   begin
      if (rst)
         roundrobin_sel <= 3'b001;
      else
         // if in round robin mode and burst just completed, circular rotate of rr_mode
         if (trans_mode == ROUNDROBIN && state == LAST_TRANS)
         begin
         roundrobin_sel[2] <= roundrobin_sel[1];
         roundrobin_sel[1] <= roundrobin_sel[0];
         roundrobin_sel[0] <= roundrobin_sel[2];
         end
         // check for error modes if roundrobin_sel is not in a one-hot state - a little SEU protection
         else if ( ^roundrobin_sel == 1'b0 || &roundrobin_sel == 1'b1) // XOR of all bits or AND of all bits
            roundrobin_sel <= 3'b001; // reset to known state
   end


   // AXIS data handler ///////////////////////////////////////////////////////
   assign axis_S_source_tready = ~rst; // because there is no backpressure from the DACs, we can always be receiving data at 300MHz

   // we buffer the data because the state machine incurs a single clock delay 
   always @(posedge clk)
   begin
      if (rst)
      begin
         axis_dac_tdata_buffer <= '0;
         axis_dac_tvalid_buffer <= 1'b0;
      end
      else 
      begin
         if (S_source_burst_active)
         begin
            axis_dac_tdata_buffer <= axis_S_source_tdata;
            axis_dac_tvalid_buffer <= axis_S_source_tvalid;
         end
         else
         begin
            axis_dac_tdata_buffer <= '0;
            axis_dac_tvalid_buffer <= 1'b0;
         end
      end
   end
   ////////////////////////////////////////////////////////////////////////////

   // AXIS combo logic data mux ///////////////////////////////////////////////
   // this minimizes clock delay between the source, the mux, and the DACs

   // however, AXI protocol in general encourages signals to be registered and not the result of combinational logic 
   // if adherence to this rule is preferred, we can increase the clock delay to two and use the sequential logic (commented out below).
   always_comb begin
      // default values
      axis_M_dac1_tdata = '0;
      axis_M_dac1_tvalid = 1'b0;
      axis_M_dac2_tdata = '0;
      axis_M_dac2_tvalid = 1'b0;
      axis_M_dac3_tdata = '0;
      axis_M_dac3_tvalid = 1'b0;

      if (state == TRANSMITTING || state == LAST_TRANS)
         case (trans_mode)
            DAC1: begin
               axis_M_dac1_tdata = axis_dac_tdata_buffer;
               axis_M_dac1_tvalid = axis_dac_tvalid_buffer;
            end
            DAC2: begin
               axis_M_dac2_tdata = axis_dac_tdata_buffer;
               axis_M_dac2_tvalid = axis_dac_tvalid_buffer;
            end
            DAC3: begin
               axis_M_dac3_tdata = axis_dac_tdata_buffer;
               axis_M_dac3_tvalid = axis_dac_tvalid_buffer;
            end
            ROUNDROBIN: 
               case (roundrobin_sel)
                  3'b001:
                  begin
                     axis_M_dac1_tdata = axis_dac_tdata_buffer;
                     axis_M_dac1_tvalid = axis_dac_tvalid_buffer;
                  end
                  3'b010:
                  begin
                     axis_M_dac2_tdata = axis_dac_tdata_buffer;
                     axis_M_dac2_tvalid = axis_dac_tvalid_buffer;
                  end
                  3'b100:
                  begin
                     axis_M_dac3_tdata = axis_dac_tdata_buffer;
                     axis_M_dac3_tvalid = axis_dac_tvalid_buffer;
                  end
                     // default: 
                     // error state
               endcase
         endcase
   end

   // always @(posedge clk) begin
   //    if (rst) begin
   //       state_dly1 <= IDLE;
   //       trans_mode_dly1 <= ROUNDROBIN;
   //       roundrobin_sel_dly1 <= 3'b001;

   //       axis_M_dac1_tdata <= '0;
   //       axis_M_dac1_tvalid <= 1'b0;
   //       axis_M_dac2_tdata <= '0;
   //       axis_M_dac2_tvalid <= 1'b0;
   //       axis_M_dac3_tdata <= '0;
   //       axis_M_dac3_tvalid <= 1'b0;
   //    end
   //    else begin

   //       if (state == TRANSMITTING || state == LAST_TRANS) begin
   //          case (trans_mode)
   //             DAC1: begin
   //                axis_M_dac1_tdata <= axis_dac_tdata_buffer;
   //                axis_M_dac1_tvalid <= axis_dac_tvalid_buffer;
   //                axis_M_dac2_tdata <= '0;
   //                axis_M_dac2_tvalid <= 1'b0;
   //                axis_M_dac3_tdata <= '0;
   //                axis_M_dac3_tvalid <= 1'b0;
   //             end
   //             DAC2: begin
   //                axis_M_dac1_tdata <= '0;
   //                axis_M_dac1_tvalid <= 1'b0;
   //                axis_M_dac2_tdata <= axis_dac_tdata_buffer;
   //                axis_M_dac2_tvalid <= axis_dac_tvalid_buffer;
   //                axis_M_dac3_tdata <= '0;
   //                axis_M_dac3_tvalid <= 1'b0;
   //             end
   //             DAC3: begin
   //                axis_M_dac1_tdata <= '0;
   //                axis_M_dac1_tvalid <= 1'b0;
   //                axis_M_dac2_tdata <= '0;
   //                axis_M_dac2_tvalid <= 1'b0;
   //                axis_M_dac3_tdata <= axis_dac_tdata_buffer;
   //                axis_M_dac3_tvalid <= axis_dac_tvalid_buffer;
   //             end
   //             ROUNDROBIN: 
   //                case (roundrobin_sel)
   //                   3'b001: // DAC1
   //                   begin
   //                      axis_M_dac1_tdata <= axis_dac_tdata_buffer;
   //                      axis_M_dac1_tvalid <= axis_dac_tvalid_buffer;
   //                      axis_M_dac2_tdata <= '0;
   //                      axis_M_dac2_tvalid <= 1'b0;
   //                      axis_M_dac3_tdata <= '0;
   //                      axis_M_dac3_tvalid <= 1'b0;
   //                   end
   //                   3'b010: // DAC2
   //                   begin
   //                      axis_M_dac1_tdata <= '0;
   //                      axis_M_dac1_tvalid <= 1'b0;
   //                      axis_M_dac2_tdata <= axis_dac_tdata_buffer;
   //                      axis_M_dac2_tvalid <= axis_dac_tvalid_buffer;
   //                      axis_M_dac3_tdata <= '0;
   //                      axis_M_dac3_tvalid <= 1'b0;
   //                   end
   //                   3'b100: // DAC3
   //                   begin
   //                      axis_M_dac1_tdata <= '0;
   //                      axis_M_dac1_tvalid <= 1'b0;
   //                      axis_M_dac2_tdata <= '0;
   //                      axis_M_dac2_tvalid <= 1'b0;
   //                      axis_M_dac3_tdata <= axis_dac_tdata_buffer;
   //                      axis_M_dac3_tvalid <= axis_dac_tvalid_buffer;
   //                   end
   //                      // default: 
   //                      // error state
   //                endcase
   //          endcase
   //       end
   //       else begin
   //          axis_M_dac1_tdata <= '0;
   //          axis_M_dac1_tvalid <= 1'b0;
   //          axis_M_dac2_tdata <= '0;
   //          axis_M_dac2_tvalid <= 1'b0;
   //          axis_M_dac3_tdata <= '0;
   //          axis_M_dac3_tvalid <= 1'b0;
   //       end
   //    end
   // end

   ////////////////////////////////////////////////////////////////////////////

endmodule: beam_mux
  