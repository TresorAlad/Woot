import json
import logging
import os
from contextlib import contextmanager
from typing import Any

logger = logging.getLogger(__name__)


@contextmanager
def locked_file(path: str, mode: str):
    directory = os.path.dirname(path)
    if directory:
        os.makedirs(directory, exist_ok=True)

    handle = open(path, mode, encoding="utf-8")
    try:
        if mode not in ("r", "rb"):
            try:
                import fcntl

                fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
            except ImportError:
                pass
        yield handle
    finally:
        try:
            import fcntl

            fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
        except ImportError:
            pass
        handle.close()


def read_json(path: str, default: Any) -> Any:
    if not os.path.isfile(path):
        return default

    try:
        with locked_file(path, "r") as handle:
            return json.load(handle)
    except (json.JSONDecodeError, OSError) as exc:
        logger.warning("Impossible de lire %s: %s", path, exc)
        return default


def write_json(path: str, data: Any) -> None:
    with locked_file(path, "w") as handle:
        json.dump(data, handle, indent=2, ensure_ascii=False)
