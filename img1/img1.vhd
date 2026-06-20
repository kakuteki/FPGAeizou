-- ============================================================
-- img1 : DE0-CV VGA 640x480@60Hz で 320x240 画像ROMを2倍表示
--   ・画像は image.mif で初期化したM10K ROM(12bit=4:4:4, 76800語)。
--   ・表示時に sx=hx/2, sy=hy/2 で参照=単純2倍スケールアップ。
--   ・ROM読出レイテンシ1サイクル。HS/VS/RGBを全てstage-2レジスタに
--     揃える2段パイプラインで同期と映像を1pxもズラさない。
--   ・vga1(カラーバー)と同じくCLOCK_50単一ドメイン+25MHzイネーブル。
-- ============================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity img1 is
    port (
        CLOCK_50 : in  std_logic;
        VGA_R    : out std_logic_vector(3 downto 0);
        VGA_G    : out std_logic_vector(3 downto 0);
        VGA_B    : out std_logic_vector(3 downto 0);
        VGA_HS   : out std_logic;
        VGA_VS   : out std_logic
    );
end img1;

architecture RTL of img1 is

    -- 640x480@60Hz タイミング
    constant H_VISIBLE : integer := 640;
    constant H_FRONT   : integer := 16;
    constant H_SYNC    : integer := 96;
    constant H_TOTAL   : integer := 800;
    constant V_VISIBLE : integer := 480;
    constant V_FRONT   : integer := 10;
    constant V_SYNC    : integer := 2;
    constant V_TOTAL   : integer := 525;

    -- 画像ストア解像度
    constant IMG_W : integer := 320;
    constant IMG_H : integer := 240;
    constant ROM_DEPTH : integer := IMG_W * IMG_H;   -- 76800

    -- M10K ROM (image.mifで初期化)
    type rom_t is array (0 to ROM_DEPTH-1) of std_logic_vector(11 downto 0);
    signal rom : rom_t;
    attribute ram_init_file : string;
    attribute ram_init_file of rom : signal is "image.mif";
    attribute ramstyle : string;
    attribute ramstyle of rom : signal is "M10K";

    signal pix_en  : std_logic := '0';
    signal hcount  : integer range 0 to H_TOTAL-1 := 0;
    signal vcount  : integer range 0 to V_TOTAL-1 := 0;

    -- stage-1 レジスタ(ROM読出と同じ深さ)
    signal rom_q : std_logic_vector(11 downto 0) := (others => '0');
    signal hs1, vs1, von1 : std_logic := '0';

begin

    process(CLOCK_50)
        variable hs_c, vs_c, von_c : std_logic;
        variable sx, sy, addr      : integer range 0 to ROM_DEPTH-1;
    begin
        if rising_edge(CLOCK_50) then
            pix_en <= not pix_en;

            if pix_en = '1' then
                -- カウンタ更新
                if hcount = H_TOTAL-1 then
                    hcount <= 0;
                    if vcount = V_TOTAL-1 then
                        vcount <= 0;
                    else
                        vcount <= vcount + 1;
                    end if;
                else
                    hcount <= hcount + 1;
                end if;

                -- 現在のhcount/vcountから同期・表示有効を算出(負論理)
                if (hcount >= H_VISIBLE + H_FRONT) and
                   (hcount <  H_VISIBLE + H_FRONT + H_SYNC) then
                    hs_c := '0';
                else
                    hs_c := '1';
                end if;
                if (vcount >= V_VISIBLE + V_FRONT) and
                   (vcount <  V_VISIBLE + V_FRONT + V_SYNC) then
                    vs_c := '0';
                else
                    vs_c := '1';
                end if;
                if (hcount < H_VISIBLE) and (vcount < V_VISIBLE) then
                    von_c := '1';
                else
                    von_c := '0';
                end if;

                -- ROMアドレス(2倍スケール: hx/2, hy/2)。範囲外は0で安全。
                if von_c = '1' then
                    sx   := hcount / 2;             -- 0..319
                    sy   := vcount / 2;             -- 0..239
                    addr := sy * IMG_W + sx;        -- 0..76799
                else
                    addr := 0;
                end if;

                -- stage-1: ROM読出(レイテンシ1)と同期/表示有効を同じ段で保持
                rom_q <= rom(addr);
                hs1   <= hs_c;
                vs1   <= vs_c;
                von1  <= von_c;

                -- stage-2: 全出力を同一レイテンシで確定
                VGA_HS <= hs1;
                VGA_VS <= vs1;
                if von1 = '1' then
                    VGA_R <= rom_q(11 downto 8);
                    VGA_G <= rom_q(7 downto 4);
                    VGA_B <= rom_q(3 downto 0);
                else
                    VGA_R <= "0000";
                    VGA_G <= "0000";
                    VGA_B <= "0000";   -- ブランキングは黒
                end if;
            end if;
        end if;
    end process;

end RTL;
