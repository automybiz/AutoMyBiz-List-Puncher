# lp-format: 2
#
# LIST: VS Code Settings and Backup
# A machine-local runbook. Saves your VS Code settings to a file, then re-applies every preference
# you have deliberately dialled in. Nothing here touches the List Puncher code.
#
# Legend: [ ] to do   [v] already done   [x] REFUSED ON PURPOSE - a trap. Read the note before deciding you know better.
#
# The visible list title comes from the project pill, not from this text.
# Written against VS Code 1.142.0 on Windows. Paths are for this machine.

# ==========================================
# 1. WHERE THE SETTINGS ACTUALLY LIVE
# ==========================================
section: "Where the Settings Actually Live"
description: |
  Objectives: find the one file that holds every preference, so a backup becomes a copy instead of a
  guessing game. Two minutes, no admin rights.
tasks:
  - [ ] Find the user settings file
    notes: |
      %APPDATA%/Code/User/settings.json
      This machine: C:/Users/3DQuicky/AppData/Roaming/Code/User/settings.json
    - [ ] Open it with Ctrl+Shift+P, then "Preferences: Open User Settings (JSON)"
    - [ ] Confirm the title bar shows the AppData path, not a path inside the project
    - [x] Edit a file inside the project folder instead
      notes: "The project folder holds no VS Code preferences. A project-level file would be .vscode/settings.json, and this project has none. The real settings live in AppData."
  - [ ] Know what that file does NOT hold
    - [ ] Extensions, which are a separate list, handled in section 2
    - [ ] Keybindings, a separate keybindings.json beside it, present only if you changed a shortcut
    - [ ] Snippets, in the User/snippets folder
    - [x] Count the settings file as a complete backup
      notes: "A restored settings.json on a fresh machine gives you the preferences and none of the extensions. Restore both, or you will spend an hour wondering why the editor looks wrong."
  - [ ] Check whether a profile is in play
    - [ ] List %APPDATA%/Code/User/profiles
    - [ ] If a profile folder exists, its settings.json silently wins over the default one
    - [v] This machine has only "builtin", so the plain User settings.json is the one in charge

# ==========================================
# 2. SAVE A BACKUP NOW
# ==========================================
section: "Save a Backup Now"
description: |
  Objectives: get a dated, self-contained copy of your settings and your extension list somewhere
  outside the VS Code folder. Five minutes. Do this before changing a setting, not after.
tasks:
  - [ ] Run the script, which is the method to use from now on
    notes: |
      powershell -ExecutionPolicy Bypass -File "%USERPROFILE%/vscode-settings-backup/backup-vscode-settings.ps1"
      It writes a new timestamped folder under %USERPROFILE%/vscode-settings-backup holding
      settings.json, extensions.txt and manifest.txt. Re-running never overwrites an older copy.
    - [ ] Confirm the new folder is stamped with the current date and time
    - [ ] Confirm extensions.txt lists every installed extension, one id per line
    - [ ] Confirm manifest.txt records the VS Code version it captured
    - [v] Run once already, so there is a dated folder to fall back on today
  - [ ] Or copy the file by hand, which is one line and always works
    notes: |
      Copy-Item "$env:APPDATA/Code/User/settings.json" "$env:USERPROFILE/Desktop/vscode-settings.json"
    - [ ] Copy keybindings.json the same way, if it exists
    - [ ] Save the extension list with: code --list-extensions > extensions.txt
  - [ ] Or export a .code-profile, the official VS Code bundle
    notes: |
      Ctrl+Shift+P, then "Profiles: Export Profile", then pick a folder. It bundles settings,
      keybindings, snippets and the extension list into one file that imports on another machine.
    - [ ] Store the .code-profile somewhere that is not the machine you are backing up
    - [x] Rely on Settings Sync as the only backup
      notes: "Sync holds the latest state, not a history. A bad edit syncs to every machine within seconds and there is no version to go back to."
  - [ ] Keep the backups off the machine
    - [ ] Copy the newest dated folder to a USB stick or a cloud folder
    - [x] Leave every backup inside the same Windows profile
      notes: "A disk failure takes the settings and all their backups together. That is a copy, not a backup."

# ==========================================
# 3. APPEARANCE: THEME AND ZOOM
# ==========================================
section: "Appearance: Theme and Zoom"
description: |
  Objectives: set the two settings that decide how the whole workbench looks. Both are cosmetic and
  both are safe to change at any time.
