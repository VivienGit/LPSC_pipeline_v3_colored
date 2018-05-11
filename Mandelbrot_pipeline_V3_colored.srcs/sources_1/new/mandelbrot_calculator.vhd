-------------------------------------------------------------------------------
-- Title       : mandelbrot_calculator
-- Project     : MSE Mandelbrot
-------------------------------------------------------------------------------
-- File        : mandelbrot_calculator.vhd
-- Authors     : Vivien Kaltenrieder
-- Company     : HES-SO
-- Created     : 23.05.2018
-- Last update : 23.05.2018
-- Platform    : Vivado (synthesis)
-- Standard    : VHDL'08
-------------------------------------------------------------------------------
-- Description: mandelbrot_calculator
-------------------------------------------------------------------------------
-- Copyright (c) 2018 HES-SO, Lausanne
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author  Description
-- 25.03.2018   0.0      VKR      Created
-- 02.03.2018   0.0      VKR      Sequential version
-- 07.03.2018   1.0      VKR      Combinatory version
-- 05.05.2018   2.0      VKR      Adding the buffer for the pipeline
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library UNISIM;
use UNISIM.VComponents.all;

entity mandelbrot_calculator is
generic (
  comma       : integer := 12;
  max_iter    : integer := 100;
  SIZE        : integer := 16;
  ITER_SIZE   : integer := 7;
  X_ADD_SIZE  : integer := 10;
  Y_ADD_SIZE  : integer := 10);

  port(
      clk_i         : in std_logic;
      rst_i         : in std_logic;
      finished_o    : out std_logic;
      c_real_i      : in std_logic_vector(SIZE-1 downto 0);
      c_imaginary_i : in std_logic_vector(SIZE-1 downto 0);
      iterations_o  : out std_logic_vector(ITER_SIZE-1 downto 0);
      x_o           : out std_logic_vector(X_ADD_SIZE-1 downto 0);
      y_o           : out std_logic_vector(Y_ADD_SIZE-1 downto 0);
      x_i           : in std_logic_vector(X_ADD_SIZE-1 downto 0);
      y_i           : in std_logic_vector(Y_ADD_SIZE-1 downto 0)
  );

end mandelbrot_calculator;

architecture Behavioral of mandelbrot_calculator is

  -- Size constants
  constant SIZE_BIG           : integer := 2*SIZE;
  constant SIZE_IN_BIG        : integer := comma+SIZE;
  constant COMMA_BIG          : integer := 2*comma;
  constant SIZE_RADIUS        : integer := 2*(SIZE-comma);
  constant EXTEND_COMMA       : std_logic_vector(comma-1 downto 0) := (others => '0');
  constant NB_PIPES           : integer := 3;

  -- Command signals
  signal finished_s           : std_logic;
  signal one_is_finished_s    : std_logic;
  signal pipe_isnt_full_s     : std_logic;

  -- Stat machine states
  constant ASK_1_STATE        : std_logic_vector := "00";
  constant ASK_2_STATE        : std_logic_vector := "01";  
  constant ASK_3_STATE        : std_logic_vector := "10";
  constant CALC_STATE         : std_logic_vector := "11";
  signal next_state_s         : std_logic_vector (1 downto 0);
  signal current_state_s      : std_logic_vector (1 downto 0);

  -- Calculation signals
  signal z_real_s             : std_logic_vector(SIZE-1 downto 0);
  signal zn1_real_big_s       : std_logic_vector(SIZE_BIG-1 downto 0);
  signal z_imag_s             : std_logic_vector(SIZE-1 downto 0); 
  signal zn1_imag_big_s       : std_logic_vector(SIZE_BIG-1 downto 0);
  signal z_real2_big_s        : std_logic_vector(SIZE_BIG-1 downto 0);
  signal zn1_real2_big_s      : std_logic_vector(SIZE_BIG-1 downto 0);
  signal z_r2_i2_big_s        : std_logic_vector(SIZE_BIG-1 downto 0);
  signal zn1_r2_i2_big_s      : std_logic_vector(SIZE_BIG-1 downto 0); 
  signal z_ri_big_s           : std_logic_vector(SIZE_BIG-1 downto 0);
  signal zn1_ri_big_s         : std_logic_vector(SIZE_BIG-1 downto 0);
  signal z_imag2_big_s        : std_logic_vector(SIZE_BIG-1 downto 0);
  signal zn1_imag2_big_s      : std_logic_vector(SIZE_BIG-1 downto 0);
  signal z_2ri_big_s          : std_logic_vector(SIZE_BIG-1 downto 0);
  signal zn1_2ri_big_s        : std_logic_vector(SIZE_BIG-1 downto 0);

  signal n1_radius_big_s      : std_logic_vector(SIZE_BIG downto 0);    
  signal radius_s             : std_logic_vector(SIZE_RADIUS downto 0);

  -- Input shifter signals
  signal c_real_s             : std_logic_vector(SIZE-1 downto 0);
  signal cn1_real_s           : std_logic_vector(SIZE-1 downto 0);
  signal cn2_real_s           : std_logic_vector(SIZE-1 downto 0);
  signal c_imag_s             : std_logic_vector(SIZE-1 downto 0);
  signal cn1_imag_s           : std_logic_vector(SIZE-1 downto 0);
  signal cn2_imag_s           : std_logic_vector(SIZE-1 downto 0);
  
  -- Iteration shifter signals
  signal iteration_s          : std_logic_vector(ITER_SIZE-1 downto 0);
  signal n1_iteration_s       : std_logic_vector(ITER_SIZE-1 downto 0);
  signal n2_iteration_s       : std_logic_vector(ITER_SIZE-1 downto 0);
  
  -- Address shifter signals
  signal x_address_s          : std_logic_vector(Y_ADD_SIZE-1 downto 0);
  signal n1_x_address_s       : std_logic_vector(Y_ADD_SIZE-1 downto 0);
  signal n2_x_address_s       : std_logic_vector(Y_ADD_SIZE-1 downto 0);
  signal y_address_s          : std_logic_vector(Y_ADD_SIZE-1 downto 0);
  signal n1_y_address_s       : std_logic_vector(Y_ADD_SIZE-1 downto 0);
  signal n2_y_address_s       : std_logic_vector(Y_ADD_SIZE-1 downto 0);

