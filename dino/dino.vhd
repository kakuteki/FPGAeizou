-- ============================================================
-- dino : DE0-CV VGA T-Rex Runner クローン
--   ・キャラ(56x72,4フレーム透過スプライト, sprite.mif)が固定x=80で走り、
--     KEY0でジャンプして右から来るサボテンを避ける。衝突でゲームオーバー。
--   ・白背景/地面ライン/サボテン(矩形)を race-the-beam 合成。
--   ・スプライトROM読出レイテンシ1を含め全出力をstage-2に揃える。
--   ・ゲーム更新は毎フレーム(vblank先頭=tick)。スコアはHEX0-3。
--   操作: KEY0 = ジャンプ / スタート / リスタート
-- ============================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dino is
    port (
        CLOCK_50 : in  std_logic;
        KEY      : in  std_logic_vector(3 downto 0);
        SW       : in  std_logic_vector(9 downto 0);
        VGA_R    : out std_logic_vector(3 downto 0);
        VGA_G    : out std_logic_vector(3 downto 0);
        VGA_B    : out std_logic_vector(3 downto 0);
        VGA_HS   : out std_logic;
        VGA_VS   : out std_logic;
        HEX0     : out std_logic_vector(6 downto 0);
        HEX1     : out std_logic_vector(6 downto 0);
        HEX2     : out std_logic_vector(6 downto 0);
        HEX3     : out std_logic_vector(6 downto 0);
        HEX4     : out std_logic_vector(6 downto 0);
        HEX5     : out std_logic_vector(6 downto 0)
    );
end dino;

architecture RTL of dino is

    -- VGA 640x480@60Hz
    constant H_VISIBLE : integer := 640;
    constant H_FRONT   : integer := 16;
    constant H_SYNC    : integer := 96;
    constant H_TOTAL   : integer := 800;
    constant V_VISIBLE : integer := 480;
    constant V_FRONT   : integer := 10;
    constant V_SYNC    : integer := 2;
    constant V_TOTAL   : integer := 525;

    -- スプライト
    constant DW : integer := 56;
    constant DH : integer := 72;
    constant NFR : integer := 4;
    constant SPR_DEPTH : integer := NFR*DW*DH;   -- 16128

    -- ゲーム配置
    constant DINO_X   : integer := 80;
    constant GROUND_Y : integer := 400;          -- 地面ライン上端=キャラ足元
    constant OW       : integer := 24;           -- サボテン幅
    constant JUMP_V   : integer := 13;
    constant GRAV     : integer := 1;
    -- 当たり判定(スプライトより内側)
    constant HITX0 : integer := DINO_X + 12;     -- 92
    constant HITX1 : integer := DINO_X + 44;     -- 124

    -- 色(4bit/ch)
    constant C_WHITE  : std_logic_vector(11 downto 0) := x"FFF";
    constant C_GROUND : std_logic_vector(11 downto 0) := x"333";
    constant C_CACTUS : std_logic_vector(11 downto 0) := x"262";

    -- スプライトROM (sprite.mif: 13bit = opaque|R4|G4|B4)
    type rom_t is array (0 to SPR_DEPTH-1) of std_logic_vector(12 downto 0);
    signal rom : rom_t;
    attribute ram_init_file : string;
    attribute ram_init_file of rom : signal is "sprite.mif";
    attribute ramstyle : string;
    attribute ramstyle of rom : signal is "M10K";

    type state_t is (READY, RUN, OVER);
    signal state : state_t := READY;

    signal pix_en : std_logic := '0';
    signal hcount : integer range 0 to H_TOTAL-1 := 0;
    signal vcount : integer range 0 to V_TOTAL-1 := 0;

    -- ゲーム状態
    signal dino_y    : integer range 0 to 255 := 0;     -- 地面からの高さ
    signal dino_vy   : integer range -64 to 64 := 0;
    signal on_ground : std_logic := '1';
    signal dino_top  : integer range 0 to 479 := GROUND_Y-DH;
    signal anim_frame: integer range 0 to 3 := 0;
    signal anim_cnt  : integer range 0 to 15 := 0;
    signal score     : integer range 0 to 9999 := 0;
    signal score_cnt : integer range 0 to 15 := 0;
    signal speed     : integer range 1 to 12 := 4;
    signal ox0, ox1  : integer range -64 to 4095 := 700;  -- 障害物X(リスポーン式の最大値を余裕で包含)
    signal oh0, oh1  : integer range 16 to 64 := 32;
    signal lfsr      : std_logic_vector(15 downto 0) := x"ACE1";
    signal key_prev  : std_logic := '1';

    -- stage-1 レジスタ(スプライトROM読出と同段)
    signal spr_q  : std_logic_vector(12 downto 0) := (others=>'0');
    signal hs1, vs1, von1, sin1, obs1, grd1 : std_logic := '0';

    function seg7(v : integer) return std_logic_vector is
    begin
        case v is
            when 0=>return "1000000"; when 1=>return "1111001";
            when 2=>return "0100100"; when 3=>return "0110000";
            when 4=>return "0011001"; when 5=>return "0010010";
            when 6=>return "0000010"; when 7=>return "1111000";
            when 8=>return "0000000"; when 9=>return "0010000";
            when others=>return "1111111";
        end case;
    end function;

