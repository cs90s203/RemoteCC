import Foundation
import Citadel

enum MacDisplayExtenderError: LocalizedError {
    case sshConnectionFailed(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .sshConnectionFailed(let message):
            return "SSH 連線失敗：\(message)"
        case .commandFailed(let message):
            return "指令執行失敗：\(message)"
        }
    }
}

/// Triggers macOS's native "Extend to Apple Vision Pro" screen mirroring over SSH.
///
/// There's no public API for a visionOS app to invoke Mac Virtual Display directly, so this
/// connects over SSH (macOS "Remote Login") and drives Control Center's Screen Mirroring menu
/// via System Events/Accessibility — the same technique used by community AirPlay-automation
/// tools. Adapted from https://github.com/kconsiglio/auto-open-screen-mirroring, hardcoded to
/// "Apple Vision Pro" as the target device.
///
/// This is inherently fragile: it depends on Control Center's accessibility hierarchy, which
/// Apple has changed across macOS versions before and may change again.
enum MacDisplayExtender {
    static func extendDisplay(to mac: SavedMac, sshUsername: String, sshPassword: String) async throws {
        let settings = SSHClientSettings(
            host: mac.host,
            authenticationMethod: { .passwordBased(username: sshUsername, password: sshPassword) },
            hostKeyValidator: .acceptAnything()
        )

        let client: SSHClient
        do {
            client = try await SSHClient.connect(to: settings)
        } catch {
            throw MacDisplayExtenderError.sshConnectionFailed(error.localizedDescription)
        }

        // executeCommand's convenience wrapper discards whatever output it collected if the
        // command exits non-zero, which throws away exactly the osascript error text we need
        // to debug this. Stream manually so partial output survives a failure.
        var output = ""
        do {
            let command = "osascript <<'APPLESCRIPT_EOF'\n\(screenMirroringScript)\nAPPLESCRIPT_EOF"
            let stream = try await client.executeCommandStream(command)

            for try await chunk in stream {
                switch chunk {
                case .stdout(let buffer):
                    output += String(buffer: buffer)
                case .stderr(let buffer):
                    output += String(buffer: buffer)
                }
            }
            try? await client.close()
        } catch {
            try? await client.close()
            let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = trimmedOutput.isEmpty
                ? error.localizedDescription
                : "\(error.localizedDescription)\n\(trimmedOutput)"
            throw MacDisplayExtenderError.commandFailed(message)
        }
    }

    private static let screenMirroringScript = #"""
    use framework "Foundation"
    use scripting additions

