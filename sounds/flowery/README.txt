Flowery voice clips
===================

Drop voice clips in this folder (.wav, .ogg or .mp3). The level finds them
by file name, so nothing has to be set in the Godot editor. A missing clip
is simply silent.

Shared cues (every level):
  intro          when the level starts (during the 3-2-1 countdown)
  segment_pass   a segment is cleared (he takes the hit)
  victory        the song is finished
  game_over      you run out of HP

Level 1 only:
  jakidding      the fake jarona: said as he starts his dash   (have it)
  prism_blow     a segment is failed: said as he starts the Prism Blow   (have it)
  spared         the MERCY meter is full and you're spared
                 (plays instead of game_over)

Level 1 does not use segment_fail (prism_blow takes its place there).

Chart events work too: any "E name" event in the played difficulty's track
plays name.wav at that moment (Level 1 handles "E jakidding" itself, so
the line lines up with his dash).

Variants: name several files intro_1, intro_2, ... (up to _9) and one is
picked at random each time, never the same one twice in a row.

The jarona dash shouts, the parry sound and the jarona hit sound stay in
sounds/jarona (set on Level1 in the editor).
