module image_read
#(
  parameter WIDTH 	= 768, 					
			HEIGHT 	= 512, 					
			INFILE  = "C:\\Users\\steve\\Verilog Projects\\ImageProcessing\\ImageProcessing.srcs\\sim_1\\new\\kodim23.hex", 	
			START_UP_DELAY = 100, 			
			HSYNC_DELAY = 160,								
			SIGN=1,									
			SCALE_FACTOR = 2
													
)
(
	input HCLK,												
	input HRESETn,									
	output VSYNC,								
	output reg HSYNC,							
    output reg [7:0]  DATA_R0,				
    output reg [7:0]  DATA_G0,			
    output reg [7:0]  DATA_B0,			
    output reg [7:0]  DATA_R1,			
    output reg [7:0]  DATA_G1,			
    output reg [7:0]  DATA_B1,				
	output			  ctrl_done					
);			
parameter sizeOfWidth = 8;						
parameter sizeOfLengthReal = 1179648; 		

localparam		ST_IDLE 	= 2'b00,		
				ST_VSYNC	= 2'b01,			
				ST_HSYNC	= 2'b10,			
				ST_DATA		= 2'b11;		
reg [1:0] cstate, 						
		  nstate;									
reg start;									
reg HRESETn_d;								
reg 		ctrl_vsync_run; 				 
reg [8:0]	ctrl_vsync_cnt;			
reg 		ctrl_hsync_run;				
reg [8:0]	ctrl_hsync_cnt;			
reg 		ctrl_data_run;					
reg [31 : 0]  in_memory    [0 : sizeOfLengthReal/4]; 	
reg [7 : 0]   total_memory [0 : sizeOfLengthReal-1];	
integer temp_BMP   [0 : WIDTH*HEIGHT*3 - 1];			
integer org_R  [0 : WIDTH*HEIGHT - 1]; 
integer org_G  [0 : WIDTH*HEIGHT - 1];	
integer org_B  [0 : WIDTH*HEIGHT - 1];	
reg [7:0] blur_R[WIDTH*HEIGHT-1:0]; 
reg [7:0] blur_G[WIDTH*HEIGHT-1:0]; 
reg[7:0] blur_B[WIDTH*HEIGHT-1:0]; 

integer i, j, m, n;
integer sum_R, sum_G, sum_B;
reg [ 9:0] row; 
reg [10:0] col; 
reg [18:0] data_count; 

initial begin
    $readmemh(INFILE,total_memory,0,sizeOfLengthReal-1);
end

