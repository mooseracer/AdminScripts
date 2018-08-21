powercfg.exe /CHANGE monitor-timeout-ac 120
powercfg.exe /CHANGE monitor-timeout-dc 30
powercfg.exe /CHANGE standby-timeout-ac 0
powercfg.exe /CHANGE standby-timeout-dc 30
powercfg.exe /HIBERNATE OFF
powercfg.exe -setdcvalueindex SCHEME_CURRENT SUB_BATTERY BATACTIONCRIT 3
powercfg.exe -setacvalueindex SCHEME_CURRENT SUB_BATTERY BATACTIONCRIT 0