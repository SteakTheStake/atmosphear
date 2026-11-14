$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Speech
$speaker = New-Object System.Speech.Synthesis.SpeechSynthesizer
$speaker.Rate = -1
$speaker.Volume = 90
$audioPath = Join-Path $PSScriptRoot '..\assets\audio'
$prompts = [ordered]@{
    intro = 'Welcome to the listening chamber. The screen is now dark. Move with the left stick, or W A S D. Turn with the right stick, or the left and right arrow keys. Follow the repeating two note sound. Find the lever, and use the bottom face button, or E, to open the mechanism. Press the top face button, or H, to hear the controls. Take your time.'
    help = 'Left stick, or W A S D, to walk. Right stick, or left and right arrows, to turn. Bottom face button, or E, to touch the lever when you are close. Left face button, or Space, to tap and hear the room. Hold the left trigger, or Shift, to quiet the atmosphere. Follow the repeating two note sound. The floor becomes wood near the lever. Menu button, or Escape, pauses the game.'
    near = 'A metal handle is within reach. Press the bottom face button, or E.'
    success = 'The lever moves. The mechanism opens, and air flows into the chamber. You found it. This completes the prototype. You can keep exploring, or use the lever again to close it.'
    closed = 'The mechanism closes. The two note signal returns.'
    paused = 'Paused. Resume selected. Use the D pad up and down, or up and down arrow keys, to choose. Bottom face button, or Enter, selects. Menu button, or Escape, resumes.'
    resume = 'Resuming.'
    disconnect = 'Controller disconnected. The game is paused. Reconnect your controller and press the Menu button, or press Escape on the keyboard, to resume.'
    menu_resume = 'Resume.'
    menu_help = 'Repeat instructions.'
    menu_restart = 'Restart chamber.'
    menu_volume = 'Volume. Use the left stick, or the left and right arrows, to adjust.'
    restart_voice = 'Chamber restarted. Follow the repeating two note sound and find the lever.'
}
foreach ($entry in $prompts.GetEnumerator()) {
    $speaker.SetOutputToWaveFile([IO.Path]::GetFullPath((Join-Path $audioPath ($entry.Key + '.wav'))))
    $speaker.Speak($entry.Value)
    $speaker.SetOutputToNull()
}
$speaker.Dispose()
Write-Output "Generated $($prompts.Count) spoken prompts using Windows speech."
