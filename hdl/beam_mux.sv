module beam_mux #(
   parameter int DWIDTH = 32,
   parameter int MAX_DEPTH = 2048
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
   typedef enum {IDLE, RECEIVING, LAST_TRANS} STATE;
    
   // state machine variables
   TMODE trans_mode, next_tmode;
   logic[2:0] roundrobin_sel;
   STATE state, next_state;
   
   // AXIS variables
   logic             S_source_burst_active;
   logic             S_source_burst_end;

   // data FIFO to store full packet transactions
   logic[DWIDTH-1:0] dac_data_buffer [0:MAX_DEPTH-1]; // TODO: replace with block ram
   logic [$clog2(MAX_DEPTH)-1:0] dac_buffer_wr_ptr;
   logic [$clog2(MAX_DEPTH)-1:0] dac_buffer_rd_ptr;

   // read out queue - side band data to track contents of buffer
   TMODE dac_trans_idx_queue [0:MAX_DEPTH-1];   // probably fine to be logic, but should be block ram
   logic [15:0] dac_trans_size [0:MAX_DEPTH-1]; 
   logic [15:0] current_wr_trans_size;
   logic [$clog2(MAX_DEPTH)-1:0] dac_tqueue_wr_ptr;
   logic [15:0] current_rd_trans_size;
   logic [$clog2(MAX_DEPTH)-1:0] dac_tqueue_rd_ptr;
   
   assign S_source_burst_active = (axis_S_source_tready & axis_S_source_tvalid);
   assign S_source_burst_end =   (S_source_burst_active & axis_S_source_tlast);

   // AXIS data handler ///////////////////////////////////////////////////////
   assign axis_S_source_tready = ~rst && (dac_buffer_wr_ptr != (dac_buffer_rd_ptr - 1'b1)); // receive data if buffer is not full

   // FIFO CONTROL ////////////////////////////////////////////////////////////
   // FIFO IN
   always @(posedge clk)
   begin
      if (rst) begin
         dac_buffer_wr_ptr <= '0;
         dac_tqueue_wr_ptr <= '0;
         current_wr_trans_size <= '0;
      end
      else
         if (S_source_burst_active) begin
            dac_data_buffer[dac_buffer_wr_ptr] <= axis_S_source_tdata;
            dac_buffer_wr_ptr = dac_buffer_wr_ptr + 1'b1;

            if (S_source_burst_end) begin
               if (trans_mode == ROUNDROBIN)
                  case (roundrobin_sel)
                     3'b001: dac_trans_idx_queue [dac_tqueue_wr_ptr] <= DAC1;
                     3'b010: dac_trans_idx_queue [dac_tqueue_wr_ptr] <= DAC2;
                     3'b100: dac_trans_idx_queue [dac_tqueue_wr_ptr] <= DAC3;
                  endcase
               else   
                  dac_trans_idx_queue [dac_tqueue_wr_ptr] <= trans_mode;

               dac_trans_size [dac_tqueue_wr_ptr] <= current_wr_trans_size;
               dac_tqueue_wr_ptr <= dac_tqueue_wr_ptr + 1'b1; 
               current_wr_trans_size <= '0;
            end
            else
               current_wr_trans_size <= current_wr_trans_size + 1'b1;
         end
   end

   // FIFO OUT
   always @(posedge clk)
   begin
      if (rst) begin
         dac_buffer_rd_ptr <= '0;
         dac_tqueue_rd_ptr <= '0;
         current_rd_trans_size <= '0;
      end
      else begin 
         if (dac_tqueue_rd_ptr != dac_tqueue_wr_ptr) begin // if packet transaction to DACs is queued up
            case (dac_trans_idx_queue [dac_tqueue_rd_ptr])
               DAC1: begin
                  axis_M_dac1_tdata  <= dac_data_buffer[dac_buffer_rd_ptr];
                  axis_M_dac1_tvalid <= 1'b1;
                  axis_M_dac2_tdata  <= '0;
                  axis_M_dac2_tvalid <= 1'b0;
                  axis_M_dac3_tdata  <= '0;
                  axis_M_dac3_tvalid <= 1'b0;
               end
               DAC2: begin
                  axis_M_dac1_tdata  <= '0;
                  axis_M_dac1_tvalid <= 1'b0;
                  axis_M_dac2_tdata  <= dac_data_buffer[dac_buffer_rd_ptr];
                  axis_M_dac2_tvalid <= 1'b1;
                  axis_M_dac3_tdata  <= '0;
                  axis_M_dac3_tvalid <= 1'b0;
               end
               DAC3: begin
                  axis_M_dac1_tdata  <= '0;
                  axis_M_dac1_tvalid <= 1'b0;
                  axis_M_dac2_tdata  <= '0;
                  axis_M_dac2_tvalid <= 1'b0;
                  axis_M_dac3_tdata  <= dac_data_buffer[dac_buffer_rd_ptr];
                  axis_M_dac3_tvalid <= 1'b1;
               end
            endcase
            // in all cases
            dac_buffer_rd_ptr <= dac_buffer_rd_ptr + 1'b1; // increment buffer pointer

            
            if (current_rd_trans_size < dac_trans_size[dac_tqueue_rd_ptr]) // increment "packets sent out register"
               current_rd_trans_size <= current_rd_trans_size + 1'b1;
            else begin // packet transaction has been completed
               dac_tqueue_rd_ptr <= dac_tqueue_rd_ptr + 1'b1; // next packet transaction
               current_rd_trans_size <= '0;
            end
         end
         else begin 
            axis_M_dac1_tdata  <= '0;
            axis_M_dac1_tvalid <= 1'b0;
            axis_M_dac2_tdata  <= '0;
            axis_M_dac2_tvalid <= 1'b0;
            axis_M_dac3_tdata  <= '0;
            axis_M_dac3_tvalid <= 1'b0;
         end
      end
   end

   ////////////////////////////////////////////////////////////////////////////    


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
               next_state = RECEIVING;
         RECEIVING:
            if (S_source_burst_end)       // transaction ending
               next_state = LAST_TRANS;
         LAST_TRANS:
            if (S_source_burst_active) 
               next_state = RECEIVING; // queue up another transaction
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



endmodule: beam_mux
  