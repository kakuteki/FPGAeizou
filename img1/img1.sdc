# 50MHz 入力クロック制約
create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]
derive_clock_uncertainty

# VGA出力はモニタ側で非同期サンプルのためタイミング解析対象外
set_false_path -from * -to [get_ports {VGA_R[*] VGA_G[*] VGA_B[*] VGA_HS VGA_VS}]
