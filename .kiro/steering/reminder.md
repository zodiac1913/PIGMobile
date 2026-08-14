---
inclusion: auto
---

# Session Reminder

**TODO: Fix PIGv4 streaming redirect issue.** The PIG Web server (PIGv4 Docker) is sending an HTTP redirect from HTTPS to `http://127.0.0.1` internally during streaming. The server's streaming endpoint (`/Player/Stream`) should serve the MP3 directly without a redirect, so we can remove `android:usesCleartextTraffic="true"` from the Android manifest. This is a PIGv4 server-side fix, not a PIG Mobile fix.

Remind the user about this once at the start of each session.
