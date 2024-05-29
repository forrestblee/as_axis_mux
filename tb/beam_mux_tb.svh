`ifndef BEAM_MUX_TB_SVH
`define BEAM_MUX_TB_SVH

   
   localparam CLK_PERIOD_NS = 3.3333;
   logic clk = 1'b0, rst = 1'b0;
   logic [1:0] dac_sel = 2'b0;

   logic [31:0]   axis_M_mod_tdata  ;
   logic          axis_M_mod_tvalid ;   
   logic          axis_M_mod_tready ;   
   logic          axis_M_mod_tlast  ;   
   logic [31:0]   axis_S_dac1_tdata ;
   logic          axis_S_dac1_tvalid;   
   logic [31:0]   axis_S_dac2_tdata ;
   logic          axis_S_dac2_tvalid;   
   logic [31:0]   axis_S_dac3_tdata ;
   logic          axis_S_dac3_tvalid;   

   int test_fail_count = 0;

class c_input_data;
   randc logic [31:0] modulator_data;
endclass

class c_input_dac_sel;
   rand  logic [1:0] dac_sel;
endclass

task generate_patterns;
   input int n_samples;

   c_input_data datum;
   int random_delay;
   datum = new();
   for (int i = 0; i < n_samples; i++)
   begin
      datum.randomize();
      @(posedge clk)
      axis_M_mod_tdata <= datum.modulator_data;
      // axis_M_mod_tdata <= (dac_sel << 8) | i; // for debugging
      
      std::randomize(random_delay) with { random_delay < 3; random_delay >= 0; };
      if (random_delay > 0) begin
         axis_M_mod_tvalid <= 1'b0; 
         repeat (random_delay) begin
            @(posedge clk)
               axis_M_mod_tvalid <= 1'b0; 
         end
         @(posedge clk)
            axis_M_mod_tvalid <= 1'b1;
      end
      else begin
         axis_M_mod_tvalid <= 1'b1;
      end
      if (i == n_samples-1)
         axis_M_mod_tlast <= 1'b1;
      else 
         axis_M_mod_tlast <= 1'b0;
      wait(axis_M_mod_tready);
      
   end
endtask

task generate_idle;
   @(posedge clk)
   axis_M_mod_tdata <= '0;
   axis_M_mod_tvalid <= 1'b0;
   axis_M_mod_tlast <= 1'b0;
endtask

task randomize_dacsel;
   c_input_dac_sel ctrl;
   ctrl = new();
   ctrl.randomize();
   @(posedge clk)
      dac_sel <= ctrl.dac_sel;
endtask

function int check_data_word;
   input logic [31:0] expected;
   input logic [31:0] received;
   input int idx;
   if (expected == received) begin
      $display("[%t] ----PASSED---- Monitor on channel %d, expected value 0x%8h matched", $realtime, idx, expected);
      return 0;
   end
   else begin
      $display("[%t] ----FAILED---- Monitor on channel %d, expected value 0x%8h, received value 0x%8h", $realtime, idx, expected, received);
      test_fail_count = test_fail_count + 1;
      return -1;
   end

endfunction

task basic_randomized_test;
   input int n_transactions;
   int random_delay;
   int num_pulses;
   repeat(n_transactions) begin
      // assert (std::randomize(num_pulses) with {num_pulses <= 65536; num_pulses >= 1024; ;}); // this took too much of a load on my computer - unless I was meant to assume "samples" meant bytes and not datawords ()
      assert (std::randomize(num_pulses) with {num_pulses <= 2048; num_pulses >= 32;});
      // assert (std::randomize(num_pulses) with {num_pulses <= 10; num_pulses >= 4;});
      generate_patterns(num_pulses);
      
      assert (std::randomize(random_delay) with { random_delay < 15; random_delay >= 0; });
      if (random_delay > 0)
         generate_idle();
      #(random_delay * CLK_PERIOD_NS * 1ns);
   end
   generate_idle();
endtask

`endif