`timescale 1ns / 1ps


module ddr3_native_top (

    input  wire        sys_clk_i,           // 200 MHz board clock
               // Optional external reset
    
    // DDR3 Physical Interface (to external DRAM chip)

    output wire        ddr3_reset_n,
    output wire [13:0] ddr3_addr,
    output wire [2:0]  ddr3_ba,
    output wire        ddr3_cas_n,
    output wire        ddr3_ras_n,
    output wire        ddr3_we_n,
    output wire        ddr3_ck_p,
    output wire        ddr3_ck_n,
    output wire        ddr3_cke,
    output wire        ddr3_odt,
    output wire [1:0]  ddr3_dm,
    inout  wire [15:0] ddr3_dq,
    inout  wire [1:0]  ddr3_dqs_p,
    inout  wire [1:0]  ddr3_dqs_n
);


localparam ADDR_WIDTH = 28;
localparam DATA_WIDTH = 128;
localparam MASK_WIDTH = 16;



wire        ui_clk;                   // 100 MHz UI clock
wire        ui_clk_sync_rst;          // Synchronized reset
wire        init_calib_complete;      // Calibration done

// Native User Interface Signals

// Command Path
wire [ADDR_WIDTH-1:0]   app_addr;
wire [2:0]              app_cmd;
wire                    app_en;
wire                    app_rdy;

// Write Data Path
wire [DATA_WIDTH-1:0]   app_wdf_data;
wire                    app_wdf_wren;
wire                    app_wdf_end;
wire [MASK_WIDTH-1:0]   app_wdf_mask;
wire                    app_wdf_rdy;

// Read Data Path
wire [DATA_WIDTH-1:0]   app_rd_data;
wire                    app_rd_data_valid;
wire                    app_rd_data_end;

// Optional signals
wire                    app_sr_req;
wire                    app_sr_active;
wire                    app_ref_req;
wire                    app_ref_ack;
wire                    app_zq_req;
wire                    app_zq_ack;

// VIO Control Signals (VIO ? Controller)

wire                    vio_start;
wire [ADDR_WIDTH-1:0]   vio_write_addr;
wire [DATA_WIDTH-1:0]   vio_write_data;
wire [ADDR_WIDTH-1:0]   vio_read_addr;
wire                    vio_sys_rst;


// Controller Status Signals (Controller ? VIO)

wire                    test_done;
wire                    data_match;
wire [DATA_WIDTH-1:0]   read_data_captured;
wire [31:0]             error_count;
wire [3:0]              current_state;

wire sys_clk_buf;

IBUF u_sysclk_ibuf (
  .I(sys_clk_i),
  .O(sys_clk_ibuf)
);

BUFG u_sysclk_bufg (
  .I(sys_clk_ibuf),
  .O(sys_clk_buf)
);


mig_7series_0 u_mig (
    // System Clock and Reset
    .sys_clk_i              (sys_clk_buf),
    .sys_rst                (vio_sys_rst),
    
    // User Interface Outputs
    .ui_clk                 (ui_clk),
    .ui_clk_sync_rst        (ui_clk_sync_rst),
    .init_calib_complete    (init_calib_complete),
    
    // Native User Interface - Command Path
    .app_addr               (app_addr),
    .app_cmd                (app_cmd),
    .app_en                 (app_en),
    .app_rdy                (app_rdy),
    
    // Native User Interface - Write Data Path
    .app_wdf_data           (app_wdf_data),
    .app_wdf_wren           (app_wdf_wren),
    .app_wdf_end            (app_wdf_end),
    .app_wdf_mask           (app_wdf_mask),
    .app_wdf_rdy            (app_wdf_rdy),
    
    // Native User Interface - Read Data Path
    .app_rd_data            (app_rd_data),
    .app_rd_data_valid      (app_rd_data_valid),
    .app_rd_data_end        (app_rd_data_end),
    
    // Native User Interface - Optional Signals
    .app_sr_req             (app_sr_req),
    .app_sr_active          (app_sr_active),
    .app_ref_req            (app_ref_req),
    .app_ref_ack            (app_ref_ack),
    .app_zq_req             (app_zq_req),
    .app_zq_ack             (app_zq_ack),
    
    // DDR3 Physical Interface
    .ddr3_dq                (ddr3_dq),
    .ddr3_dqs_n             (ddr3_dqs_n),
    .ddr3_dqs_p             (ddr3_dqs_p),
    .ddr3_addr              (ddr3_addr),
    .ddr3_ba                (ddr3_ba),
    .ddr3_ras_n             (ddr3_ras_n),
    .ddr3_cas_n             (ddr3_cas_n),
    .ddr3_we_n              (ddr3_we_n),
    .ddr3_reset_n           (ddr3_reset_n),
    .ddr3_ck_p              (ddr3_ck_p),
    .ddr3_ck_n              (ddr3_ck_n),
    .ddr3_cke               (ddr3_cke),
    .ddr3_dm                (ddr3_dm),
    .ddr3_odt               (ddr3_odt)
);

//==============================================================================
// Native Controller Instance
//==============================================================================
ddr3_native_controller #(
    .ADDR_WIDTH             (ADDR_WIDTH),
    .DATA_WIDTH             (DATA_WIDTH),
    .MASK_WIDTH             (MASK_WIDTH)
) u_native_controller (
    // Clock and Reset
    .ui_clk                 (ui_clk),
    .ui_clk_sync_rst        (ui_clk_sync_rst),
    .init_calib_complete    (init_calib_complete),
    
    // VIO Control
    .start                  (vio_start),
    .vio_write_addr         (vio_write_addr),
    .vio_write_data         (vio_write_data),
    .vio_read_addr          (vio_read_addr),
    
    // VIO Status
    .test_done              (test_done),
    .data_match             (data_match),
    .read_data_captured     (read_data_captured),
    .error_count            (error_count),
    .current_state          (current_state),
    
    // MIG Native Interface - Command Path
    .app_addr               (app_addr),
    .app_cmd                (app_cmd),
    .app_en                 (app_en),
    .app_rdy                (app_rdy),
    
    // MIG Native Interface - Write Data Path
    .app_wdf_data           (app_wdf_data),
    .app_wdf_wren           (app_wdf_wren),
    .app_wdf_end            (app_wdf_end),
    .app_wdf_mask           (app_wdf_mask),
    .app_wdf_rdy            (app_wdf_rdy),
    
    // MIG Native Interface - Read Data Path
    .app_rd_data            (app_rd_data),
    .app_rd_data_valid      (app_rd_data_valid),
    .app_rd_data_end        (app_rd_data_end),
    
    // MIG Native Interface - Optional Signals
    .app_sr_req             (app_sr_req),
    .app_sr_active          (app_sr_active),
    .app_ref_req            (app_ref_req),
    .app_ref_ack            (app_ref_ack),
    .app_zq_req             (app_zq_req),
    .app_zq_ack             (app_zq_ack)
);



vio_0 u_vio (
    .clk                    (sys_clk_buf),
    

    .probe_out0             (vio_start),            // [0:0]    Start test
    .probe_out1             (vio_write_data),       // [63:0]   Data to write
    .probe_out2             (vio_write_addr),       // [27:0]   Write address
    .probe_out3             (vio_read_addr),        // [27:0]   Read address
    .probe_out4              (vio_sys_rst),

    .probe_in0              (init_calib_complete),  // [0:0]    MIG calibrated
    .probe_in1              (test_done),            // [0:0]    Test complete
    .probe_in2              (data_match),           // [0:0]    Data matches
    .probe_in3              (read_data_captured),   // [63:0]   Read data
    .probe_in4              (error_count)           // [31:0]   Error counter
);

endmodule