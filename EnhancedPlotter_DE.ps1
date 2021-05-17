#If this is a new plotting machine and you haven't imported your certificates yet, share the "C:\Users\USERNAME\.chia\mainnet\config\ssl\ca" folder on your main node computer, then run these commands on your plotter(s) to sync them to the same keys and wallet target as your main node
###################################################################################
# cd "~\appdata\local\chia-blockchain\app-*\resources\app.asar.unpacked\daemon"    #
# .\chia.exe stop all -d                                                           #
# .\chia init -c \\[MAIN_COMPUTER]\ca                                              #
# .\chia configure --set-farmer-peer [MAIN_NODE_IP]:8447                           #
###################################################################################

<#
.SYNOPSIS
    The objective of this script is to maximize plotting throughput, with minimal human interaction.
.DESCRIPTION
    DE - German Language version. This script will generate plots according to the settings you specify in the #VARIABLES section. It will monitor disk, cpu and memory resources and automatically create new plots when enough free space and performance headroom are available.
.INPUTS
    null
.OUTPUTS
    void
.NOTES
    Version: 1.5.2
    Author:  /u/epidemic0110
    Email: enhancedchia [@] gmail.com (Send me feedback, please! I'm dyin here!)
    Donation: xch18n2p6ml9sud595kws9m3x38ujh4dgt60sdstk9cpzke9f0qtzrzq079jfg (Hah! Why would anyone would donate their precious Chia XCH?!)
#>


#VARIABLES - Set these to match your environment.

#MANDATORY
$tempDrives = @("F:","T:") #Drives that you want to use for temp files
$plotDir = "\\SERVERNAME\SharedFolder" #Local or shared Destination directory you want plots to be sent to (for example, \\SERVERNAME\Plots or G:\Plots)
$newPlots = 30 #Total number of plots to produce

#OPTIONAL - Advanced settings
$logDir = "C:\temp\EnhancedPlotter"
$tempFolder = "\ChiaTemp" #Name of folder to be used/created on the temp drives for temp files. DO NOT INCLUDE DRIVE LETTER, this will result in an error!
$temp2Dir = $null #Full path to a directory to be used for staging the finished plot file before it is moved to the final $plotDir destination directory. If set, it uses the -tmp2_dir switch. If $null it does not stage the final files anywhere other than the source temp directory.
$tempPlotSize = 240 #Size in GiB that the temp files for one k32 plot take (Currently ~240GiB/260GB as of v1.1.3)
$threadsPerPlot = 2 #How many processor each plotting process should use. Feel free to experiment with higher numbers on high core systems, but general consesus is that there are diminishing returns above 2 threads
$checkDelaySeconds = 600 #Delay (in seconds) between checks for sufficient free resources to start a new plot; DON'T SET THIS TOO LOW OR YOU RISK OVER-FILLING A DISK. 300-900 seconds (5-15 minutes) seem to be good values
$lowDiskThreshold = .7 #A queue length of 1.0 or greater means a disk is saturated and cannot handle any more concurrent requests. Anything less than 1.0 theoretically means the disk isn't fully utilized, however it may not be ideal to target full saturation, especially on mechanical drives. A threshold in the range of .5-.8 is suggested, but tweak and let me know what you find best for overall throughput
$lowCpuThreshold = 80 #How low should the CPU utilization percent be before a new plot is allowed to be started if other resources are free; This will vary depending on core count and if this is a dedicated plotter or not. If it is doing nothing else and you have lots of cores, you might want to set this to a high value, like 85%. If it is running a full node or farmer, you might want to keep it a bit lower to prevent plotting from using all of the CPU
$lowMemThreshold = 512 #Don't start a new plot if it would make system free memory drop below this amount (MB). For example if your $memoryBuffer value is set to 4096MB per plot, and your current system free memory is less than 4096+$lowMemThreshold, it won't start a new plot
$memoryBuffer = 3390 #Amount of memory to limit each plotting process to. Default is 3390MiB but if you have lots of memory and CPU or disk I/O are your bottleneck, you can try increasing this number
$initialDelayMinutes = 20 #Stagger delay (in minutes) before the very first instance starts on each tempDrive after the first. May help distribute plotting load across phases better, but untested- not sure if helpful or harmful to overall throughput.
$discordLogging = $false #Set to $true to log to Discord with following webhook URL and username to shout @
$hookUrl = 'https://discord.com/api/webhooks/SAMPLE/URL' #Discord webhook URL for Discord logging (only mandatory if $discordLogging set to $true)
$targetUser = "" #Discord username to call out @ (optional)
###################################################################################

#FUNCTIONS
function Write-Discord {
    param (
        [parameter(Mandatory)]
        [string]$url,
        [string]$message,
        [string]$user
    )
    if ($discord -eq $true) {
        $content = "@$user`: $message"

        $payload = [PSCustomObject]@{ 
            content = $content
        }
        Invoke-RestMethod -Uri $hookUrl -Method Post -Body ($payload | ConvertTo-Json) -ContentType 'Application/Json'
    }
}

#HEALTH CHECKS
if (!(Get-CimInstance Win32_ComputerSystem).AutomaticManagedPagefile) { Write-Host "WARNING: Your system is not set to use an automatically managed page file. This can cause Chia to fail with `"Bad allocation`" errors." -ForegroundColor Red }

#INITIAL SETUP
if (!(Test-Path $plotDir)) { Write-Host "Plot directory does not exist, attempting to create."; New-Item -ItemType Directory -Force -Path $plotDir }
if (!(Test-Path $logDir)) { Write-Host "Log directory does not exist, attempting to create.";New-Item -ItemType Directory -Force -Path $logDir }
if (($temp2Dir -ne $null) -AND !(Test-Path $temp2Dir)) { Write-Host "Temp2 directory does not exist, attempting to create.";New-Item -ItemType Directory -Force -Path $temp2Dir }
foreach ($tempDrive in $tempDrives) { if (!(Test-Path $tempDrive$tempFolder)) { Write-Host "Temp directory $tempDrive$tempFolder does not exist, attempting to create."; New-Item -ItemType Directory -Force -Path $tempDrive$tempFolder } }
$plots = [hashtable[]]::new($newPlots)



#MAIN ROUTINE
cd "~\appdata\local\chia-blockchain\app-*\resources\app.asar.unpacked\daemon"

#Start plotting
for ($i = 0; $i -lt $newPlots){
    #Cycle through temp drives
    foreach ($tempDrive in $tempDrives) {
        #Sleep for initialDelay if this is our first run through each drive
        if (($i -lt $($tempDrives.Count)) -and ($i -ge 1)) {
            Write-Host "Sleeping for initial stagger delay of $initialDelayMinutes minutes."
            sleep $($initialDelayMinutes*60)
        }

        #Check for sufficient free memory
        Write-Host "Checking for sufficient free memory..."
        $freeMemory = (Get-Counter '\Arbeitsspeicher\Verfügbare MB').CounterSamples.CookedValue
        if ($freeMemory -gt $($lowMemThreshold + $memoryBuffer)) {
            Write-Host "Sufficient free memory of $freeMemory. Continuing..."

            #Check for sufficient free CPU using average of 3 samples over 3 seconds
            Write-Host "Checking for sufficient free CPU..."
            $CPUSample1 = (Get-Counter '\prozessor(_total)\prozessorzeit (%)').CounterSamples.CookedValue
            sleep 1
            $CPUSample2 = (Get-Counter '\prozessor(_total)\prozessorzeit (%)').CounterSamples.CookedValue
            sleep 1
            $CPUSample3 = (Get-Counter '\prozessor(_total)\prozessorzeit (%)').CounterSamples.CookedValue
            $CPUAvg = [math]::Round(($CPUSample1 + $CPUSample2 + $CPUSample3) / 3)
            if ($CPUAvg -lt $lowCpuThreshold) {
                Write-Host "Sufficient free CPU of $(100-$CPUAvg)%. Continuing..."

                #Calculate space reserved by existing plot processes
                $expandingPlots = 0
                $plots | Where-Object {$_.tempDrive -like $tempDrive} | foreach {
                    #If the plot log file exists, but it does not contain "phase 3", then consider the plot still growing
                    if ((Test-Path "$logDir`\$($_.logFile)") -AND !(Select-String -LiteralPath "$logDir`\$($_.logFile)" -Pattern "phase 3" -Quiet)) {
                        Write-Host "DEBUG: Hit $_.logFile doesn't say phase 3"
                        $expandingPlots++
                    }
                }
                Write-Host "$expandingPlots plots still expanding on $tempDrive"
                $reservedSpace = $expandingPlots * $tempPlotSize*1024*1024*1024
                Write-Host "$($reservedSpace/1024/1024/1024) GiB reserved for existing plot processes"
                #Check for sufficient space
                Write-Host "Checking $tempDrive for sufficient temp space..."
                $tempSpace = $(Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID like '$tempDrive'" | select FreeSpace)
                
                if ($tempSpace.FreeSpace -gt $($tempPlotSize*1024*1024*1024 + $reservedSpace)){
                    Write-Host "Free space on $tempDrive $([math]::Round($tempSpace.FreeSpace/1024/1024/1024)) GiB is large enough to hold new $tempPlotSize GiB plot + $($reservedSpace/1024/1024/1024) GiB running plotting processes. Continuing... "
                    #Check for sufficient disk IO
                    $tempQueue = [math]::Round((Get-Counter "\Physikalischer Datenträger(* $tempDrive)\Aktuelle Warteschlangenlänge").CounterSamples.CookedValue,3)
                    if ($tempQueue -lt $lowDiskThreshold) {
                        Write-Host "Disk queue length $tempQueue is below $lowDiskThreshold. Continuing..."

                        #Start plot
                        Write-Host "GO: Spinning off plot $($i) of $newPlots using $tempDrive in new process" -ForegroundColor Green
                        Write-Host "NEW POWERSHELL WINDOWS WILL CLOSE AUTOMATICALLY WHEN FINISHED. Do not close them unless you want to interrupt them." -ForegroundColor Green
                        $logFile = "Plot$($i)_$(Get-Date -Format dd-mm-yyyy-hh-mm).txt"
                        if ($temp2Dir -ne $null) { $proc = start-process powershell -ArgumentList ".\chia.exe plots create --size 32 --num 1 --num_threads $threadsPerPlot --tmp_dir `"$tempDrive$tempFolder`" --final_dir `"$plotDir`" --tmp2_dir $temp2Dir --buffer $memoryBuffer -x | Tee-Object -FilePath `"$logDir\$logFile`"" -PassThru }
                        else { $proc = start-process powershell -ArgumentList ".\chia.exe plots create --size 32 --num 1 --num_threads $threadsPerPlot --tmp_dir `"$tempDrive$tempFolder`" --final_dir `"$plotDir`" --buffer $memoryBuffer -x | Tee-Object -FilePath `"$logDir\$logFile`"" -PassThru }
                        #Capture plot info
                        $plots[$i] = @{procId=$proc.Id; tempDrive=$tempDrive; logFile=$logFile; phase=$null}
                        $i++
                        #Quit if we've reached desired plot count, otherwise wait delay and start over
                        if ($i -lt $newPlots) {
                            Write-Host "Waiting $checkDelaySeconds seconds before next check..."
                            sleep $($checkDelaySeconds)
                        } 
                        else { 
                            Write-Host "Reached desired plot count. Stopping."
                            Write-Discord -url $hookUrl -message "Reached desired plot count on $env:COMPUTERNAME. Stopping." -user $targetUser
                            Write-Host $plots.count
                            Read-Host "Press Enter to exit"
                            exit 
                        }
                    }
                    else { Write-Host "$tempDrive queue length is higher than $lowDiskThreshold. Waiting $checkDelaySeconds seconds..."; sleep $checkDelaySeconds }
                }
                else { Write-Host "$tempDrive has insufficient space. Only $([math]::Round($tempSpace.FreeSpace/1024/1024/1024))GiB remaining. Waiting $checkDelaySeconds seconds..."; sleep $checkDelaySeconds }
            }
            else { Write-Host "CPU average of $CPUAvg is not below low CPU threshold of $lowCpuThreshold. Waiting $checkDelaySeconds seconds..."; sleep $checkDelaySeconds }
        }
        else { Write-Host "Insufficient free memory for new plot plus $lowMemThreshold MB of headroom. Waiting $checkDelaySeconds seconds..."; sleep $checkDelaySeconds }
    }
}
