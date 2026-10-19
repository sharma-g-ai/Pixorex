"""Signed links to private MinIO files (BC-09, CONSTITUTION rule 12, PRD FR-6.4).

A0 DRAFT, NEEDS ARCHITECT REVIEW (CONSTITUTION §5): signed URLs are human-written. Written
as a draft so the export flow can be tested end to end; replace or approve before merge.

Rules it follows: a link is issued only after the caller's authorization was checked on
this request (the caller does that, so none is issued after revocation), it is
object-specific and read-only (GET). Photos: 15 minutes. Export files: until the export
link expires (1 hour after the file was built), never later.
"""

from datetime import UTC, datetime

from app.core.storage import StorageConfig, client

PHOTO_SECONDS = 15 * 60


def export_download_url(
    config: StorageConfig, key: str, expires_at: datetime, filename: str
) -> str:
    seconds = int((expires_at - datetime.now(UTC)).total_seconds())
    if seconds <= 0:
        raise ValueError("the link has already expired")
    url: str = client(config, public=True).generate_presigned_url(
        "get_object",
        Params={
            "Bucket": config.bucket,
            "Key": key,
            "ResponseContentDisposition": f'attachment; filename="{filename}"',
            "ResponseContentType": "text/csv; charset=utf-8",
        },
        ExpiresIn=min(seconds, 3600),
    )
    return url


def photo_url(config: StorageConfig, key: str) -> str:
    url: str = client(config, public=True).generate_presigned_url(
        "get_object", Params={"Bucket": config.bucket, "Key": key}, ExpiresIn=PHOTO_SECONDS
    )
    return url
