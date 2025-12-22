use framework "Foundation"
use scripting additions

on run argv
    set appName to "SaneVideo"
    if (count of argv) > 0 then
        set appName to item 1 of argv
    end if
    
    log "Starting permission monitor for: " & appName
    
    -- Loop for 60 seconds (monitor duration)
    repeat 60 times
        tell application "System Events"
            -- Access the CoreServicesUIAgent which hosts the TCC dialogs
            if exists process "UserNotificationCenter" then
                tell process "UserNotificationCenter"
                    if exists (window 1) then
                        set winName to name of window 1
                        if winName contains appName and winName contains "access" then
                            -- Click Allow
                            if exists button "Allow" of window 1 then
                                click button "Allow" of window 1
                                log "Clicked Allow on UserNotificationCenter"
                            end if
                        end if
                    end if
                end tell
            end if
            
            -- Also check for standard alerts in the app process itself (sometimes they present differently)
            -- or the specialized TCC daemon wrapper
            
            -- Check "CoreServicesUIAgent" (Historical host for some alerts)
            if exists process "CoreServicesUIAgent" then
                tell process "CoreServicesUIAgent"
                     if exists (window 1) then
                        set winText to ""
                        try
                            set winText to value of static text 1 of window 1
                        end try
                        
                        if winText contains appName then
                            if exists button "Allow" of window 1 then
                                click button "Allow" of window 1
                                log "Clicked Allow on CoreServicesUIAgent"
                            end if
                        end if
                     end if
                end tell
            end if
            
        end tell
        delay 1
    end repeat
end run
