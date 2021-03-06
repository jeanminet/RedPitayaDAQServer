`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 09/26/2017 05:13:25 PM
// Design Name: 
// Module Name: reset_manager
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module reset_manager #
(
    parameter integer WATCHDOG_TIMEOUT = 100, // in milliseconds
    parameter integer ALIVE_SIGNAL_LOW_TIME = 100, // in milliseconds
    parameter integer ALIVE_SIGNAL_HIGH_TIME = 10 // in milliseconds
)
(
    input clk,
    input peripheral_aresetn,
    input [7:0] reset_cfg,
    inout trigger,
    inout watchdog,
    inout instant_reset,
    output write_to_ram_aresetn,
    output xadc_aresetn,
    output fourier_synth_aresetn,
    output pdm_aresetn,
    output [31:0] reset_sts,
    output [7:0] led,
    inout reset_ack,
    inout alive_signal,
    inout master_trigger
);

/*
reset_cfg:
Bit 0 => 0: continuous mode; 1: trigger mode
Bit 1 => 0: no watchdog; 1: watchdog mode
Bit 2 => master trigger

reset_ack: high if reset active (either watchdog failed or instant reset)
*/

localparam integer WATCHDOG_TIMEOUT_CYCLES = 12500000;//(125000000/WATCHDOG_TIMEOUT)*1000;
localparam integer ALIVE_SIGNAL_LOW_TIME_CYCLES = 12500000;//(125000000/ALIVE_SIGNAL_LOW_TIME)*1000;
localparam integer ALIVE_SIGNAL_HIGH_TIME_CYCLES = 1250000;//(125000000/ALIVE_SIGNAL_HIGH_TIME)*1000;

reg write_to_ram_aresetn_int = 0;
reg xadc_aresetn_int = 0;
reg fourier_synth_aresetn_int = 0;
reg pdm_aresetn_int = 0;

wire trigger_in;
wire watchdog_in;
wire instant_reset_in;
wire reset_ack_in;
wire alive_signal_in;
wire master_trigger_in;

wire trigger_out;
wire watchdog_out;
wire instant_reset_out;
wire reset_ack_out;
wire alive_signal_out;
wire master_trigger_out;

// Buffer Tristate inputs
IOBUF #(
.DRIVE(8),
.IOSTANDARD("LVCMOS33"),
.SLEW("FAST")
) IOBUF_trigger (
.I(trigger_out),
.IO(trigger),
.O(trigger_in),
.T(1'b1) // 3-state enable input, high=input, low=output
);

IOBUF #(
.DRIVE(8),
.IOSTANDARD("LVCMOS33"),
.SLEW("FAST")
) IOBUF_watchdog (
.I(watchdog_out),
.IO(watchdog),
.O(watchdog_in),
.T(1'b1) // 3-state enable input, high=input, low=output
);

IOBUF #(
.DRIVE(8),
.IOSTANDARD("LVCMOS33"),
.SLEW("FAST")
) IOBUF_instant_reset (
.I(instant_reset_out),
.IO(instant_reset),
.O(instant_reset_in),
.T(1'b1) // 3-state enable input, high=input, low=output
);

// Buffer Tristate outputs
IOBUF #(
.DRIVE(8),
.IOSTANDARD("LVCMOS33"),
.SLEW("FAST")
) IOBUF_reset_ack (
.I(reset_ack_out),
.IO(reset_ack),
.O(reset_ack_in),
.T(1'b0) // 3-state enable input, high=input, low=output
);

IOBUF #(
.DRIVE(8),
.IOSTANDARD("LVCMOS33"),
.SLEW("FAST")
) IOBUF_alive_signal (
.I(alive_signal_out),
.IO(alive_signal),
.O(alive_signal_in),
.T(1'b0) // 3-state enable input, high=input, low=output
);

IOBUF #(
.DRIVE(8),
.IOSTANDARD("LVCMOS33"),
.SLEW("FAST")
) IOBUF_master_trigger (
.I(master_trigger_out),
.IO(master_trigger),
.O(master_trigger_in),
.T(1'b0) // 3-state enable input, high=input, low=output
);

// Create alive signal
reg alive_signal_int = 0;
reg [27:0] alive_signal_counter = 0;
always @(posedge clk)
begin
    if (alive_signal_counter < (ALIVE_SIGNAL_LOW_TIME_CYCLES + ALIVE_SIGNAL_HIGH_TIME_CYCLES))
    begin
        alive_signal_counter <= alive_signal_counter + 1;
    end
    else
    begin
        alive_signal_counter <= 0;
    end
    
    if (alive_signal_counter < ALIVE_SIGNAL_LOW_TIME_CYCLES)
    begin
        alive_signal_int <= 0;
    end
    else
    begin
        alive_signal_int <= 1;
    end
end

// Watchdog counter for timeouts
reg [25:0] watchdog_counter = 0;
reg last_status = 0;
always @(posedge clk)
begin
    if (watchdog_in & last_status == 0)
    begin
        watchdog_counter <= 0;
        last_status <= 1;
    end
    else if (~watchdog_in & last_status == 1)
    begin
        watchdog_counter <= 0;
        last_status <= 0;
    end
    else        
    begin
        if (watchdog_counter < 16777213) // Prevent wrapping
        begin
            watchdog_counter <= watchdog_counter + 1;
        end
        else
        begin
            watchdog_counter <= 16777214;
        end
    end
end

always @(posedge clk)
begin
    if (~peripheral_aresetn)
    begin
        write_to_ram_aresetn_int <= peripheral_aresetn;
        xadc_aresetn_int <= peripheral_aresetn;
        fourier_synth_aresetn_int <= peripheral_aresetn;
        pdm_aresetn_int <= peripheral_aresetn;
    end
    else
    begin
        // Write to RAM
        if (reset_cfg[0] == 0) // continuous mode
        begin
            write_to_ram_aresetn_int <= peripheral_aresetn;
        end
        else // trigger mode
        begin
            write_to_ram_aresetn_int <= trigger_in;
        end
        
        // Watchdog for DACs
        if (instant_reset_in)
        begin
            fourier_synth_aresetn_int <= 1'b0;
            pdm_aresetn_int <= 1'b0;
        end
        else
        begin
            if (reset_cfg[1] == 0) // no watchdog
            begin
                if (reset_cfg[0] == 0) // continuous mode
                begin
                    fourier_synth_aresetn_int <= peripheral_aresetn;
                    pdm_aresetn_int <= peripheral_aresetn;
                end
                else // trigger mode
                begin
                    fourier_synth_aresetn_int <= trigger_in;
                    pdm_aresetn_int <= trigger_in;
                end
                
            end
            else // watchdog mode
            begin
                if (watchdog_counter < WATCHDOG_TIMEOUT_CYCLES) // watchdog still working
                begin
                    if (reset_cfg[0] == 0) // continuous mode
                    begin
                        fourier_synth_aresetn_int <= peripheral_aresetn;
                        pdm_aresetn_int <= peripheral_aresetn;
                    end
                    else // trigger mode
                    begin
                        fourier_synth_aresetn_int <= trigger_in;
                        pdm_aresetn_int <= trigger_in;
                    end
                end
                else // watchdog failed to signal within the given timeframe
                begin
                    fourier_synth_aresetn_int <= 1'b0;
                    pdm_aresetn_int <= 1'b0;
                end
            end
        end
        
        // XADC is always running
        xadc_aresetn_int <= peripheral_aresetn;
    end
end

assign write_to_ram_aresetn = write_to_ram_aresetn_int;
assign xadc_aresetn = xadc_aresetn_int;
assign fourier_synth_aresetn = fourier_synth_aresetn_int;
assign pdm_aresetn = pdm_aresetn_int;

assign reset_sts[0] = peripheral_aresetn;
assign reset_sts[1] = fourier_synth_aresetn_int;
assign reset_sts[2] = pdm_aresetn_int;
assign reset_sts[3] = write_to_ram_aresetn_int;
assign reset_sts[4] = xadc_aresetn_int;

// Temporary fix for LOC errors
assign reset_sts[5] = 0;//trigger_in;
assign reset_sts[6] = 0;//watchdog_in;
assign reset_sts[7] = 0;//instant_reset_in;
assign reset_sts[8] = reset_cfg[2];
assign reset_sts[31:9] = 23'b0;

assign led[7:0] =  reset_sts[7:0];

assign reset_ack_out = watchdog_in; // Acknowledge received watchdog signal

assign alive_signal_out = alive_signal_int;
assign master_trigger_out = reset_cfg[2];


endmodule

