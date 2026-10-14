"""Shared Snowflake helpers: key-pair auth for the Python connector and for REST (MCP) calls."""

from __future__ import annotations

import base64
import hashlib
import os
import time
from pathlib import Path

import jwt
import snowflake.connector
from cryptography.hazmat.primitives import serialization
from dotenv import load_dotenv

load_dotenv(Path(__file__).resolve().parent.parent / ".env")

ACCOUNT = os.environ["SNOWFLAKE_ACCOUNT"]
USER = os.environ["SNOWFLAKE_USER"]
KEY_PATH = Path(os.path.expanduser(os.environ["SNOWFLAKE_PRIVATE_KEY_PATH"]))
ACCOUNT_URL = f"https://{ACCOUNT.lower().replace('_', '-')}.snowflakecomputing.com"


def _private_key():
    return serialization.load_pem_private_key(KEY_PATH.read_bytes(), password=None)


def keypair_jwt(lifetime_s: int = 3540) -> str:
    """Short-lived JWT for Snowflake REST APIs (X-Snowflake-Authorization-Token-Type: KEYPAIR_JWT)."""
    key = _private_key()
    pub_der = key.public_key().public_bytes(
        serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo
    )
    fingerprint = "SHA256:" + base64.b64encode(hashlib.sha256(pub_der).digest()).decode()
    qualified_user = f"{ACCOUNT.upper()}.{USER.upper()}"
    now = int(time.time())
    return jwt.encode(
        {"iss": f"{qualified_user}.{fingerprint}", "sub": qualified_user, "iat": now, "exp": now + lifetime_s},
        key,
        algorithm="RS256",
    )


def connect(role: str | None = None):
    key = _private_key()
    return snowflake.connector.connect(
        account=ACCOUNT,
        user=USER,
        private_key=key.private_bytes(
            serialization.Encoding.DER, serialization.PrivateFormat.PKCS8, serialization.NoEncryption()
        ),
        role=role,
        session_parameters={"QUERY_TAG": '{"app": "fleet-to-snowflake-mcp"}'},
    )
