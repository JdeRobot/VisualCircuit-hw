//------------------------------------------------------------------------------
//   Felipe Machado Sanchez
//   Area de Tecnologia Electronica
//   Universidad Rey Juan Carlos
//   https://github.com/felipe-m
//
//   ov7670_capture.v
//   
//-----------------------------------------------------------------------------

module ov7670_capture
  #(parameter
    // VGA
    //c_img_cols    = 640, // 10 bits
    //c_img_rows    = 480, //  9 bits
    //c_img_pxls    = c_img_cols * c_img_rows,
    //c_nb_line_pxls = 10, // log2i(c_img_cols-1) + 1;
    // c_nb_img_pxls = log2i(c_img_pxls-1) + 1
    //c_nb_img_pxls =  19,  //640*480=307,200 -> 2^19=524,288
    // QQVGA
    //c_img_cols    = 160, // 8 bits
    //c_img_rows    = 120, //  7 bits
    //c_img_pxls    = c_img_cols * c_img_rows,
    //c_nb_line_pxls = 8, // log2i(c_img_cols-1) + 1;
    //c_nb_img_pxls =  15,  //160*120=19.200 -> 2^15
    // QQVGA/2
    c_img_cols    = 80, // 7 bits
    c_img_rows    = 60, // 6 bits
    c_img_pxls    = c_img_cols * c_img_rows,
    c_nb_line_pxls = 7, // log2i(c_img_cols-1) + 1;
    c_nb_img_pxls =  13,  //80*60=4800 -> 2^13


    c_nb_buf_red   =  4,  // n bits for red in the buffer (memory)
    c_nb_buf_green =  4,  // n bits for green in the buffer (memory)
    c_nb_buf_blue  =  4,  // n bits for blue in the buffer (memory)
    // word width of the memory (buffer)
    c_nb_buf       =   c_nb_buf_red + c_nb_buf_green + c_nb_buf_blue
  )
  (
   input          rst,    // FPGA reset
   input          clk,    // FPGA clock
    // camera pclk (byte clock) (~40ns)  
    // 2 bytes is a pixel
    input         pclk,
    input         href,
    input         vsync,
    input  [2:0]  sw13_rgbmode,
    output [11:0] dataout_test,
    output reg [3:0]  led_test,
    input  [7:0]  data,
    output [c_nb_img_pxls-1:0] addr,
    output [c_nb_buf-1:0]  dout,
    output        we
  );

  reg        pclk_rg1, pclk_rg2;  // registered pclk
  reg        href_rg1, href_rg2;  // registered href
  reg        vsync_rg1, vsync_rg2;// registered vsync
  reg [7:0]  data_rg1, data_rg2;  //registered data

  reg        pclk_rg3, href_rg3, vsync_rg3; //3rd
  reg [7:0]  data_rg3;     // registered data 3rd

  // it seems that vsync has some spurious 
  wire       vsync_3up;

  wire       pclk_fall;
  wire       pclk_rise_prev;
  wire       pclk_rise;

  reg        cnt_byte; // count to 2: 2 bytes per pixel
  reg [c_nb_img_pxls-1:0]  cnt_pxl;
  // number of pixels in the previous lines, not considering the actual line
  reg [c_nb_img_pxls-1:0]  cnt_pxl_base;
  reg [c_nb_line_pxls-1:0] cnt_line_pxl;
  reg [c_nb_line_pxls-1:0] cnt_line_totpxls;

  // indicates if the column is in the frame of the image (taking less cols)
  wire       col_inframe;
  // indicates if the number of pixels are in the frame of the image
  // (taking less rows and cols)
  wire       img_inframe;

   // there should be 4 clks in a pclk (byte), but just in case, make 
   // another bit to avoid overflow and go back in 0 before time
  reg [4:0]    cnt_clk;
  reg [4:0]    cnt_pclk_max;
  reg [4:0]    cnt_pclk_max_freeze;

  reg [25:0]   cnt_05seg;
  parameter    c_cnt_05seg_end = 50_000_000;

  reg  [7:0]   gray;
  reg  [c_nb_buf_red-1:0]   red;
  reg  [c_nb_buf_red-1:0]   green;
  reg  [c_nb_buf_red-1:0]   blue;
   
  // to test the number of
  always @ (posedge rst, posedge clk)
  begin
    if (rst) begin
      cnt_clk <= 0;
      cnt_pclk_max <= 0;
      led_test[0] <= 1'b0;
    end
    else begin
      if (pclk_fall) begin
        cnt_clk <= 0;
        led_test[0] <= 1'b1;
        cnt_pclk_max <= cnt_clk;
      end
      else
        cnt_clk <= cnt_clk + 1;
    end
  end

  always @ (posedge rst, posedge clk)
  begin
    if (rst) begin
      cnt_pclk_max_freeze <= 0;
      cnt_05seg <= 0;
    end
    else begin
      if (cnt_05seg == c_cnt_05seg_end) begin
        cnt_05seg <= 0;
        cnt_pclk_max_freeze <= cnt_pclk_max;
      end
      else
        cnt_05seg <= cnt_05seg + 1;
    end
  end

  // register 3 times all the camera inputs to synchronize
  always @ (posedge rst, posedge clk)
  begin
    if (rst) begin
      pclk_rg1  <= 1'b0;
      pclk_rg2  <= 1'b0;
      href_rg1  <= 1'b0;
      href_rg2  <= 1'b0;
      vsync_rg1 <= 1'b0;
      vsync_rg2 <= 1'b0;
      data_rg1  <= 0;
      data_rg2  <= 0;
      // 3rd to detect falling edge
      pclk_rg3  <= 1'b0;
      href_rg3  <= 1'b0;
      vsync_rg3 <= 1'b0;
      data_rg3  <= 0;
    end
    else begin
      pclk_rg1  <= pclk;
      pclk_rg2  <= pclk_rg1;
      href_rg1  <= href;
      href_rg2  <= href_rg1;
      vsync_rg1 <= vsync;
      vsync_rg2 <= vsync_rg1;
      data_rg1  <= data;
      data_rg2  <= data_rg1;
      // 3rd
      pclk_rg3  <= pclk_rg2;
      href_rg3  <= href_rg2;
      vsync_rg3 <= vsync_rg2;
      data_rg3  <= data_rg2;
    end
  end

  // since some times it is up up to 2 cycles, has to be '1' during
  // the 3 following cycles
  assign vsync_3up = vsync_rg3 && vsync_rg2 && vsync_rg1 && vsync;

  // FPGA clock is 10ns and pclk is 40ns
  //pclk_fall <= '1' when (pclk_rg2='0' and pclk_rg3='1') else '0';
  assign pclk_fall = ((pclk_rg2 == 1'b0) && pclk_rg3)? 1'b1 : 1'b0;
  assign pclk_rise_prev = (pclk_rg1 && (pclk_rg2 == 1'b0))? 1'b1 : 1'b0;
  assign pclk_rise = (pclk_rg2 && (pclk_rg3 == 1'b0))? 1'b1 : 1'b0;

  // each pixel has 2 bytes, each byte in each pclk
  // each pixel -> 2 pclk
  always @ (posedge rst, posedge clk)
  begin
    if (rst) begin
      cnt_pxl          <= 0;
      cnt_line_pxl     <= 0;
      cnt_pxl_base     <= 0;
      cnt_line_totpxls <= 0;
      cnt_byte         <= 1'b0;
    end
    else begin
      //if vsync_rg3 = '1' then // there are some glitches
      if (vsync_3up) begin // new screen
        cnt_pxl      <= 0;
        cnt_pxl_base <= 0;
        cnt_line_pxl <= 0;
        cnt_byte     <= 1'b0;
      end
      else if (href_rg3) begin // is zero at optical blank COM[6]
        if (img_inframe) begin
          if (pclk_fall &&  col_inframe) begin
            if (cnt_byte) begin
              cnt_pxl <= cnt_pxl + 1;
              cnt_line_pxl <= cnt_line_pxl + 1;
            end
            cnt_byte <= ~cnt_byte;
          end
          if (href_rg2 == 1'b0) begin // will be a falling edge
            // new line
            cnt_line_totpxls <= cnt_line_pxl; // cnt_line_totpxls is to test
            // it is not reliable to count all the pixels of a line,
            // some lines have more other less
            cnt_pxl <= cnt_pxl_base + c_img_cols;
            cnt_pxl_base <= cnt_pxl_base + c_img_cols;
            cnt_line_pxl <= 0;
          end
        end
        else begin
          cnt_byte <= 1'b0;
          cnt_line_pxl <= 0;
        end
      end
    end
  end

  assign col_inframe = ( cnt_line_pxl < c_img_cols) ? 1'b1 : 1'b0;
  assign img_inframe = ( cnt_pxl < c_img_pxls) ? 1'b1 : 1'b0;

  //dataout_test <= "00" & std_logic_vector(cnt_line_totpxls); // 2 + 10 bits
  assign dataout_test = {7'b0000000, cnt_pclk_max_freeze}; // 7 + 5 bits

  always @ (posedge rst, posedge clk)
  begin
    if (rst) begin
      red   <= 0;
      green <= 0;
      blue  <= 0;
    end
    else begin
      if (href_rg3) begin  // visible
        //if (cnt_clk == 3'b001) begin // I think this is the safest
        if (pclk_rise_prev == 1'b1) begin
          if (cnt_byte == 1'b0) begin
             case (sw13_rgbmode)
               3'b000: // RGB444
                 red <= data_rg3[3:0];
               3'b001: begin // RGB555
                 red  <= data_rg3[6:3];
                 green[3:2] <= data_rg3[1:0];
               end
               3'b010: begin // RGB565
                 red   <= data_rg3[7:4];
                 green[3:1] <= data_rg3[2:0];
               end
               3'b011: // YUV (gray first byte)
                 gray  <= data_rg3;
               //default:
               //  null;
             endcase
          end
          else begin
             case (sw13_rgbmode)
               3'b000: begin // RGB444
                 green <= data_rg3[7:4];
                 blue <= data_rg3[3:0];
               end
               3'b001: begin // RGB555
                 green [1:0] <= data_rg3[7:6];
                 blue <= data_rg3[4:1];
               end
               3'b010: begin // RGB565
                 blue <= data_rg3[4:1];
                 green [0] <= data_rg3[7];
               end
               3'b011: begin// YUV (gray first byte)
                 // do nothing
               end
               default: // YUV (Y gray second byte)
                 gray  <= data_rg3;
             endcase
          end
        end
      end
    end
  end

  //dout <= (red & green & blue) when unsigned(sw13_rgbmode) < 3 else gray;
  assign dout = (sw13_rgbmode < 3) ? {red, green, blue} : {4'b000, gray};
  //dout <= std_logic_vector(cnt_pxl(7 downto 0));
  assign addr = cnt_pxl;

  assign we = (href_rg3 && cnt_byte && pclk_rise && col_inframe && img_inframe)? 1'b1 : 1'b0;

endmodule

