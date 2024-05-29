# as_axis_mux

![image](https://github.com/forrestblee/as_axis_mux/assets/3317623/29d76971-0b5f-4df3-9ca3-05a6107a9bbb)


# Design
dac_sel selects which of 4 operating modes the MUX will operate in: Round Robin, DAC1 only, DAC2 only, or DAC3 only. The AXI-S implementation at the source implements tready and tlast, and at the DAC output only the bare minimum tdata and tvalid are implemented. 
The mux operation is state machine based, with state machine input as dac_sel. 

**Performance**

As long as the source input and the Beam Mux are operating at the same clock rate, there is no need for any backpressure from the MUX to the source. However, backpressure is implemented regardless.

The new version which buffers the full transactions before sending has a 2 clock cycle delay from the final TLAST pulse. However, there may be data in queue being transmitted that would ultimate delay the transaction further. 
~~The Beam Mux has a clock delay of one clock. As a caveat, this implementation violates the AXI spec "suggestion" for all AXI outputs to be registered. There is a commented out version that registers the outputs, which increases the clock delay to two.~~

**Notes**

UPDATE: transactional model was implemented to accomodate continuous burst at output. 
~~Possible improvements include simplifying state machine logic: the state machine selecting which DAC is output to could be replaced by a transaction based model, deciding which DAC by registering dac_sel alongside the first AXI burst. However, this would have been complicated if the source AXI-stream was capable of sparse transactions - that is, if tvalid did not pulse for the full duration of the burst. I made the assumption that the source was allowed to pause and restart the transaction mid-burst.~~

# Testbench
The testbench is fully hand coded with each 32-bit dword treated as a single transaction, since the DACs do not receive a tlast - it would not be possible to differentiate bursts.

![as_axis_mux drawio](https://github.com/forrestblee/as_axis_mux/assets/3317623/3163ec47-a671-48a3-ab3d-39a76b4fe365)

Bursts are randomly generated using functions represented in the diagram by Modulator Driver. The functions use std::randomize and burst length ranges from 32 dwords to 2048 dwords. dac_sel is also randomized in the fork portion of the testbench. Built-in constrained randomized delays are also interlaced into stimulus generation to ensure corner cases are all hit using this one-size-fits all testcase. 

When bursts are sent to the DUT, the testbench dynamically queues all dwords in the appropriate queue in FIFO order, based on the state of dac_sel and internal status logic tracking round-robin. 

The testbench is self checking. As data words exit the DUT, destined for the DACs (minimally modelled), they are compared with the corresponding data word stored in the queue, which should match. The comparators log the DAC index, value, and any errors observed in the simulation log. An example waveform diagram and simulation log is included. Simulation was done with xsim in Vivado but since there are no IP dependencies it should run on any sim without any additional work.  

![image](https://github.com/forrestblee/as_axis_mux/assets/3317623/a1c07a98-7d50-4be2-921c-20fcb2f15f5f)
![image](https://github.com/forrestblee/as_axis_mux/assets/3317623/75c72996-0fa4-4e7c-8929-0e6bafd99be8)

![image](https://github.com/forrestblee/as_axis_mux/assets/3317623/dc4dff19-f904-45c2-9e29-ca372600677b)
An example with toggling source tvalid, where the design maintains continuous "burstiness" on the DAC output side. 

# Build
The project can be built by opening Vivado and running the tcl script contained in the base folder, from the GUI we can run the simulation. It might only work in the current Vivado version I have installed (2023.1) since Vivado loves doing that.  