tasks:
  - [ ] Set the colour theme
    notes: |
      "workbench.colorTheme": "Default High Contrast"
    - [ ] Open the picker with Ctrl+K, then Ctrl+T
    - [ ] Understand that settings.json stores the theme display name, not a slug
    - [v] Current value is Default High Contrast
    - [x] Hand-edit the theme name in settings.json
      notes: "A misspelled name silently falls back to the default theme and looks like the setting refused to save. Use the picker."
  - [ ] Set the zoom level
    notes: |
      "window.zoomLevel": 1
      One level is 120 percent. Zero is 100 percent, and negative values shrink.
    - [ ] Change it with Ctrl+= and Ctrl+-, which writes this same setting
    - [ ] Reset to 100 percent with Ctrl+0
    - [v] Current value is 1, so every window opens at 120 percent
    - [x] Zoom the editor right up and then wonder where the status bar went
      notes: "Zoom scales the entire workbench, not the text. A high level clips the status bar and the bottom of the terminal."

# ==========================================
# 4. TABS AND EDITORS
# ==========================================
section: "Tabs and Editors"
description: |
  Objectives: decide how many open files are drawn as tabs, and make sure a deleted file never leaves
  a dead tab behind. Two settings, both instant.
tasks:
  - [ ] Decide how many tab chips appear
    notes: |
      "workbench.editor.showTabs": "single"
      single = one chip, always the active file. multiple = one chip per open file. none = no chip.
    - [ ] Understand that single does not limit how many files are open
    - [ ] Understand that the Open Editors list ignores this setting completely
    - [v] This machine uses single, because it wastes the least space
    - [x] Switch to multiple to reduce the number of open files
      notes: "showTabs controls how many chips are drawn, not how many files are open. Multiple only adds a second, horizontal copy of the list you already have vertically."
  - [ ] Let a deleted file close its own tab
    notes: |
      "workbench.editor.closeOnFileDelete": true
    - [ ] Understand that a tab restored from a previous session can outlive its file
    - [ ] Clear those with right-click on the Open Editors header, then Close All, or Ctrl+K W
    - [ ] Know that pinned tabs never close on their own, which is the documented exception
    - [x] Add a hard cap on open editors to keep the list short
      notes: "workbench.editor.limit never blocks opening a file, it evicts the least recently used tab. That is only safe with workbench.editor.limit.excludeDirty set, so add both or neither."
  - [ ] Know which of the two lists you are looking at
    - [ ] The tab bar is the horizontal strip at the top of the editor area
    - [ ] Open Editors is a list view that enumerates every open editor, in every tab mode
    - [v] The vertical list on the right is Open Editors, not a tab bar

# ==========================================
# 5. FILES AND TERMINAL
# ==========================================
section: "Files and Terminal"
description: |
  Objectives: silence the two confirmation prompts that interrupt the way you actually work. Both
  remove a guard that was catching a specific mistake, so know which one before you turn it off.
tasks:
  - [ ] Skip the delete confirmation
    notes: |
      "explorer.confirmDelete": false
    - [ ] Understand that the Recycle Bin is still the destination, not a permanent delete
    - [ ] Understand that the prompt only ever caught one misclick
    - [v] Current value is false
    - [x] Turn it off and then delete a folder you still needed
      notes: "Nothing is gone for good, but restoring from the Recycle Bin is a manual trip you will be making in a hurry. Ctrl+Z in the Explorer does not bring it back."
  - [ ] Allow multi-line paste without a warning
    notes: |
      "terminal.integrated.enableMultiLinePasteWarning": "never"
      Acceptable values are auto, never and always.
    - [ ] Understand that the warning exists because a pasted newline can run a line you never read
    - [v] Current value is never
    - [x] Paste a script with a trailing newline into a shell you are not watching
      notes: "The warning is the only thing that shows a multi-line paste before it executes. With never, it is already running."

# ==========================================
# 6. GIT AND GITLENS
# ==========================================
section: "Git and GitLens"
description: |
  Objectives: make the commit loop one click and stop it asking twice. These settings are the most
  likely to surprise you, because two of them act on a remote the moment you press commit.
tasks:
  - [ ] Stop the sync confirmation
    notes: |
      "git.confirmSync": false
      VS Code syncs without asking first. The status bar still reports what happened.
    - [v] Current value is false
  - [ ] Commit without staging first
    notes: |
      "git.enableSmartCommit": true
      When nothing is staged, a commit takes every changed file.
    - [ ] Know the other two values: never and prompt
    - [x] Smart-commit a scratch file that was never meant to be tracked
      notes: "Smart commit is not selective. Put the scratch pattern in .gitignore first, or stage the files you want by hand."
  - [ ] Push after every commit
    notes: |
      "git.postCommitCommand": "push"
      Values are none, push and sync. Sync pulls as well.
    - [ ] Understand that this is the setting that publishes a commit immediately
    - [ ] Set it to none while you are experimenting
    - [x] Commit just to inspect a change locally and get it published by accident
      notes: "Not a bug and not a typo. With postCommitCommand set to push, commit means pushed. Check this before pressing commit on anything private."
  - [ ] Tame the GitLens side bar
    notes: |
      "gitlens.views.scm.grouped.views": { ... }
      A block of booleans showing or hiding each GitLens view inside the grouped Source Control panel.
    - [ ] Toggle a view by right-clicking its header, not by editing JSON
    - [v] Current state hides branches and the search-and-compare views
    - [x] Hand-edit that block to "back up" GitLens
      notes: "GitLens rewrites the block when the extension updates. It is safe to lose and pointless to hand-restore."

