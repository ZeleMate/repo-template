"""Small helpers shared by Acme services."""


def slugify(text: str) -> str:
    """Lowercase text and join words with dashes."""
    return "-".join(text.lower().split())
