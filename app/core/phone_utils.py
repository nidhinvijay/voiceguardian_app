import re

_DIGIT_MATCHER = re.compile(r'\D+')


def normalize_indian_phone_number(value: str) -> str | None:
    """Normalize a phone number to +91XXXXXXXXXX form."""
    if not value:
        return None

    digits = _DIGIT_MATCHER.sub('', value)
    if len(digits) > 10:
        digits = digits[-10:]

    if len(digits) != 10:
        return None

    return f'+91{digits}'
