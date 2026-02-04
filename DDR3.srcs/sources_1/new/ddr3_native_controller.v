`timescale 1ns / 1ps

module ddr3_native_controller #(
    parameter ADDR_WIDTH = 28,
    parameter DATA_WIDTH = 128,
    parameter MASK_WIDTH = 16
)(
    // Clock and Reset
    input  wire                     ui_clk,
    input  wire                     ui_clk_sync_rst,
    input  wire                     init_calib_complete,
    
    // VIO Control
    input  wire                     start,
    input  wire [ADDR_WIDTH-1:0]    vio_write_addr,
    input  wire [DATA_WIDTH-1:0]    vio_write_data,
    input  wire [ADDR_WIDTH-1:0]    vio_read_addr,
    
    // Status Outputs
    output reg                      test_done,
    output reg                      data_match,
    output reg  [DATA_WIDTH-1:0]    read_data_captured,
    output reg  [31:0]              error_count,
    output reg  [3:0]               current_state,
    
    // MIG Native Interface
    output reg  [ADDR_WIDTH-1:0]    app_addr,
    output reg  [2:0]               app_cmd,
    output reg                      app_en,
    input  wire                     app_rdy,
    
    output reg  [DATA_WIDTH-1:0]    app_wdf_data,
    output reg                      app_wdf_wren,
    output reg                      app_wdf_end,
    output reg  [MASK_WIDTH-1:0]    app_wdf_mask,
    input  wire                     app_wdf_rdy,
    
    input  wire [DATA_WIDTH-1:0]    app_rd_data,
    input  wire                     app_rd_data_valid,
    input  wire                     app_rd_data_end,
    
    output wire                     app_sr_req,
    input  wire                     app_sr_active,
    output wire                     app_ref_req,
    input  wire                     app_ref_ack,
    output wire                     app_zq_req,
    input  wire                     app_zq_ack
);

// Tie off unused signals
assign app_sr_req = 1'b0;
assign app_ref_req = 1'b0;
assign app_zq_req = 1'b0;

// State Machine
localparam [3:0] IDLE          = 4'd0,
                 WAIT_CALIB    = 4'd1,
                 WRITE_CMD     = 4'd2,
                 WRITE_DATA    = 4'd3,
                 WRITE_WAIT    = 4'd4,
                 READ_CMD      = 4'd5,
                 READ_WAIT     = 4'd6,
                 COMPARE       = 4'd7,
                 DONE          = 4'd8;

// Internal Registers
reg [DATA_WIDTH-1:0] write_data_reg;
reg [ADDR_WIDTH-1:0] write_addr_reg;
reg [ADDR_WIDTH-1:0] read_addr_reg;
reg                  write_cmd_accepted;
reg                  write_data_accepted;
reg                  read_cmd_accepted;
reg [7:0]            wait_counter;

// Synchronize start signal
reg start_d1, start_d2;
wire start_pulse = start_d1 && !start_d2;

always @(posedge ui_clk) begin
    if (ui_clk_sync_rst) begin
        start_d1 <= 1'b0;
        start_d2 <= 1'b0;
    end else begin
        start_d1 <= start;
        start_d2 <= start_d1;
    end
end

// Main State Machine
always @(posedge ui_clk) begin
    if (ui_clk_sync_rst) begin
        current_state <= IDLE;
        test_done <= 1'b0;
        data_match <= 1'b0;
        read_data_captured <= {DATA_WIDTH{1'b0}};
        error_count <= 32'd0;
        
        app_addr <= {ADDR_WIDTH{1'b0}};
        app_cmd <= 3'b000;
        app_en <= 1'b0;
        
        app_wdf_data <= {DATA_WIDTH{1'b0}};
        app_wdf_wren <= 1'b0;
        app_wdf_end <= 1'b0;
        app_wdf_mask <= {MASK_WIDTH{1'b0}};
        
        write_data_reg <= {DATA_WIDTH{1'b0}};
        write_addr_reg <= {ADDR_WIDTH{1'b0}};
        read_addr_reg <= {ADDR_WIDTH{1'b0}};
        
        write_cmd_accepted <= 1'b0;
        write_data_accepted <= 1'b0;
        read_cmd_accepted <= 1'b0;
        wait_counter <= 8'd0;
        
    end else begin
        // Default: de-assert control signals
        app_en <= 1'b0;
        app_wdf_wren <= 1'b0;
        app_wdf_end <= 1'b0;
        
        case (current_state)
            //------------------------------------------------------------------
            IDLE: begin
                test_done <= 1'b0;
                data_match <= 1'b0;
                error_count <= 32'd0;
                write_cmd_accepted <= 1'b0;
                write_data_accepted <= 1'b0;
                read_cmd_accepted <= 1'b0;
                wait_counter <= 8'd0;
                
                if (start_pulse) begin
                    // Capture VIO inputs
                    write_data_reg <= vio_write_data;
                    write_addr_reg <= vio_write_addr;
                    read_addr_reg <= vio_read_addr;
                    current_state <= WAIT_CALIB;
                end
            end
            
            //------------------------------------------------------------------
            WAIT_CALIB: begin
                if (init_calib_complete) begin
                    current_state <= WRITE_CMD;
                end
            end
            
            //------------------------------------------------------------------
            WRITE_CMD: begin
                if (!write_cmd_accepted) begin
                    // Issue write command
                    app_addr <= write_addr_reg;
                    app_cmd <= 3'b000;  // Write command
                    app_en <= 1'b1;
                    
                    if (app_rdy) begin
                        write_cmd_accepted <= 1'b1;
                    end
                end else begin
                    // Command accepted, move to data phase
                    current_state <= WRITE_DATA;
                end
            end
            
            //------------------------------------------------------------------
            WRITE_DATA: begin
                if (!write_data_accepted) begin
                    // Provide write data
                    app_wdf_data <= write_data_reg;
                    app_wdf_wren <= 1'b1;
                    app_wdf_end <= 1'b1;
                    app_wdf_mask <= {MASK_WIDTH{1'b0}};  // No masking
                    
                    if (app_wdf_rdy) begin
                        write_data_accepted <= 1'b1;
                    end
                end else begin
                    // Data accepted, wait before read
                    current_state <= WRITE_WAIT;
                    wait_counter <= 8'd0;
                end
            end
            
            //------------------------------------------------------------------
            WRITE_WAIT: begin
                // Wait some cycles for write to complete
                wait_counter <= wait_counter + 1;
                if (wait_counter >= 8'd20) begin
                    current_state <= READ_CMD;
                end
            end
            
            //------------------------------------------------------------------
            READ_CMD: begin
                if (!read_cmd_accepted) begin
                    // Issue read command
                    app_addr <= read_addr_reg;
                    app_cmd <= 3'b001;  // Read command
                    app_en <= 1'b1;
                    
                    if (app_rdy) begin
                        read_cmd_accepted <= 1'b1;
                    end
                end else begin
                    // Command accepted, wait for data
                    current_state <= READ_WAIT;
                end
            end
            
            //------------------------------------------------------------------
            READ_WAIT: begin
                if (app_rd_data_valid) begin
                    // Capture read data
                    read_data_captured <= app_rd_data;
                    current_state <= COMPARE;
                end
            end
            
            //------------------------------------------------------------------
            COMPARE: begin
                // Compare read data with written data
                if (read_addr_reg == write_addr_reg) begin
                    // Same address - should match
                    if (read_data_captured == write_data_reg) begin
                        data_match <= 1'b1;
                    end else begin
                        data_match <= 1'b0;
                        error_count <= error_count + 1;
                    end
                end else begin
                    // Different addresses - just mark as done
                    data_match <= 1'b0;
                end
                current_state <= DONE;
            end
            
            //------------------------------------------------------------------
            DONE: begin
                test_done <= 1'b1;
                // Stay in DONE until reset or new start
                if (start_pulse) begin
                    current_state <= IDLE;
                end
            end
            
            //------------------------------------------------------------------
            default: begin
                current_state <= IDLE;
            end
        endcase
    end
end

endmodule