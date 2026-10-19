"""Private object storage (ARCHITECTURE §2: MinIO; AWS S3 later, same S3 API via boto3).

Files are written from inside the network (internal URL). Download links are signed for
the address browsers use (public URL): the signature covers the host, so the two differ
in Docker. Signing lives in app/auth/signed_urls.py (A0, BC-09)."""

from dataclasses import dataclass
from typing import Any

import anyio
import boto3
from botocore.config import Config
from botocore.exceptions import ClientError
from pydantic import AnyHttpUrl, SecretStr


@dataclass(frozen=True)
class StorageConfig:
    internal_url: str
    public_url: str
    access_key: str
    secret_key: SecretStr
    bucket: str


def config_from(
    *,
    minio_url: AnyHttpUrl,
    minio_public_url: AnyHttpUrl | None,
    access_key: str | None,
    secret_key: SecretStr | None,
    bucket: str,
) -> StorageConfig | None:
    """None when storage isn't configured (then large exports stay queued)."""
    if not access_key or secret_key is None:
        return None
    return StorageConfig(
        internal_url=str(minio_url).rstrip("/"),
        public_url=str(minio_public_url or minio_url).rstrip("/"),
        access_key=access_key,
        secret_key=secret_key,
        bucket=bucket,
    )


def client(config: StorageConfig, *, public: bool = False) -> Any:
    return boto3.client(
        "s3",
        endpoint_url=config.public_url if public else config.internal_url,
        aws_access_key_id=config.access_key,
        aws_secret_access_key=config.secret_key.get_secret_value(),
        region_name="us-east-1",
        config=Config(signature_version="s3v4", s3={"addressing_style": "path"}),
    )


def _ensure_bucket(config: StorageConfig) -> None:
    s3 = client(config)
    try:
        s3.head_bucket(Bucket=config.bucket)
    except ClientError:
        s3.create_bucket(Bucket=config.bucket)


async def ensure_bucket(config: StorageConfig) -> None:
    await anyio.to_thread.run_sync(_ensure_bucket, config)


def _put(config: StorageConfig, key: str, body: bytes, content_type: str) -> None:
    client(config).put_object(Bucket=config.bucket, Key=key, Body=body, ContentType=content_type)


async def put(config: StorageConfig, key: str, body: bytes, content_type: str) -> None:
    await anyio.to_thread.run_sync(_put, config, key, body, content_type)
