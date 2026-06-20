-- ============================================================
-- xstg : DE0-CV VGA 縦スクロール・シューティング(XEVIOUS“風”の
--        ゲームシステムをオリジナル資産で実装)
--   ・縦スクロール地形(手続き生成)
--   ・自機: KEY3=左 KEY2=右 / SW1=上 SW0=下
--   ・2系統武器: KEY1=ザッパー(前方ショット, 空中敵用)
--                KEY0=ブラスター(レティクル位置に地上ボム, 地上敵用)
--   ・空中敵3 / 地上ターゲット3(スクロール連動) / 残機3 / スコア(HEX)
--   ・描画: 多オブジェクトを優先度で1つ選び単一スプライトROM読出、
--           img1/dinoと同じく全出力をstage-2に揃える。
-- ============================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity xstg is
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
end xstg;

architecture RTL of xstg is

    -- VGA 640x480@60Hz
    constant H_VISIBLE : integer := 640; constant H_FRONT : integer := 16;
    constant H_SYNC : integer := 96;     constant H_TOTAL : integer := 800;
    constant V_VISIBLE : integer := 480; constant V_FRONT : integer := 10;
    constant V_SYNC : integer := 2;      constant V_TOTAL : integer := 525;

    -- スプライトROM配置
    constant BASE_PLAYER : integer := 0;    constant PW : integer := 28; constant PH : integer := 28;
    constant BASE_ENEMY  : integer := 784;  constant EW : integer := 24; constant EH : integer := 24;
    constant BASE_EXPL   : integer := 1360; constant XW : integer := 20; constant XH : integer := 20;
    constant SPR_DEPTH   : integer := 1760;

    constant PSPD : integer := 3;        -- 自機速度
    constant ZSPD : integer := 10;       -- ザッパー弾速
    constant ESPD : integer := 2;        -- 敵降下速度
    constant SCRSPD : integer := 2;      -- スクロール速度
    constant RET_OFF : integer := 96;    -- レティクル前方距離

    type rom_t is array (0 to SPR_DEPTH-1) of std_logic_vector(12 downto 0);
    signal rom : rom_t;
    attribute ram_init_file : string;
    attribute ram_init_file of rom : signal is "sprite.mif";
    attribute ramstyle : string;
    attribute ramstyle of rom : signal is "M10K";

    type state_t is (READY, PLAY, OVER);
    signal state : state_t := READY;

    signal pix_en : std_logic := '0';
    signal hcount : integer range 0 to H_TOTAL-1 := 0;
    signal vcount : integer range 0 to V_TOTAL-1 := 0;

    -- 自機
    signal px : integer range 0 to 639 := 306;
    signal py : integer range 0 to 479 := 420;
    -- スクロール
    signal scroll : integer range 0 to 2047 := 0;
    -- ザッパー弾(2)
    type i2 is array(0 to 1) of integer range -64 to 700;
    type s2 is array(0 to 1) of std_logic;
    signal zx, zy : i2 := (others => 0);
    signal zact   : s2 := (others => '0');
    signal zcool  : integer range 0 to 31 := 0;
    -- 空中敵(3)
    type i3 is array(0 to 2) of integer range -64 to 700;
    type d3 is array(0 to 2) of integer range -8 to 8;
    type s3 is array(0 to 2) of std_logic;
    signal ex, ey : i3 := (others => 0);
    signal edir   : d3 := (others => 2);
    signal eact   : s3 := (others => '0');
    -- 地上ターゲット(3)
    signal tx : i3 := (120, 360, 520);
    signal ty : i3 := (120, 280, 440);
    signal tact   : s3 := (others => '1');
    -- 爆発
    signal expl_x : integer range 0 to 639 := 0;
    signal expl_y : integer range 0 to 479 := 0;
    signal expl_t : integer range 0 to 31 := 0;
    -- スコア/残機
    signal score : integer range 0 to 9999 := 0;
    signal lives : integer range 0 to 3 := 3;
    signal invuln: integer range 0 to 127 := 0;
    -- 乱数 / キーエッジ
    signal lfsr : std_logic_vector(15 downto 0) := x"1234";
    signal k0p, k1p : std_logic := '1';

    -- stage-1
    signal spr_q : std_logic_vector(12 downto 0) := (others=>'0');
    signal hs1, vs1, von1, scov1 : std_logic := '0';
    signal shp1 : std_logic_vector(11 downto 0) := (others=>'0');

    function seg7(v:integer) return std_logic_vector is begin
        case v is
            when 0=>return "1000000"; when 1=>return "1111001"; when 2=>return "0100100";
            when 3=>return "0110000"; when 4=>return "0011001"; when 5=>return "0010010";
            when 6=>return "0000010"; when 7=>return "1111000"; when 8=>return "0000000";
            when 9=>return "0010000"; when others=>return "1111111";
        end case;
    end function;

    function terrain(x:integer; wy:integer) return std_logic_vector is
        variable sel:integer;
    begin
        sel := ((x/32)*7 + (wy/32)*13) mod 4;
        case sel is
            when 0 => return x"262";
            when 1 => return x"383";
            when 2 => return x"253";
            when others => return x"374";
        end case;
    end function;

