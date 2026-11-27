## ADDED Requirements

### Requirement: A call that starts pauses the music once
When a call in a catalog app becomes ongoing, from no call or from a ring, Kannu SHALL pause the music that is
playing by sending its music source one explicit pause command. It SHALL do so only while **Pause music during calls**
(on by default) and **Show calls from other apps** are both on, only when Kannu's music state says playing, and only
when the music's source is not the calling app or one of its helpers. It SHALL send that command at most once per
call: nothing while the call goes on, and nothing when it ends. Kannu SHALL NOT resume, toggle or start the music
because of a call.

#### Scenario: A call connects while music plays
- **WHEN** Spotify is playing and a WhatsApp call connects
- **THEN** Spotify pauses within about 2 seconds of the call connecting, and stays paused after the call ends

#### Scenario: The setting is off
- **WHEN** the user has switched **Pause music during calls** off and a call connects while music plays
- **THEN** the music keeps playing

#### Scenario: The music is already paused
- **WHEN** a call connects while no music is playing
- **THEN** Kannu sends no command

#### Scenario: The calling app is the music source
- **WHEN** WhatsApp is the Now Playing app, as it is for a voice note, and a WhatsApp call connects
- **THEN** Kannu sends no command

#### Scenario: The user plays music during the call
- **WHEN** the music paused as the call started and the user presses play during the call
- **THEN** the music plays on, and Kannu sends no further command for that call
