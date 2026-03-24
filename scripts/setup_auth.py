#!/usr/bin/env python3
"""
Generate secure auth credentials and add them to .env file.

Usage:
    python scripts/setup_auth.py              # Interactive prompts
    python scripts/setup_auth.py --auto       # Auto-generate everything
    python scripts/setup_auth.py --username admin --password mypass  # Explicit credentials
"""

import argparse
import os
import secrets
import string
import sys
from pathlib import Path


def generate_password(length: int = 16) -> str:
    """Generate a random password with letters, digits, and punctuation."""
    alphabet = string.ascii_letters + string.digits + "!@#$%&*"
    return "".join(secrets.choice(alphabet) for _ in range(length))


def generate_token(length: int = 32) -> str:
    """Generate a URL-safe random token."""
    return secrets.token_urlsafe(length)


def update_env_file(env_path: Path, updates: dict[str, str]) -> None:
    """Update or append key=value pairs in a .env file."""
    lines: list[str] = []
    existing_keys: set[str] = set()

    if env_path.exists():
        with open(env_path, "r") as f:
            lines = f.readlines()

    # Update existing lines
    new_lines: list[str] = []
    for line in lines:
        stripped = line.strip()
        if stripped and not stripped.startswith("#") and "=" in stripped:
            key = stripped.split("=", 1)[0]
            if key in updates:
                new_lines.append(f"{key}={updates[key]}\n")
                existing_keys.add(key)
                continue
        new_lines.append(line)

    # Append missing keys
    for key, value in updates.items():
        if key not in existing_keys:
            new_lines.append(f"{key}={value}\n")

    with open(env_path, "w") as f:
        f.writelines(new_lines)


def main() -> None:
    parser = argparse.ArgumentParser(description="Setup auth credentials for WorkbenchIQ")
    parser.add_argument("--auto", action="store_true", help="Auto-generate all values without prompts")
    parser.add_argument("--username", default=None, help="Login username (default: admin)")
    parser.add_argument("--password", default=None, help="Login password (auto-generated if not provided)")
    parser.add_argument("--env-file", default=".env", help="Path to .env file (default: .env)")
    args = parser.parse_args()

    env_path = Path(args.env_file)

    # Create .env from .env.example if it doesn't exist
    if not env_path.exists():
        example_path = Path(".env.example")
        if example_path.exists():
            import shutil
            shutil.copy(example_path, env_path)
            print(f"Created {env_path} from .env.example")
        else:
            env_path.touch()
            print(f"Created empty {env_path}")

    if args.auto:
        username = args.username or "admin"
        password = args.password or generate_password()
    else:
        default_user = args.username or "admin"
        username = input(f"Login username [{default_user}]: ").strip() or default_user
        if args.password:
            password = args.password
        else:
            password = input("Login password (leave empty to auto-generate): ").strip()
            if not password:
                password = generate_password()

    api_secret_key = generate_token()
    auth_secret = generate_token()

    updates = {
        "AUTH_USER_1": f"{username}:{password}",
        "AUTH_SECRET": auth_secret,
        "API_SECRET_KEY": api_secret_key,
    }

    update_env_file(env_path, updates)

    print("")
    print("=" * 60)
    print("  Auth credentials configured!")
    print("=" * 60)
    print("")
    print(f"  Frontend login:  {username} / {password}")
    print(f"  AUTH_SECRET:     {auth_secret[:8]}...  (HMAC signing key)")
    print(f"  API_SECRET_KEY:  {api_secret_key[:8]}...  (backend API key)")
    print("")
    print(f"  Saved to: {env_path.resolve()}")
    print("")
    print("  Start the app:")
    print("    Terminal 1:  uv run python -m uvicorn api_server:app --reload --port 8000")
    print("    Terminal 2:  cd frontend && npm run dev")
    print("")
    print("  The backend API now requires X-API-Key header.")
    print("  The frontend proxy injects it automatically.")
    print("  Direct curl calls need:  -H 'X-API-Key: <your-key>'")
    print("=" * 60)


if __name__ == "__main__":
    main()
