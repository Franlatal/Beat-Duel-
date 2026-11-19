Shared level sound effects
==========================

Every level finds these by file name (.wav, .ogg or .mp3), so to change a
sound just drop in a file with the same name. A missing file is silent.

  countdown      each 3 / 2 / 1 beep before the song
  countdown_3    (optional) replaces "countdown" for the 3 only, same for
  countdown_2    countdown_2 and countdown_1, if you want a rising beep
  countdown_1
  countdown_go   the "DUEL!" at the end of the countdown
  hit            click on every note you hit (Perfect or Good)
  hold           loops while you hold a hold note. Plays once per held
                 lane, pitched a little higher in each lane. Any length
                 works; it's looped automatically.
  hold_end       (optional) when you finish a hold
  miss           a missed / dropped note
  segment_pass, segment_fail, victory, game_over

hit, hold, countdown and countdown_go here are placeholders.

Volume and on/off switches are on the level in the Inspector, under
Sound: Hit Sounds Enabled, Hit Sound Volume Db, Hold Sounds Enabled,
Hold Sound Volume Db, Hold Lane Pitches, and Sfx Volume Db for all of them.