# ==========================================
# 7. LIVE SERVER
# ==========================================
section: "Live Server"
description: |
  Objectives: make Live Server open the browser you want instead of whatever it decides. One setting,
  and it only works when the command actually resolves on this machine.
tasks:
  - [ ] Point Live Server at Firefox
    notes: |
      "liveServer.settings.AdvanceCustomBrowserCmdLine": "firefox"
    - [ ] Understand that the value is a command line, not a browser keyword
    - [ ] Verify the name resolves with: where.exe firefox
    - [v] Current value is firefox
    - [x] Assume a bare browser name is a supported keyword
      notes: "The value is handed to the shell. A bare name only works because firefox is on PATH. If it ever opens nothing, paste the full path to firefox.exe instead."
  - [ ] Know what Live Server does to this project
    - [ ] It serves index.html and index.css exactly as they sit on disk
    - [ ] There is no build step, so a reload is the shipped state
    - [v] Opening the file directly works too, because the app has no bundler

# ==========================================
# 8. RESTORE ON A NEW MACHINE
# ==========================================
section: "Restore on a New Machine"
description: |
  Objectives: put the dialled-in settings back in the right order so the editor never sits half
  restored wondering why it looks wrong. About ten minutes on a fresh install.
tasks:
  - [ ] Install VS Code and the extensions first
    - [ ] Install the same build, x64 or arm64 to match the machine
    - [ ] Restore extensions with code --install-extension, once per line of extensions.txt
    - [ ] Or import the whole bundle with Ctrl+Shift+P, then "Profiles: Import Profile"
  - [ ] Restore the settings file last
    - [ ] CLOSE VS Code first, or it rewrites the copy when it exits
    - [ ] Copy settings.json into %APPDATA%/Code/User/settings.json
    - [ ] Reopen and check the theme, the zoom and the tab mode in one look
    - [x] Copy settings.json while the window is still open
      notes: "VS Code holds settings in memory and writes the file on change. A copy made while the window is open can be overwritten a second later."
  - [ ] Restore the things that are deliberately not in the backup
    - [ ] Re-authenticate Supabase MCP through the MCP panel, do not copy a token file
    - [ ] Re-authenticate GitHub from the Accounts menu
    - [ ] Re-enter the Live Server browser path if Firefox is not on PATH
    - [x] Copy cline_mcp_settings.json across from the old machine
      notes: "It holds a live client_secret, an access_token and a refresh_token. It is a credential store, not a config file. A new machine does a fresh OAuth instead."

# ==========================================
# 9. TRAPS THAT BITE
# ==========================================
section: "Traps That Bite"
description: |
  Objectives: the mistakes that cost real time, in one place, so they are read once instead of
  rediscovered. Nothing here is theory; each one has already happened.
tasks:
  - [ ] Read these five before collecting a backup
    - [x] Back up onto the same disk
      notes: "A copy beside the original is not a backup. It has to live on another device: a USB stick, a cloud folder, another machine."
    - [x] Trust Settings Sync as history
      notes: "Sync propagates the latest state everywhere within seconds. A bad edit becomes every machine's bad edit and there is no version to return to."
    - [x] Expect the project folder to hold the user settings
      notes: "The settings are in AppData. Nothing inside this project folder can change them, and .vscode/settings.json could only ever add to them."
    - [x] Leak the MCP token file while collecting a backup
      notes: "cline_mcp_settings.json is a credential, not a preference. Keep it out of every backup, screenshot and chat log."
    - [x] Change a setting and assume it applied because it is in the file
      notes: "Three things override the User settings: a profile's settings.json, .vscode/settings.json in the open folder, and a .code-workspace file. Check all three before debugging a setting that looks ignored."

# ==========================================
# HOW TO WORK THIS LIST QUICKLY
# ==========================================
# Every group of sub-tasks sits under a parent on purpose.
# When you have finished a whole group, use YesAll on the parent and the whole branch turns green in one click.
# Use NoAll only on a trap you have read and consciously rejected, so the reasoning stays in the list.
