create_clock -name CLOCK_50 -period 20.000 [get_ports {CLOCK_50}]
derive_clock_uncertainty
set_false_path -from [get_ports {KEY[*] SW[*]}] -to *
set_false_path -from * -to [get_ports {VGA_R[*] VGA_G[*] VGA_B[*] VGA_HS VGA_VS HEX0[*] HEX1[*] HEX2[*] HEX3[*] HEX4[*] HEX5[*]}]