always@(start) begin
    if(start == 1'b1) begin
        for(i=0; i<WIDTH*HEIGHT*3 ; i=i+1) begin
            temp_BMP[i] = total_memory[i+0][7:0]; 
        end
        
        for(i=0; i<HEIGHT; i=i+1) begin
            for(j=0; j<WIDTH; j=j+1) begin
                org_R[WIDTH*i+j] = temp_BMP[WIDTH*3*(HEIGHT-i-1)+3*j+0]; // save Red component
                org_G[WIDTH*i+j] = temp_BMP[WIDTH*3*(HEIGHT-i-1)+3*j+1];// save Green component
                org_B[WIDTH*i+j] = temp_BMP[WIDTH*3*(HEIGHT-i-1)+3*j+2];// save Blue component
            end
        end
    end
end

always@(posedge HCLK, negedge HRESETn)
begin
    if(!HRESETn) begin
        start <= 0;
		HRESETn_d <= 0;
    end
    else begin														
        HRESETn_d <= HRESETn;							
		if(HRESETn == 1'b1 && HRESETn_d == 1'b0)		
			start <= 1'b1;
		else
			start <= 1'b0;
    end
end

always@(posedge HCLK, negedge HRESETn)
begin
    if(~HRESETn) begin
        cstate <= ST_IDLE;
    end
    else begin
        cstate <= nstate; 
    end
end

// IDLE . VSYNC . HSYNC . DATA
always @(*) begin
	case(cstate)
		ST_IDLE: begin
			if(start)
				nstate = ST_VSYNC;
			else
				nstate = ST_IDLE;
		end			
		ST_VSYNC: begin
			if(ctrl_vsync_cnt == START_UP_DELAY) 
				nstate = ST_HSYNC;
			else
				nstate = ST_VSYNC;
		end
		ST_HSYNC: begin
			if(ctrl_hsync_cnt == HSYNC_DELAY) 
				nstate = ST_DATA;
			else
				nstate = ST_HSYNC;
		end		
		ST_DATA: begin
			if(ctrl_done)
				nstate = ST_IDLE;
			else begin
				if(col == WIDTH - 2)
					nstate = ST_HSYNC;
				else
					nstate = ST_DATA;
			end
		end
	endcase
end

always @(*) begin
	ctrl_vsync_run = 0;
	ctrl_hsync_run = 0;
	ctrl_data_run  = 0;
	case(cstate)
		ST_VSYNC: 	begin ctrl_vsync_run = 1; end 	
		ST_HSYNC: 	begin ctrl_hsync_run = 1; end	
		ST_DATA: 	begin ctrl_data_run  = 1; end	
	endcase
end
// counters for vsync, hsync
always@(posedge HCLK, negedge HRESETn)
begin
    if(~HRESETn) begin
        ctrl_vsync_cnt <= 0;
		ctrl_hsync_cnt <= 0;
    end
    else begin
        if(ctrl_vsync_run)
			ctrl_vsync_cnt <= ctrl_vsync_cnt + 1; 
		else 
			ctrl_vsync_cnt <= 0;
			
        if(ctrl_hsync_run)
			ctrl_hsync_cnt <= ctrl_hsync_cnt + 1;		
		else
			ctrl_hsync_cnt <= 0;
    end
end

always@(posedge HCLK, negedge HRESETn)
begin
    if(~HRESETn) begin
        row <= 0;
		col <= 0;
    end
	else begin
		if(ctrl_data_run) begin
			if(col == WIDTH - 2) begin
				row <= row + 1;
			end
			if(col == WIDTH - 2) 
				col <= 0;
			else 
				col <= col + 2; 
		end
	end
end

always@(posedge HCLK, negedge HRESETn)
begin
    if(~HRESETn) begin
        data_count <= 0;
    end
    else begin
        if(ctrl_data_run)
			data_count <= data_count + 1;
    end
end
assign VSYNC = ctrl_vsync_run;
assign ctrl_done = (data_count == 196607)? 1'b1: 1'b0; 
//-------------------------------------------------//
//-------------  Image processing   ---------------//
//-------------------------------------------------//
		// Define brightness adjustment LUT size and parameters
parameter signed [7:0] BRIGHTNESS_VALUE = 50; // You can adjust this value to increase or decrease brightness
integer tempR0,tempR1,tempG0,tempG1,tempB0,tempB1; 
always @(*) begin
	
	HSYNC   = 1'b0;
	DATA_R0 = 0;
	DATA_G0 = 0;
	DATA_B0 = 0;                                       
	DATA_R1 = 0;
	DATA_G1 = 0;
	DATA_B1 = 0;                                      
	if(ctrl_data_run) begin
		
		HSYNC   = 1'b1;

//    // Brightness addition
//    if (SIGN == 1) begin
//        // Add brightness value to each pixel component
//        tempR0 = org_R[WIDTH * row + col] + BRIGHTNESS_VALUE;
//        tempG0 = org_G[WIDTH * row + col] + BRIGHTNESS_VALUE;
//        tempB0 = org_B[WIDTH * row + col] + BRIGHTNESS_VALUE;
//        // Ensure pixel components are within valid range (0 to 255)
//        DATA_R0 = (tempR0 > 255) ? 255 : ((tempR0 < 0) ? 0 : tempR0);
//        DATA_G0 = (tempG0 > 255) ? 255 : ((tempG0 < 0) ? 0 : tempG0);
//        DATA_B0 = (tempB0 > 255) ? 255 : ((tempB0 < 0) ? 0 : tempB0);
//    end
//    // Brightness subtraction
//    else begin
//        // Subtract brightness value from each pixel component
//        tempR0 = org_R[WIDTH * row + col] - BRIGHTNESS_VALUE;
//        tempG0 = org_G[WIDTH * row + col] - BRIGHTNESS_VALUE;
//        tempB0 = org_B[WIDTH * row + col] - BRIGHTNESS_VALUE;
//        // Ensure pixel components are within valid range (0 to 255)
//        DATA_R0 = (tempR0 > 255) ? 255 : ((tempR0 < 0) ? 0 : tempR0);
//        DATA_G0 = (tempG0 > 255) ? 255 : ((tempG0 < 0) ? 0 : tempG0);
//        DATA_B0 = (tempB0 > 255) ? 255 : ((tempB0 < 0) ? 0 : tempB0);
//    end
//end
//end        

    if (col >= WIDTH || row >= HEIGHT) begin
        DATA_R0 = 0;
        DATA_G0 = 0;
        DATA_B0 = 0;
        DATA_R1 = 0;
        DATA_G1 = 0;
        DATA_B1 = 0;
    end else begin
        // Otherwise, rotate the image by 180 degrees
        DATA_R0 = org_R[WIDTH * (HEIGHT - row - 1) - col];
        DATA_G0 = org_G[WIDTH * (HEIGHT - row - 1) - col];
        DATA_B0 = org_B[WIDTH * (HEIGHT - row - 1) - col];
        DATA_R1 = org_R[WIDTH * (HEIGHT - row - 1) - col + 1];
        DATA_G1 = org_G[WIDTH * (HEIGHT - row - 1) - col + 1];
        DATA_B1 = org_B[WIDTH * (HEIGHT - row - 1) - col + 1];
    end
  end
end

/*
		if (col >= WIDTH || row >= HEIGHT) begin
			// If we have gone beyond the original image dimensions, output blank pixels
			DATA_R0 = 0;
			DATA_G0 = 0;
			DATA_B0 = 0;
			DATA_R1 = 0;
			DATA_G1 = 0;
			DATA_B1 = 0;
		end else begin
			// Otherwise, rotate the image
			DATA_R0 = org_R[WIDTH * (WIDTH - col - 1) + row];
			DATA_G0 = org_G[WIDTH * (WIDTH - col - 1) + row];
			DATA_B0 = org_B[WIDTH * (WIDTH - col - 1) + row];
			DATA_R1 = org_R[WIDTH * (WIDTH - col - 1) + row + 1];
			DATA_G1 = org_G[WIDTH * (WIDTH - col - 1) + row + 1];
			DATA_B1 = org_B[WIDTH * (WIDTH - col - 1) + row + 1];
		end
*/
/*

        // Image Segmentation by Thresholding
        if (org_R[WIDTH * (HEIGHT - row - 1) - col] > THRESHOLD) begin
            DATA_R0 = 255; // Set the pixel to maximum intensity if above threshold
        end else begin
            DATA_R0 = 0; // Otherwise, set it to black
        end

        if (org_R[WIDTH * (HEIGHT - row - 1) - col + 1] > THRESHOLD) begin
            DATA_R1 = 255; // Set the pixel to maximum intensity if above threshold
        end else begin
            DATA_R1 = 0; // Otherwise, set it to black
        end
    end
end
*/

/*

// Inside the always block for image processing
integer scaled_row, scaled_col;

always @(*) begin
    if (ctrl_data_run) begin
        // Calculate the scaled row and column indices
        scaled_row = row / SCALE_FACTOR;
        scaled_col = col / SCALE_FACTOR;
        
        // Apply scaling by replicating the pixel values
        DATA_R0 = org_R[WIDTH * scaled_row + scaled_col];
        DATA_G0 = org_G[WIDTH * scaled_row + scaled_col];
        DATA_B0 = org_B[WIDTH * scaled_row + scaled_col];
        DATA_R1 = org_R[WIDTH * scaled_row + scaled_col];
        DATA_G1 = org_G[WIDTH * scaled_row + scaled_col];
        DATA_B1 = org_B[WIDTH * scaled_row + scaled_col];
    end
end
*/
/*
image duplication:

integer scaled_row, scaled_col;

always @(*) begin
    if (ctrl_data_run) begin
        // Calculate the scaled row and column indices
        scaled_row = row * SCALE_FACTOR;
        scaled_col = col * SCALE_FACTOR;
        
        // Iterate over each pixel in the original image and replicate it horizontally and vertically
        for (i = 0; i < SCALE_FACTOR; i = i + 1) begin
            for (j = 0; j < SCALE_FACTOR; j = j + 1) begin
                // Apply scaling by replicating the pixel values
                DATA_R0 = org_R[WIDTH * scaled_row + scaled_col];
                DATA_G0 = org_G[WIDTH * scaled_row + scaled_col];
                DATA_B0 = org_B[WIDTH * scaled_row + scaled_col];
                DATA_R1 = org_R[WIDTH * scaled_row + scaled_col];
                DATA_G1 = org_G[WIDTH * scaled_row + scaled_col];
                DATA_B1 = org_B[WIDTH * scaled_row + scaled_col];
            end
        end
    end
end
*/
/*
        if (org_R[WIDTH * row + col] > 150 && org_G[WIDTH * row + col] < 100 && org_B[WIDTH * row + col] < 100) begin
            // Convert the red pixels to pink by setting appropriate RGB values
            DATA_R0 = 255; // Pink color
            DATA_G0 = 192;
            DATA_B0 = 203;
        end else begin
            // Keep the original RGB values for non-red pixels
            DATA_R0 = org_R[WIDTH * row + col];
            DATA_G0 = org_G[WIDTH * row + col];
            DATA_B0 = org_B[WIDTH * row + col];
        end
        // Repeat the same process for the second pixel in the row
        if (org_R[WIDTH * row + col + 1] > 150 && org_G[WIDTH * row + col + 1] < 100 && org_B[WIDTH * row + col + 1] < 100) begin
            DATA_R1 = 255; // Pink color
            DATA_G1 = 192;
            DATA_B1 = 203;
        end else begin
            DATA_R1 = org_R[WIDTH * row + col + 1];
            DATA_G1 = org_G[WIDTH * row + col + 1];
            DATA_B1 = org_B[WIDTH * row + col + 1];
        end
    end
end
*/

/*
image techniques that couldn't be tested because it required a lot of time and power from the computer:

// Histogram equalization
        integer histogram[0:255]; // Histogram array
        integer cdf[0:255];       // Cumulative distribution function array
        integer new_intensity[0:255]; // Array to store new intensity values

        // Compute histogram
        for (i = 0; i < WIDTH*HEIGHT; i = i + 1) begin
            histogram[org_R[i]] = histogram[org_R[i]] + 1; // Assuming the image is grayscale, use only one component (org_R)
        end

        // Compute cumulative distribution function (CDF)
        cdf[0] = histogram[0];
        for (i = 1; i < 256; i = i + 1) begin
            cdf[i] = cdf[i - 1] + histogram[i];
        end

        // Map original intensity values to new intensity values using CDF
        for (i = 0; i < 256; i = i + 1) begin
            new_intensity[i] = (cdf[i] * 255) / (WIDTH*HEIGHT);
        end

        // Apply histogram equalization to each pixel
        for (i = 0; i < WIDTH*HEIGHT; i = i + 1) begin
            org_R[i] = new_intensity[org_R[i]]; // Update the intensity value of the pixel
        end

        // Assign the updated pixel values to the output signals
        DATA_R0 = org_R[WIDTH * (HEIGHT - row - 1) - col];
        DATA_R1 = org_R[WIDTH * (HEIGHT - row - 1) - col + 1];
        // For simplicity, the green and blue components remain unchanged
    end
end

________________________________________________________________________

parameter KERNEL_SIZE = 5; // Size of the Gaussian kernel
parameter KERNEL_RADIUS = (KERNEL_SIZE - 1) / 2; // Radius of the Gaussian kernel
reg signed [15:0] gaussian_kernel[0:KERNEL_SIZE-1][0:KERNEL_SIZE-1];
 
// Initialize the Gaussian kernel coefficients
initial begin
    gaussian_kernel[0][0] = 16'h0001; gaussian_kernel[0][1] = 16'h0004; gaussian_kernel[0][2] = 16'h0007; gaussian_kernel[0][3] = 16'h0004; gaussian_kernel[0][4] = 16'h0001;
    gaussian_kernel[1][0] = 16'h0004; gaussian_kernel[1][1] = 16'h0010; gaussian_kernel[1][2] = 16'h001A; gaussian_kernel[1][3] = 16'h0010; gaussian_kernel[1][4] = 16'h0004;
    gaussian_kernel[2][0] = 16'h0007; gaussian_kernel[2][1] = 16'h001A; gaussian_kernel[2][2] = 16'h0029; gaussian_kernel[2][3] = 16'h001A; gaussian_kernel[2][4] = 16'h0007;
    gaussian_kernel[3][0] = 16'h0004; gaussian_kernel[3][1] = 16'h0010; gaussian_kernel[3][2] = 16'h001A; gaussian_kernel[3][3] = 16'h0010; gaussian_kernel[3][4] = 16'h0004;
    gaussian_kernel[4][0] = 16'h0001; gaussian_kernel[4][1] = 16'h0004; gaussian_kernel[4][2] = 16'h0007; gaussian_kernel[4][3] = 16'h0004; gaussian_kernel[4][4] = 16'h0001;
end

always @(*) begin
	
	HSYNC   = 1'b0;
	DATA_R0 = 0;
	DATA_G0 = 0;
	DATA_B0 = 0;                                       
	DATA_R1 = 0;
	DATA_G1 = 0;
	DATA_B1 = 0;                                         
	if(ctrl_data_run) begin
		
		HSYNC   = 1'b1;
        
        for (i = 0; i < WIDTH*HEIGHT; i = i + 1) begin
      blur_R[i] <= org_R[i];
      blur_G[i] <= org_G[i];
      blur_B[i] <= org_B[i];
    end
  end
  else begin
    for (i = KERNEL_RADIUS; i < HEIGHT - KERNEL_RADIUS; i = i + 1) begin
      for (j = KERNEL_RADIUS; j < WIDTH - KERNEL_RADIUS; j = j + 1) begin
        sum_R = 0;
        sum_G = 0;
        sum_B = 0;
        for (m = -KERNEL_RADIUS; m <= KERNEL_RADIUS; m = m + 1) begin
          for (n = -KERNEL_RADIUS; n <= KERNEL_RADIUS; n = n + 1) begin
            sum_R = sum_R + gaussian_kernel[KERNEL_RADIUS+m][KERNEL_RADIUS+n] * org_R[(i+m)*WIDTH+(j+n)];
            sum_G = sum_G + gaussian_kernel[KERNEL_RADIUS+m][KERNEL_RADIUS+n] * org_G[(i+m)*WIDTH+(j+n)];
            sum_B = sum_B + gaussian_kernel[KERNEL_RADIUS+m][KERNEL_RADIUS+n] * org_B[(i+m)*WIDTH+(j+n)];
          end
        end
        blur_R[i*WIDTH+j] <= sum_R / 273; // Dividing by the sum of all coefficients
        blur_G[i*WIDTH+j] <= sum_G / 273; // Dividing by the sum of all coefficients
        blur_B[i*WIDTH+j] <= sum_B / 273; // Dividing by the sum of all coefficients
      end
    end
  end
end
*/

endmodule

