CryptoBlocker - uses the Windows Server FSRM feature to blacklist file naming patterns.
Usage: run _update, verify the results, then run _deploy.

CryptoBlocker_update.ps1 - downloads a new blacklist from the web, writes it to CryptoBlocker_extensions.txt. Excludes anything you've added to CryptoBlocker_whitelist.txt.
CryptoBlocker_deploy.ps1 - queries PRTG for File & Print servers, then remotes to each and executes CryptoBlocker_install.ps1
CrytoBlocker_install.ps1 - runs locally on the File & Print server, sets up FSRM to use the blacklist as a series of filescreens
CryptoBlocker.ps1 - the script executed by FSRM when the filescreen is triggered; writes to the event log which is monitored by PRTG