begin
  -- Combinatory part
  finished_s <= one_is_finished_s;
  finished_o <= finished_s;
  
  iterations_o <= iteration_s;
  
  x_o     <= x_address_s;
  y_o     <= y_address_s;

  ----------------------------------------------
  --             calc_proc             ---------
  ----------------------------------------------
  calc_proc : process (all)
  begin
      one_is_finished_s <= '0';
   
      ----------------- Calcul the real part      --------------------
      -- Calcul the squared of the input values
      zn1_real2_big_s   <= std_logic_vector(signed(z_real_s)*signed(z_real_s));
      zn1_imag2_big_s   <= std_logic_vector(signed(z_imag_s)*signed(z_imag_s));
      -- Substraction of the squared inputs
      zn1_r2_i2_big_s   <= std_logic_vector(signed(z_real2_big_s)-signed(z_imag2_big_s));
      -- New value of the output (next value of the input)
      zn1_real_big_s  <= std_logic_vector(signed(std_logic_vector'(c_real_s & EXTEND_COMMA)) + signed(z_r2_i2_big_s));
  
      ----------------- Calcul the imaginary part  --------------
      -- Multiplication of the two inputs
      zn1_ri_big_s    <= std_logic_vector(signed(z_real_s)*signed(z_imag_s));
      -- Multiplication by 2
      zn1_2ri_big_s   <= z_ri_big_s(SIZE_BIG-2 downto 0) & '0';
      -- New value of the output (next value of the input)
      zn1_imag_big_s  <= std_logic_vector(signed(std_logic_vector'(c_imag_s & EXTEND_COMMA)) + signed(z_2ri_big_s));
   
      
      ------------------ Calcul the radius ----------------------
      n1_radius_big_s    <= std_logic_vector(signed(z_real2_big_s(SIZE_BIG-1) & z_real2_big_s)+signed(z_imag2_big_s(SIZE_BIG-1) & z_imag2_big_s));
  
      ------------------ Condition to finish one ---------------- 
      if signed(radius_s) >= 4 or unsigned(iteration_s) >= max_iter then
          one_is_finished_s <= '1';       
      end if;
  end process; -- calc_proc

    ----------------------------------------------
     --       Output Buffer and synch           --
    ----------------------------------------------
    buffer_proc : process (all)
    begin
        if rst_i = '1' then
            z_real_s          <= (others => '0');
            z_imag_s          <= (others => '0');
            z_real2_big_s     <= (others => '0');
            z_imag2_big_s     <= (others => '0');
            z_r2_i2_big_s     <= (others => '0');
            z_ri_big_s        <= (others => '0');
            z_2ri_big_s       <= (others => '0');
            iteration_s       <= (others => '0');
            n1_iteration_s    <= (others => '0');
            n2_iteration_s    <= (others => '0');
            c_real_s          <= (others => '0');
            cn1_real_s        <= (others => '0');
            cn2_real_s        <= (others => '0');
            c_imag_s          <= (others => '0');
            cn1_imag_s        <= (others => '0');
            cn2_imag_s        <= (others => '0');
        elsif Rising_Edge(clk_i) then
            if (one_is_finished_s = '1' or pipe_isnt_full_s = '1') then
                z_real_s          <= (others => '0');
                z_imag_s          <= (others => '0');
                n2_x_address_s    <= x_i;
                n2_y_address_s    <= y_i;
                cn2_real_s        <= c_real_i;
                cn2_imag_s        <= c_imaginary_i; 
                n2_iteration_s    <= (others => '0');   
            else                 
                z_real_s          <= zn1_real_big_s(SIZE_IN_BIG-1 downto comma);
                z_imag_s          <= zn1_imag_big_s(SIZE_IN_BIG-1 downto comma);
                n2_x_address_s    <= x_address_s;
                n2_y_address_s    <= y_address_s;
                cn2_real_s        <= c_real_s;
                cn2_imag_s        <= c_imag_s;
                n2_iteration_s    <= std_logic_vector(unsigned(iteration_s) + 1);
            end if;
            z_real2_big_s     <= zn1_real2_big_s;
            z_imag2_big_s     <= zn1_imag2_big_s;
            z_r2_i2_big_s     <= zn1_r2_i2_big_s;
            z_ri_big_s        <= zn1_ri_big_s;
            z_2ri_big_s       <= zn1_2ri_big_s;
            radius_s          <= std_logic_vector(n1_radius_big_s(SIZE_BIG downto COMMA_BIG));
            n1_x_address_s    <= n2_x_address_s;
            x_address_s       <= n1_x_address_s;
            n1_y_address_s    <= n2_y_address_s;
            y_address_s       <= n1_y_address_s;
            cn1_real_s        <= cn2_real_s;
            cn1_imag_s        <= cn2_imag_s;
            c_real_s          <= cn1_real_s;
            c_imag_s          <= cn1_imag_s;
            n1_iteration_s    <= n2_iteration_s;
            iteration_s       <= n1_iteration_s;
                       
        end if; -- End risign edge
    end process; -- buffer_proc

    ----------------------------------------------
    --           State machine                  --
    ----------------------------------------------
    state_machine : process (all)
    begin
        next_state_s      <= ASK_1_STATE;
        pipe_isnt_full_s  <= '0';
        
        -- State machine
        case current_state_s is
            when ASK_1_STATE =>
                pipe_isnt_full_s <= '1';
                next_state_s <= ASK_2_STATE;
            when ASK_2_STATE =>
                pipe_isnt_full_s <= '1';
                if one_is_finished_s = '1' then
                    next_state_s  <= ASK_2_STATE;
                else
                    next_state_s  <= ASK_3_STATE;
                end if;
            when ASK_3_STATE =>
                 pipe_isnt_full_s <= '1';
                if one_is_finished_s = '1' then
                    next_state_s  <= ASK_3_STATE;
                else
                    next_state_s  <= CALC_STATE;
                end if;
            when CALC_STATE  =>
                if one_is_finished_s = '1' then
                    pipe_isnt_full_s <= '1';
                end if;
                next_state_s  <= CALC_STATE;
            when others =>
              next_state_s <= ASK_1_STATE;
        end case;
    end process; -- state_machine

    ----------------------------------------------
    --           synch state machine            --
    ----------------------------------------------
  	 synch_proc : process (all)
     begin
        if (rst_i = '1') then
          current_state_s <= ASK_1_STATE;
        elsif Rising_Edge(clk_i) then
          current_state_s <= next_state_s;
        end if;
    end process; -- synch_proc

end Behavioral;
