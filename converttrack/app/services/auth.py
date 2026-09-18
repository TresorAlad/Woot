from functools import wraps

from flask import current_app, jsonify, request


def require_converttrack_secret(view):
    @wraps(view)
    def wrapped(*args, **kwargs):
        secret = current_app.config.get("WEBHOOK_SECRET", "")
        if not secret:
            return view(*args, **kwargs)

        provided = request.headers.get("X-ConvertTrack-Secret", "")
        if not hmac_compare(provided, secret):
            return jsonify({"error": "unauthorized"}), 401
        return view(*args, **kwargs)

    return wrapped


def hmac_compare(provided: str, expected: str) -> bool:
    import hmac

    return hmac.compare_digest(provided or "", expected or "")
