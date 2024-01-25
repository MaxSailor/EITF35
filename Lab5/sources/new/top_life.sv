
`default_nettype none
`timescale 1ns / 1ps

module top_life (
    input  wire logic clk_100m,     // 100 MHz clock
    input  wire logic btn_rst_n,    // reset button
    input  wire logic btn_fire,
    input  wire logic btn_up,
    input  wire logic btn_dn,
    input  wire logic btn_l,
    input  wire logic btn_r,
    input  wire logic runPin,    
    output      logic vga_hsync,    // VGA horizontal sync
    output      logic vga_vsync,    // VGA vertical sync
    output      logic [3:0] vga_r,  // 4-bit VGA red
    output      logic [3:0] vga_g,  // 4-bit VGA green
    output      logic [3:0] vga_b   // 4-bit VGA blue
    );

    // generate pixel clock
    logic clk_pix;
    logic clk_pix_locked;
    clock_480p clock_pix_inst (
       .clk_100m,
       .rst(!btn_rst_n),  // reset button is active low
       .clk_pix,
       /* verilator lint_off PINCONNECTEMPTY */
       .clk_pix_5x(),  // not used for VGA output
       /* verilator lint_on PINCONNECTEMPTY */
       .clk_pix_locked
    );

    // display sync signals and coordinates
    localparam CORDW = 10;  // screen coordinate width in bits
    /* verilator lint_off UNUSED */
    logic [CORDW-1:0] sx, sy;
    /* verilator lint_on UNUSED */
    logic hsync, vsync, de;
    simple_480p display_inst (
        .clk_pix,
        .rst_pix(!clk_pix_locked),  // wait for clock lock
        .sx,
        .sy,
        .hsync,
        .vsync,
        .de
    );
    
    logic sig_fire,sig_up,sig_dn,sig_l,sig_r;
    debouncer deb_fire (.clk(clk_pix), .in(btn_fire), .out(sig_fire));
    debouncer deb_up (.clk(clk_pix), .in(btn_up), .out(sig_up));
    debouncer deb_dn (.clk(clk_pix), .in(btn_dn), .out(sig_dn));
    debouncer deb_l (.clk(clk_pix), .in(btn_l), .out(sig_l));
    debouncer deb_r (.clk(clk_pix), .in(btn_r), .out(sig_r));

    // bitmap: MSB first, so we can write pixels left to right
    /* verilator lint_off LITENDIAN */
    
    localparam unsigned HEIGHT = 62;
    localparam unsigned WIDTH = 82;
    logic [0:WIDTH - 1] bmap [HEIGHT];  // 20 pixels by 15 lines
    logic [0:WIDTH - 1] next_bmap [HEIGHT];  // 20 pixels by 15 lines
    
    /* verilator lint_on LITENDIAN */
    integer ix, iy;
    //updates the bitmap
    always_ff @(posedge clk_pix, negedge btn_rst_n)begin
        if(!btn_rst_n)begin
            for(ix = 0; ix < WIDTH; ix = ix + 1)begin
                for(iy = 0; iy < HEIGHT; iy = iy + 1)begin
                    bmap[iy][ix] <= 0;
                end
            end
        end else begin
            bmap <= next_bmap;
        end
    end
    
    //Logic for counting up to a gametic
    logic[32:0] ticCntr;
    
    always_ff @(posedge clk_pix, negedge btn_rst_n)begin
        if(!btn_rst_n)begin
            ticCntr <= 32'b0;
        end else if (ticCntr == 32'd5_000_000 && runPin) begin
            ticCntr <= 0;
        end else if(runPin) begin
            ticCntr <= ticCntr + 1;
        end else begin
            ticCntr <= 0;
        end
    end
    
    //player controls
    logic [$clog2(WIDTH) - 1:0] player_x, next_player_x;
    logic [$clog2(HEIGHT) - 1:0] player_y, next_player_y;
    
    always_ff @ (posedge clk_pix, negedge btn_rst_n) begin 
        if(!btn_rst_n)begin
            player_x <= WIDTH / 2;
            player_y <= HEIGHT / 2;
        end else begin
            player_x <= next_player_x;
            player_y <= next_player_y;
        end  
    end
    
    //calculates the value of each square for next tic
    //
    always_comb begin
        next_bmap = bmap;
        next_player_x = player_x;
        next_player_y = player_y;
        if(ticCntr == 32'd5_000_000 && runPin)begin //if gametic and simulation running
            for(ix = 1; ix < WIDTH - 1; ix = ix + 1) begin
                for(iy = 1; iy < HEIGHT - 1; iy = iy + 1) begin                
                    if(bmap[iy - 1][ix] + bmap[iy - 1][ix - 1] + bmap[iy - 1][ix + 1] + bmap[iy][ix + 1] + bmap[iy][ix - 1] + bmap[iy + 1][ix] + bmap[iy + 1][ix - 1] + bmap[iy + 1][ix + 1] == 3)begin
                        next_bmap[iy][ix] = 1; //If 3 neighbours are alive, cell will be alive
                    end else if(bmap[iy - 1][ix] + bmap[iy - 1][ix - 1] + bmap[iy - 1][ix + 1] + bmap[iy][ix + 1] + bmap[iy][ix - 1] + bmap[iy + 1][ix] + bmap[iy + 1][ix - 1] + bmap[iy + 1][ix + 1] == 2)begin
                        next_bmap[iy][ix] = bmap[iy][ix]; //If 2 neighbours are alive, cell will be keep its current state
                    end else begin
                        next_bmap[iy][ix] = 0; //If any other number of cells are alive, cell will be dead
                    end
                end
            end
        end else if(!runPin)begin //if simulation not running player control is allowed
            if(sig_up && player_y > 1)begin
                next_player_y = player_y - 1; 
            end else if(sig_dn && player_y < HEIGHT - 1)begin
                next_player_y = player_y + 1;        
            end else if(sig_l && player_x > 1)begin
                next_player_x = player_x - 1;
            end else if(sig_r && player_y < WIDTH - 1)begin
                next_player_x = player_x + 1;       
            end else if(sig_fire)begin
                next_bmap[player_y][player_x] = !bmap[player_y][player_x];
            end
        end
    end
    
    
    logic alive;
    logic playerOutline;
    logic [$clog2(WIDTH) - 1:0] x;  // address for x
    logic [$clog2(HEIGHT) - 1:0] y;  // address for y
    always_comb begin
        if(sx[9:10 - $clog2(WIDTH)] + 1 == player_x && sy[8:9 - $clog2(HEIGHT)] + 1 == player_y && (sx[9 - $clog2(WIDTH):0] == 3'b000 || sx[9 - $clog2(WIDTH):0] == 3'b111 || sy[8 - $clog2(HEIGHT):0] == 3'b000 || sy[8 - $clog2(HEIGHT):0] == 3'b111) && !runPin)begin
            //if edge of player square, paint red. Only when simulation not running
            playerOutline = de ? 1 : 0;
            alive = 0;
        end else begin
            x = sx[9:10 - $clog2(WIDTH)] + 1;  //Convert to game resolution
            y = sy[8:9 - $clog2(HEIGHT)] + 1;  //Convert to game resolution
            alive = de ? bmap[y][x] : 0;  // look up pixel (unless we're in blanking)
            playerOutline = 0;
        end
    end

    // paint colour: yellow alive, blue dead, red outline
    logic [3:0] paint_r, paint_g, paint_b;
    always_comb begin
        
        if(alive)begin
            paint_r =4'hF;
            paint_g =4'hC;
            paint_b =4'h0;
        end else if(playerOutline)begin
            paint_r =4'hF;
            paint_g =4'h0;
            paint_b =4'h0;
        end else begin
            paint_r =4'h1;
            paint_g =4'h3;
            paint_b =4'h7;
        end
        
    end

    // display colour: paint colour but black in blanking interval
    logic [3:0] display_r, display_g, display_b;
    always_comb begin
        display_r = (de) ? paint_r : 4'h0;
        display_g = (de) ? paint_g : 4'h0;
        display_b = (de) ? paint_b : 4'h0;
    end

    // VGA output
    always_ff @(posedge clk_pix) begin
        vga_hsync <= hsync;
        vga_vsync <= vsync;
        vga_r <= display_r;
        vga_g <= display_g;
        vga_b <= display_b;
    end
endmodule