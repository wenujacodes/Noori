# To do

Planned work for Noori. Finished items move to `CHANGELOG.md`.

## Music

- [ ] **Playing Next (Spotify only).** A list button next to the lyrics button
  in the open notch shows the next 4–5 songs (cover, title, artist), like the
  iOS "Playing Next" list.
  - Data: Spotify Web API `GET /me/player/queue`. Needs a one-time "Connect
    Spotify" sign-in in Settings (PKCE, no secret; redirect `noori://spotify`).
  - Spotify limits unapproved apps to 25 allow-listed users, so each user pastes
    their own free Spotify app Client ID in Settings (check Spotify's current
    rules before building).
  - Read-only: Spotify doesn't let other apps reorder or remove queued songs,
    so no drag handles. Tapping a song could skip forward to it.
  - Apple Music and other players can't share their queue; the button only
    shows for a connected Spotify.
