`timescale 1ps/1ps


module beam_mux_tb;

   `include "beam_mux_tb.svh"

   beam_mux #(.DWIDTH(32)) DUT 
   (
      .clk                    (clk),
      .rst                    (rst),
      .dac_sel                (dac_sel),
      .axis_S_source_tdata    (axis_M_mod_tdata  ),
      .axis_S_source_tvalid   (axis_M_mod_tvalid ),
      .axis_S_source_tready   (axis_M_mod_tready ),
      .axis_S_source_tlast    (axis_M_mod_tlast  ),
      .axis_M_dac1_tdata      (axis_S_dac1_tdata ),
      .axis_M_dac1_tvalid     (axis_S_dac1_tvalid),
      .axis_M_dac2_tdata      (axis_S_dac2_tdata ),
      .axis_M_dac2_tvalid     (axis_S_dac2_tvalid),
      .axis_M_dac3_tdata      (axis_S_dac3_tdata ),
      .axis_M_dac3_tvalid     (axis_S_dac3_tvalid)
   );

   // Monitor

   // queues representing DAC inputs
   logic[31:0] dac1_mon_queue[$];
   logic[31:0] dac2_mon_queue[$];
   logic[31:0] dac3_mon_queue[$];
   
   typedef enum {ROUNDROBIN = 0, DAC1 = 1, DAC2 = 2, DAC3 = 3} TMODE;
   typedef enum {RR1, RR2, RR3} RRMODE;

   // storage for output data
   logic [31:0] expected_data1;
   logic [31:0] expected_data2;
   logic [31:0] expected_data3;

   // testbench state variables
   TMODE expected_channel = ROUNDROBIN;
   RRMODE expected_rr_channel = RR1;
   logic mode_can_change = 1'b1;

   // add monitor input to queues
   function void add_to_queue;
      input logic[31:0] datum;
      case (expected_channel)
         ROUNDROBIN: begin
            case(expected_rr_channel)
               RR1:
                  dac1_mon_queue.push_back(datum);
               RR2:
                  dac2_mon_queue.push_back(datum);
               RR3:
                  dac3_mon_queue.push_back(datum);
            endcase
         end
         DAC1:
            dac1_mon_queue.push_back(datum);
         DAC2:
            dac2_mon_queue.push_back(datum);
         DAC3:
            dac3_mon_queue.push_back(datum);

      endcase
   endfunction

   // monitor data collection
   always begin
      @(posedge clk)
      if (axis_M_mod_tvalid & axis_M_mod_tready) begin
         if (axis_M_mod_tlast)
            mode_can_change = 1'b1; 
         else begin
            if (mode_can_change)
               case (dac_sel)
                  2'b00:
                     expected_channel = ROUNDROBIN;
                  2'b01:
                     expected_channel = DAC1;
                  2'b10:
                     expected_channel = DAC2;
                  2'b11:
                     expected_channel = DAC3;
               endcase
            mode_can_change = 1'b0; // transaction start - update dac_sel state
         end

         // after updating expected channels, add transaction to corresponding queue
         add_to_queue(axis_M_mod_tdata);
      end
   end

   // monitor expected channel collector
   always begin
      @(posedge clk)
      if (axis_M_mod_tvalid & axis_M_mod_tready & axis_M_mod_tlast & expected_channel == ROUNDROBIN)
         expected_rr_channel = expected_rr_channel.next;
   end

   // monitor received channel data collection
   always begin
      @(posedge clk) begin
         if (axis_S_dac1_tvalid) begin
            expected_data1 = dac1_mon_queue.pop_front();
            $display("Monitor 1 queue count: %d", dac1_mon_queue.size());
            check_data_word(expected_data1, axis_S_dac1_tdata, 1);
         end
      end
   end
   always begin
      @(posedge clk) begin
         if (axis_S_dac2_tvalid) begin
            expected_data2 = dac2_mon_queue.pop_front();
            $display("Monitor 2 queue count: %d", dac2_mon_queue.size());
            check_data_word(expected_data2, axis_S_dac2_tdata, 2);
         end
      end
   end
   always begin
      @(posedge clk) begin
         if (axis_S_dac3_tvalid) begin
            expected_data3 = dac3_mon_queue.pop_front();
            $display("Monitor 3 queue count: %d", dac3_mon_queue.size());
            check_data_word(expected_data3, axis_S_dac3_tdata, 3);
         end
      end
   end

   // TODO: check that queue size does not exceed 1, since that would indicate backpressure (which is not part of the design)

   // clock generation
   always 
      #(CLK_PERIOD_NS * 0.5ns) clk <= ~clk;

   // main test loop
   initial begin
      rst <= 1'b1;
      generate_idle();
   
      $timeformat(-9, 3, "ns", 8);
      //$timeformat params:
      //1) Scaling factor (–9 for nanoseconds, –12 for picoseconds)
      //2) Number of digits to the right of the decimal point
      //3) A string to print after the time value
      //4) Minimum field width

      #1us;
      @(posedge clk)
      rst <= 1'b0;

      fork
         begin
            int random_delay;
            repeat(1000) begin
               @(posedge clk)
               randomize_dacsel();
               assert(std::randomize(random_delay) with { random_delay < 4096; random_delay >= 10; });
               #(random_delay * CLK_PERIOD_NS * 1ns);
            end
         end
      join_none

      basic_randomized_test(200); 

      #10us;
      if (test_fail_count > 0) begin
         $display("Failure Count: %d", test_fail_count);
         $display("--------------- TEST FAILED ---------------");
      end
      else
         $display("--------------- TEST PASSED ---------------");


      $display("--------------- TEST END ---------------");
      $stop;
   end




endmodule