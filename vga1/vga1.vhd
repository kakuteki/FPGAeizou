-- ============================================================
-- vga1 : DE0-CV VGA 640x480@60Hz テストパターン出力
--   ・CLOCK_50(50MHz)単一クロックドメイン。
--     25MHzのピクセルクロックは「クロックイネーブル(pix_en)」で生成
--     （派生クロックを使わずタイミングクロージャを堅牢にする）。
--   ・VGAは4bit/chの抵抗ラダーDAC（VGA_R/G/B[3:0]）+ HS/VS。
--   ・テストパターン = 8本の縦カラーバー
--     （白 黄 シアン 緑 マゼンタ 赤 青 黒）。
--     RGB各チャネルの配線正否が一目で分かる。
-- ============================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity vga1 is
    port (
        CLOCK_50 : in  std_logic;
        VGA_R    : out std_logic_vector(3 downto 0);
        VGA_G    : out std_logic_vector(3 downto 0);
        VGA_B    : out std_logic_vector(3 downto 0);
        VGA_HS   : out std_logic;
        VGA_VS   : out std_logic
    );
end vga1;

architecture RTL of vga1 is

    -- 640x480@60Hz 標準タイミング（ピクセルクロック25MHz）
    constant H_VISIBLE : integer := 640;
    constant H_FRONT   : integer := 16;
    constant H_SYNC    : integer := 96;
    constant H_BACK    : integer := 48;
    constant H_TOTAL   : integer := 800;   -- 640+16+96+48

    constant V_VISIBLE : integer := 480;
    constant V_FRONT   : integer := 10;
    constant V_SYNC    : integer := 2;
    constant V_BACK    : integer := 33;
    constant V_TOTAL   : integer := 525;   -- 480+10+2+33

    signal pix_en  : std_logic := '0';                       -- 25MHzイネーブル
    signal hcount  : integer range 0 to H_TOTAL-1 := 0;
    signal vcount  : integer range 0 to V_TOTAL-1 := 0;

begin

    -- すべての出力(HS/VS/RGB)を単一プロセス・単一クロックドメインで生成。
    -- 同一のhcount/vcountから同一レイテンシで叩き出すため、同期と色が
    -- 1ピクセルもずれない（パイプライン段差なし）。
    process(CLOCK_50)
        variable bar : integer range 0 to 9;
    begin
        if rising_edge(CLOCK_50) then

            -- 50MHz→25MHzイネーブル（1クロックおきに'1'）
            pix_en <= not pix_en;

            if pix_en = '1' then
                -- 水平/垂直カウンタ更新
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

                -- 水平同期（負論理: sync区間で'0'）
                if (hcount >= H_VISIBLE + H_FRONT) and
                   (hcount <  H_VISIBLE + H_FRONT + H_SYNC) then
                    VGA_HS <= '0';
                else
                    VGA_HS <= '1';
                end if;

                -- 垂直同期（負論理）
                if (vcount >= V_VISIBLE + V_FRONT) and
                   (vcount <  V_VISIBLE + V_FRONT + V_SYNC) then
                    VGA_VS <= '0';
                else
                    VGA_VS <= '1';
                end if;

                -- カラーバー（表示領域外は必ず黒＝ブランキング）
                if (hcount < H_VISIBLE) and (vcount < V_VISIBLE) then
                    bar := hcount / 80;   -- 80px×8本
                    case bar is
                        when 0      => VGA_R<="1111"; VGA_G<="1111"; VGA_B<="1111"; -- 白
                        when 1      => VGA_R<="1111"; VGA_G<="1111"; VGA_B<="0000"; -- 黄
                        when 2      => VGA_R<="0000"; VGA_G<="1111"; VGA_B<="1111"; -- シアン
                        when 3      => VGA_R<="0000"; VGA_G<="1111"; VGA_B<="0000"; -- 緑
                        when 4      => VGA_R<="1111"; VGA_G<="0000"; VGA_B<="1111"; -- マゼンタ
                        when 5      => VGA_R<="1111"; VGA_G<="0000"; VGA_B<="0000"; -- 赤
                        when 6      => VGA_R<="0000"; VGA_G<="0000"; VGA_B<="1111"; -- 青
                        when others => VGA_R<="0000"; VGA_G<="0000"; VGA_B<="0000"; -- 黒
                    end case;
                else
                    VGA_R<="0000"; VGA_G<="0000"; VGA_B<="0000"; -- ブランキングは黒必須
                end if;
            end if;
        end if;
    end process;

end RTL;
