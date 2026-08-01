# agy_login_recording.bin

Every byte `agy login` (Antigravity CLI 1.1.9) wrote to a pseudo-terminal 94
columns wide, on a Linux server, up to the point where it shows a sign-in link
and waits for a code. Captured by `capture_login_recording.py`, which is kept
beside it so the recording can be remade when the CLI changes.

It exists because four attempts at this bug were verified against fixtures
invented from a guess at what the program prints, and one of those fixtures
passed with the fix removed — it was not reproducing the failure at all. This
is the real output, so `console_replay_probe` checks the console against what
Antigravity does rather than against what I assumed it does.

The probe replays it whole and in 4096, 1024 and 137-byte pieces. That matters:
the address the console picked out used to depend on where a read happened to
be cut, and three of the four sizes gave a different, broken address. Reading
the last piece to arrive is how a half-written link came to be opened.

Nothing here is private. The request is one the capture itself created, the
client id belongs to Google's own application and is public by design, and the
challenge and state are single-use values from a sign-in nobody completed. The
server address does not appear.
