@echo off
del /s *.bak
del /s *.orig
del /s *.rej
del /s *~
rmdir /s /q db
rmdir /s /q incremental_db
rmdir /s /q output_files
rmdir /s /q simulation
rmdir /s /q greybox_tmp
rmdir /s /q hc_output
rmdir /s /q .qsys_edit
rmdir /s /q hps_isw_handoff
rmdir /s /q sys\.qsys_edit
rmdir /s /q sys\vip
rmdir /s /q system
cd sys
for /d %%i in (*_sim) do rmdir /s /q "%%~nxi"
cd ..
for /d %%i in (*_sim) do rmdir /s /q "%%~nxi"
del build_id.v
del c5_pin_model_dump.txt
del PLLJ_PLLSPE_INFO.txt
del /s *.qws
del /s *.ppf
del /s *.ddb
del /s *.csv
del /s *.cmp
del /s *.sip
del /s *.spd
del /s *.bsf
del /s *.f
del /s *.sopcinfo
del /s *.xml
del *.cdf
del *.rpt
del /s new_rtl_netlist
del /s old_rtl_netlist
pause