begin
    HEX0 <= seg7(score mod 10);
    HEX1 <= seg7((score/10) mod 10);
    HEX2 <= seg7((score/100) mod 10);
    HEX3 <= seg7((score/1000) mod 10);
    HEX4 <= seg7(lives);
    HEX5 <= "1111111";

    process(CLOCK_50)
        variable hs_c, vs_c, von_c, scov : std_logic;
        variable saddr, lx, ly, wy, rcx, rcy : integer;
        variable shp : std_logic_vector(11 downto 0);
        variable k0e, k1e, spawned : std_logic;
        variable nx, ny : integer;
    begin
        if rising_edge(CLOCK_50) then
            pix_en <= not pix_en;
            lfsr <= lfsr(14 downto 0) & (lfsr(15) xor lfsr(13) xor lfsr(12) xor lfsr(10));

            if pix_en = '1' then
                ---------------- カウンタ ----------------
                if hcount = H_TOTAL-1 then
                    hcount <= 0;
                    if vcount = V_TOTAL-1 then vcount <= 0; else vcount <= vcount + 1; end if;
                else hcount <= hcount + 1; end if;

                ---------------- 描画 stage-0 ----------------
                if (hcount>=H_VISIBLE+H_FRONT) and (hcount<H_VISIBLE+H_FRONT+H_SYNC) then hs_c:='0'; else hs_c:='1'; end if;
                if (vcount>=V_VISIBLE+V_FRONT) and (vcount<V_VISIBLE+V_FRONT+V_SYNC) then vs_c:='0'; else vs_c:='1'; end if;
                if (hcount<H_VISIBLE) and (vcount<V_VISIBLE) then von_c:='1'; else von_c:='0'; end if;

                rcx := px + PW/2;  rcy := py - RET_OFF;

                -- 形状レイヤ(背→前: 地形→ターゲット→レティクル→弾)
                wy := vcount + scroll;
                shp := terrain(hcount, wy);
                -- 地上ターゲット
                for i in 0 to 2 loop
                    if tact(i)='1' and hcount>=tx(i) and hcount<tx(i)+EW and vcount>=ty(i) and vcount<ty(i)+EH then
                        if hcount>=tx(i)+8 and hcount<tx(i)+16 and vcount>=ty(i)+8 and vcount<ty(i)+16 then
                            shp := x"E33";       -- コア(赤)
                        else shp := x"99A"; end if;  -- 基地(灰)
                    end if;
                end loop;
                -- レティクル(十字＋枠, 白)
                if von_c='1' then
                    if (vcount=rcy and hcount>=rcx-8 and hcount<=rcx+8) or
                       (hcount=rcx and vcount>=rcy-8 and vcount<=rcy+8) or
                       ((hcount=rcx-9 or hcount=rcx+9) and vcount>=rcy-9 and vcount<=rcy+9) or
                       ((vcount=rcy-9 or vcount=rcy+9) and hcount>=rcx-9 and hcount<=rcx+9) then
                        shp := x"FF0";
                    end if;
                end if;
                -- ザッパー弾(黄)
                for i in 0 to 1 loop
                    if zact(i)='1' and hcount>=zx(i) and hcount<zx(i)+4 and vcount>=zy(i) and vcount<zy(i)+10 then
                        shp := x"FE2";
                    end if;
                end loop;

                -- スプライト選択(優先: 爆発 > 自機 > 敵), 単一ROM読出
                scov := '0'; saddr := 0;
                for i in 0 to 2 loop
                    if eact(i)='1' and hcount>=ex(i) and hcount<ex(i)+EW and vcount>=ey(i) and vcount<ey(i)+EH then
                        lx := hcount-ex(i); ly := vcount-ey(i);
                        saddr := BASE_ENEMY + ly*EW + lx; scov := '1';
                    end if;
                end loop;
                if hcount>=px and hcount<px+PW and vcount>=py and vcount<py+PH then
                    lx := hcount-px; ly := vcount-py;
                    saddr := BASE_PLAYER + ly*PW + lx; scov := '1';
                end if;
                if expl_t>0 and hcount>=expl_x and hcount<expl_x+XW and vcount>=expl_y and vcount<expl_y+XH then
                    lx := hcount-expl_x; ly := vcount-expl_y;
                    saddr := BASE_EXPL + ly*XW + lx; scov := '1';
                end if;
                if saddr<0 then saddr:=0; elsif saddr>SPR_DEPTH-1 then saddr:=SPR_DEPTH-1; end if;

                ---------------- stage-1 ----------------
                spr_q <= rom(saddr);
                hs1<=hs_c; vs1<=vs_c; von1<=von_c; scov1<=scov; shp1<=shp;

                ---------------- stage-2 出力 ----------------
                VGA_HS<=hs1; VGA_VS<=vs1;
                if von1='1' then
                    if scov1='1' and spr_q(12)='1' then
                        VGA_R<=spr_q(11 downto 8); VGA_G<=spr_q(7 downto 4); VGA_B<=spr_q(3 downto 0);
                    else
                        VGA_R<=shp1(11 downto 8); VGA_G<=shp1(7 downto 4); VGA_B<=shp1(3 downto 0);
                    end if;
                else VGA_R<="0000"; VGA_G<="0000"; VGA_B<="0000"; end if;

                ---------------- ゲーム更新(vblank先頭=60Hz) ----------------
                if hcount=0 and vcount=V_VISIBLE then
                    k0e := '0'; k1e := '0';
                    if KEY(0)='0' and k0p='1' then k0e:='1'; end if;
                    if KEY(1)='0' and k1p='1' then k1e:='1'; end if;
                    k0p<=KEY(0); k1p<=KEY(1);

                    if scroll >= 2047-SCRSPD then scroll<=0; else scroll<=scroll+SCRSPD; end if;
                    if zcool>0 then zcool<=zcool-1; end if;
                    if invuln>0 then invuln<=invuln-1; end if;
                    if expl_t>0 then expl_t<=expl_t-1; end if;

                    -- 自機移動(KEY=押下'0', SW=ON'1')
                    nx := px; ny := py;
                    if KEY(3)='0' then nx:=px-PSPD; end if;
                    if KEY(2)='0' then nx:=px+PSPD; end if;
                    if SW(1)='1'  then ny:=py-PSPD; end if;
                    if SW(0)='1'  then ny:=py+PSPD; end if;
                    if nx<0 then nx:=0; elsif nx>639-PW then nx:=639-PW; end if;
                    if ny<240 then ny:=240; elsif ny>479-PH then ny:=479-PH; end if;
                    px<=nx; py<=ny;

                    case state is
                    when READY =>
                        px<=306; py<=420; lives<=3; score<=0;
                        for i in 0 to 2 loop eact(i)<='0'; end loop;
                        for i in 0 to 1 loop zact(i)<='0'; end loop;
                        if k1e='1' or k0e='1' then state<=PLAY; end if;

                    when PLAY =>
                        ---------- 地上ターゲット スクロール ----------
                        for i in 0 to 2 loop
                            if ty(i) > 479 then
                                ty(i) <= -EH; tx(i) <= 40 + (to_integer(unsigned(lfsr(8 downto 0))) mod 540); tact(i)<='1';
                            else ty(i) <= ty(i) + SCRSPD; end if;
                        end loop;

                        ---------- ザッパー発射 ----------
                        if KEY(1)='0' and zcool=0 then
                            if zact(0)='0' then zx(0)<=px+PW/2-2; zy(0)<=py-10; zact(0)<='1'; zcool<=7;
                            elsif zact(1)='0' then zx(1)<=px+PW/2-2; zy(1)<=py-10; zact(1)<='1'; zcool<=7; end if;
                        end if;
                        -- 弾移動
                        for i in 0 to 1 loop
                            if zact(i)='1' then
                                if zy(i) < -10 then zact(i)<='0'; else zy(i)<=zy(i)-ZSPD; end if;
                            end if;
                        end loop;

                        ---------- ブラスター(地上ボム) ----------
                        if k0e='1' and expl_t=0 then
                            expl_x<=rcx-XW/2; expl_y<=rcy-XH/2; expl_t<=20;
                            for i in 0 to 2 loop
                                if tact(i)='1' and (tx(i)+EW/2 - rcx < 18) and (rcx - (tx(i)+EW/2) < 18)
                                              and (ty(i)+EH/2 - rcy < 18) and (rcy - (ty(i)+EH/2) < 18) then
                                    tact(i)<='0';
                                    if score<9900 then score<=score+100; end if;
                                end if;
                            end loop;
                        end if;

                        ---------- 敵: スポーン/移動/衝突 ----------
                        -- スポーンは1tickにつき最大1機(同一lfsrでの重なり防止)
                        spawned := '0';
                        for i in 0 to 2 loop
                            if eact(i)='0' then
                                if spawned='0' and lfsr(3 downto 0) = "0000" then
                                    ex(i) <= 30 + (to_integer(unsigned(lfsr(12 downto 4))) mod 560);
                                    ey(i) <= -EH;
                                    if lfsr(14)='1' then edir(i)<=2; else edir(i)<=-2; end if;
                                    eact(i) <= '1';
                                    spawned := '1';
                                end if;
                            else
                                ny := ey(i) + ESPD;
                                nx := ex(i) + edir(i);
                                if nx < 0 then nx:=0; edir(i)<=2;
                                elsif nx > 639-EW then nx:=639-EW; edir(i)<=-2; end if;
                                if ny > 479 then eact(i)<='0'; else ey(i)<=ny; ex(i)<=nx; end if;
                            end if;
                        end loop;
                        -- 敵×弾
                        for i in 0 to 2 loop
                            for j in 0 to 1 loop
                                if eact(i)='1' and zact(j)='1'
                                   and ex(i)<zx(j)+4 and zx(j)<ex(i)+EW
                                   and ey(i)<zy(j)+10 and zy(j)<ey(i)+EH then
                                    eact(i)<='0'; zact(j)<='0';
                                    if score<9980 then score<=score+10; end if;
                                end if;
                            end loop;
                        end loop;
                        -- 敵×自機
                        if invuln=0 then
                            for i in 0 to 2 loop
                                if eact(i)='1'
                                   and px<ex(i)+EW and ex(i)<px+PW
                                   and py<ey(i)+EH and ey(i)<py+PH then
                                    eact(i)<='0'; invuln<=90;
                                    if lives>0 then lives<=lives-1; end if;
                                end if;
                            end loop;
                        end if;
                        if lives=0 then state<=OVER; end if;

                    when OVER =>
                        for i in 0 to 2 loop eact(i)<='0'; end loop;
                        if k1e='1' or k0e='1' then state<=READY; end if;
                    end case;
                end if;
            end if;
        end if;
    end process;

end RTL;
