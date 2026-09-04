"""Opt-in diagnostic logging for the Python engine."""

import os
import tempfile


_ENABLED = os.environ.get("FILMCUTTER_DEBUG", "").lower() in {
    "1", "true", "yes"
}
_LOG_PATH = os.environ.get(
    "FILMCUTTER_DEBUG_LOG",
    os.path.join(tempfile.gettempdir(), "filmcutter_debug.log"),
)


def debug_log(message: str):
    """Write diagnostics only when explicitly enabled by the caller."""
    if not _ENABLED:
        return
    try:
        with open(_LOG_PATH, "a", encoding="utf-8") as log_file:
            log_file.write(message.rstrip() + "\n")
    except OSError:
        # Diagnostics must never make a scan fail.
        pass