begin

    -- 7セグ: スコア4桁(HEX0=1の位 .. HEX3=1000の位)、HEX4/5は消灯
    HEX0 <= seg7(score mod 10);
    HEX1 <= seg7((score/10) mod 10);
    HEX2 <= seg7((score/100) mod 10);
    HEX3 <= seg7((score/1000) mod 10);
    HEX4 <= "1111111";
    HEX5 <= "1111111";

    process(CLOCK_50)
        variable hs_c, vs_c, von_c, sin_c, obs_c, grd_c : std_logic;
        variable lx, ly, addr : integer range 0 to SPR_DEPTH-1;
        variable v, ny, fy, maxox, g, hgt : integer;
        variable key_press : std_logic;
    begin
        if rising_edge(CLOCK_50) then
            pix_en <= not pix_en;
            lfsr <= lfsr(14 downto 0) & (lfsr(15) xor lfsr(13) xor lfsr(12) xor lfsr(10));

            if pix_en = '1' then
                ---------------------------------------------------------
                -- カウンタ
                ---------------------------------------------------------
                if hcount = H_TOTAL-1 then
                    hcount <= 0;
                    if vcount = V_TOTAL-1 then vcount <= 0; else vcount <= vcount + 1; end if;
                else
                    hcount <= hcount + 1;
                end if;

                ---------------------------------------------------------
                -- 描画 stage-0 (現hcount/vcountから各レイヤを判定)
                ---------------------------------------------------------
                if (hcount >= H_VISIBLE+H_FRONT) and (hcount < H_VISIBLE+H_FRONT+H_SYNC) then hs_c:='0'; else hs_c:='1'; end if;
                if (vcount >= V_VISIBLE+V_FRONT) and (vcount < V_VISIBLE+V_FRONT+V_SYNC) then vs_c:='0'; else vs_c:='1'; end if;
                if (hcount < H_VISIBLE) and (vcount < V_VISIBLE) then von_c:='1'; else von_c:='0'; end if;

                -- スプライト領域?
                addr := 0; sin_c := '0';
                if von_c='1' and hcount>=DINO_X and hcount<DINO_X+DW
                            and vcount>=dino_top and vcount<dino_top+DH then
                    lx := hcount - DINO_X;
                    ly := vcount - dino_top;
                    addr := anim_frame*(DW*DH) + ly*DW + lx;
                    sin_c := '1';
                end if;

                -- サボテン?(2本, 地面に底)
                obs_c := '0';
                if von_c='1' then
                    if (hcount>=ox0 and hcount<ox0+OW and vcount>=GROUND_Y-oh0 and vcount<GROUND_Y) or
                       (hcount>=ox1 and hcount<ox1+OW and vcount>=GROUND_Y-oh1 and vcount<GROUND_Y) then
                        obs_c := '1';
                    end if;
                end if;

                -- 地面ライン?
                if von_c='1' and vcount>=GROUND_Y and vcount<GROUND_Y+3 then grd_c:='1'; else grd_c:='0'; end if;

                ---------------------------------------------------------
                -- stage-1: スプライトROM読出 + 各判定を同段で保持
                ---------------------------------------------------------
                spr_q <= rom(addr);
                hs1<=hs_c; vs1<=vs_c; von1<=von_c; sin1<=sin_c; obs1<=obs_c; grd1<=grd_c;

                ---------------------------------------------------------
                -- stage-2: 合成して出力(優先 キャラ>サボテン>地面>白)
                ---------------------------------------------------------
                VGA_HS <= hs1; VGA_VS <= vs1;
                if von1='1' then
                    if sin1='1' and spr_q(12)='1' then
                        VGA_R<=spr_q(11 downto 8); VGA_G<=spr_q(7 downto 4); VGA_B<=spr_q(3 downto 0);
                    elsif obs1='1' then
                        VGA_R<=C_CACTUS(11 downto 8); VGA_G<=C_CACTUS(7 downto 4); VGA_B<=C_CACTUS(3 downto 0);
                    elsif grd1='1' then
                        VGA_R<=C_GROUND(11 downto 8); VGA_G<=C_GROUND(7 downto 4); VGA_B<=C_GROUND(3 downto 0);
                    else
                        VGA_R<=C_WHITE(11 downto 8); VGA_G<=C_WHITE(7 downto 4); VGA_B<=C_WHITE(3 downto 0);
                    end if;
                else
                    VGA_R<="0000"; VGA_G<="0000"; VGA_B<="0000";
                end if;

                ---------------------------------------------------------
                -- ゲーム更新: フレーム先頭(vblank)で1回 = 60Hzティック
                ---------------------------------------------------------
                if hcount=0 and vcount=V_VISIBLE then
                    key_press := '0';
                    if KEY(0)='0' and key_prev='1' then key_press := '1'; end if;
                    key_prev <= KEY(0);

                    g   := 220 + to_integer(unsigned(lfsr(7 downto 0)));        -- 220..475
                    hgt := 28  + to_integer(unsigned(lfsr(11 downto 10)))*8;    -- 28,36,44,52

                    case state is
                    when READY =>
                        dino_y<=0; dino_vy<=0; on_ground<='1'; dino_top<=GROUND_Y-DH;
                        anim_frame<=0; ox0<=700; ox1<=700+300;
                        if key_press='1' then
                            state<=RUN; score<=0; score_cnt<=0; speed<=4;
                            ox0<=640; ox1<=640+300; oh0<=36; oh1<=44;
                        end if;

                    when RUN =>
                        -- ジャンプ物理
                        if key_press='1' and on_ground='1' then v:=JUMP_V; else v:=dino_vy; end if;
                        ny := dino_y + v;
                        if ny <= 0 then fy:=0; dino_vy<=0; on_ground<='1';
                        else fy:=ny; dino_vy<=v-GRAV; on_ground<='0'; end if;
                        dino_y  <= fy;
                        dino_top<= GROUND_Y-DH-fy;

                        -- 走りアニメ(接地時のみ)
                        if on_ground='1' then
                            if anim_cnt>=4 then anim_cnt<=0;
                                if anim_frame=3 then anim_frame<=0; else anim_frame<=anim_frame+1; end if;
                            else anim_cnt<=anim_cnt+1; end if;
                        else anim_frame<=0; anim_cnt<=0; end if;

                        -- 障害物スクロール&リスポーン(待ち行列で間隔保証)
                        maxox := ox0; if ox1>maxox then maxox:=ox1; end if;
                        if ox0 - speed < -OW then ox0<=maxox+g; oh0<=hgt;
                        else ox0<=ox0-speed; end if;
                        if ox1 - speed < -OW then ox1<=maxox+g+260; oh1<=hgt;
                        else ox1<=ox1-speed; end if;

                        -- スコア&加速
                        if score_cnt>=5 then score_cnt<=0;
                            if score<9999 then score<=score+1; end if;
                        else score_cnt<=score_cnt+1; end if;
                        if    score>=800 then speed<=9;
                        elsif score>=400 then speed<=7;
                        elsif score>=150 then speed<=6;
                        else speed<=4; end if;

                        -- 衝突(x重なり かつ ジャンプ高さ不足)
                        if (HITX0 < ox0+OW and ox0 < HITX1 and dino_y < oh0) or
                           (HITX0 < ox1+OW and ox1 < HITX1 and dino_y < oh1) then
                            state<=OVER;
                        end if;

                    when OVER =>
                        if key_press='1' then state<=READY; end if;
                    end case;
                end if;
            end if;
        end if;
    end process;

end RTL;
