# EnhancedPlotter
This script will generate plots according to the settings you specify in the #VARIABLES section. It will monitor disk, cpu and memory resources and automatically create new plots when enough free space and performance headroom are available.

If this is a new plotting machine and you haven't imported your certificates yet, share the "C:\Users\USERNAME\.chia\mainnet\config\ssl\ca" folder on your main node computer, then run these commands on your plotter(s) to sync them to the same keys and wallet target as your main node


cd "~\appdata\local\chia-blockchain\app-*\resources\app.asar.unpacked\daemon"
.\chia.exe stop all -d
.\chia init -c \\[MAIN_COMPUTER]\ca
.\chia configure --set-farmer-peer [MAIN_NODE_IP]:8447


Once you are sure you have your certificates imported so your keys are synced with your main node, then fill out the VARIABLES section of the EnhancedPlotter.ps1 script and run it.
