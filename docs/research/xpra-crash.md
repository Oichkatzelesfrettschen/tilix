# xpra Crash Investigation

## Repro (debug)
- xpra start :100 --html=no --mdns=no --dbus=no \
  --start-child=/home/eirikr/Github/tilix/tilix \
  --exit-with-children=yes --debug=all --daemon=yes \
  --log-dir=/tmp --log-file=/tmp/xpra-tilix-debug.log

## Observed Failure
- Crash during gstreamer encoder selftest initialization.
- Assertion:
  ERROR:../pygobject/gi/pygi-invoke.c:45:next_python_argument
- Fatal Python error: Aborted

## Mitigation
- Start with --gstreamer=no to avoid the crash.
- Session stays live with gstreamer disabled in local tests.

## Notes
- Debug logs contain environment variables; treat as sensitive and sanitize
  before sharing upstream.

## Next Steps
- Isolate the gstreamer GI callsite in xpra encoder initialization.
- Re-test with updated gobject-introspection or Python version.
- Report upstream with sanitized logs and minimal repro.