    -- Neither a device's AXIdentifier nor its title actually contains its display name (e.g.
    -- "Apple Vision Pro") — confirmed by live inspection of the real menu contents. Apple's own
    -- devices (Vision Pro included) show up as "screen-mirroring-device-Sidecar:<UUID>", while
    -- third-party AirPlay receivers show up as "screen-mirroring-device-AirPlay:<MAC address>".
    -- Matching on "Sidecar" is what actually identifies the Vision Pro entry.
    set airPlayDevice to "Sidecar"

    -- Menu bar items are iterated one at a time with try/on error, rather than a "whose"
    -- clause across all of them, because several default items (Battery, Clock, etc.) don't
    -- expose an AXIdentifier at all — a "whose ... attribute AXIdentifier ..." filter throws
    -- as soon as it evaluates one of those, instead of just skipping it.
    on findMenuBarItem(matchString)
    	tell application "System Events"
    		tell its application process "ControlCenter"
    			set barItems to UI elements of menu bar 1
    			repeat with anItem in barItems
    				try
    					if value of attribute "AXIdentifier" of anItem contains matchString then
    						return anItem
    					end if
    				end try
    			end repeat
    		end tell
    	end tell
    	return missing value
    end findMenuBarItem

    tell application "System Events"
    	tell its application process "ControlCenter"
    		set osVersion to get system version of (system info)
    		set status to ""
    		set screenMirroringDropDownButton to findMenuBarItem("screen-mirroring") of me
    		if screenMirroringDropDownButton is not missing value then
    			click screenMirroringDropDownButton
    			delay 1
    			set window_ to title of its window as string
    		else
    			set controlCenter to findMenuBarItem("controlcenter") of me
    			if controlCenter is missing value then
    				return "COULD NOT FIND CONTROL CENTER MENU BAR ITEM"
    			end if
    			click controlCenter
    			delay 1
    			set window_ to title of its window as string
    			set status to controlCenterDropDown(osVersion, window_) of me as string
    		end if

    		if status is not "failed" then
    			getScreenMirroringDropDown(osVersion, airPlayDevice, window_) of me
    		end if
    	end tell
    end tell
    return

    on controlCenterDropDown(osVersion, window_)
    	tell application "System Events"
    		tell its application process "ControlCenter"
    			tell its window window_
    				try
    					if osVersion ≥ 13 then
    						set controlCenterElements to UI elements of group 1
    						set myattribute to "AXIdentifier"
    					else if osVersion < 13 and osVersion ≥ 12 then
    						set controlCenterElements to UI elements
    						set myattribute to "AXIdentifier"
    					else
    						set controlCenterElements to UI elements of group 1 of group 1
    						set myattribute to "AXTitle"
    					end if
    				on error
    					log "Error getting screen mirroring button"
    					return "failed"
    				end try
    				repeat with anItem in controlCenterElements
    					try
    						if exists attribute myattribute of anItem then
    							if value of attribute myattribute of anItem contains "screen-mirroring" or value of attribute myattribute of anItem contains "Screen Mirroring" then
    								-- AXPress (a normal click), not AXShowMenu (right-click-style
    								-- context menu) — this element supports both, and picking by
    								-- position rather than name previously triggered the wrong one.
    								perform action "AXPress" of anItem
    								exit repeat
    							end if
    						end if
    					on error
    						log "error clicking screen mirroring"
    						return "failed"
    					end try
    				end repeat
    				delay 1
    			end tell
    		end tell
    	end tell
    	return
    end controlCenterDropDown

    -- Confirmed by live inspection: after AXPress opens the Screen Mirroring panel, the
    -- window's top-level group is reused (not replaced) and its contents become 3 items —
    -- a header, a scroll area, and a preferences button. The device checkboxes are two
    -- levels below the scroll area (scroll area -> device-list group -> checkboxes), so
    -- this searches breadth-first up to 3 levels deep rather than assuming an exact fixed
    -- path, since that's the minimum that's actually been verified to work on this system.
    on getScreenMirroringDropDown(osVersion, airPlayDevice, window_)
    	tell application "System Events"
    		tell its application process "ControlCenter"
    			tell its window window_
    				try
    					set topGroup to item 1 of (UI elements)
    					set level1 to UI elements of topGroup
    					repeat with item1 in level1
    						try
    							set level2 to UI elements of item1
    							repeat with item2 in level2
    								try
    									if tryMatchAndClick(item2, airPlayDevice) of me then
    										return
    									end if
    								end try
    								try
    									set level3 to UI elements of item2
    									repeat with item3 in level3
    										try
    											if tryMatchAndClick(item3, airPlayDevice) of me then
    												return
    											end if
    										end try
    									end repeat
    								end try
    							end repeat
    						end try
    					end repeat
    				on error errMsg
    					log "getScreenMirroringDropDown error: " & errMsg
    				end try
    			end tell
    		end tell
    	end tell
    	return
    end getScreenMirroringDropDown

    on tryMatchAndClick(anItem, matchString)
    	tell application "System Events"
    		try
    			if value of attribute "AXIdentifier" of anItem contains matchString then
    				click anItem
    				return true
    			end if
    		end try
    	end tell
    	return false
    end tryMatchAndClick
    """#
}
