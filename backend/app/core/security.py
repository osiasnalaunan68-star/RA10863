from typing import Optional

from fastapi import Header, HTTPException, status

from app.core.config import settings as app_settings


def require_edit_access(
    x_admin_key: Optional[str] = Header(default=None, alias="X-Admin-Key"),
) -> None:
    """Optional gate for endpoints that mutate legal text.

    Only enforced when EDIT_ACCESS_KEY is configured; left open otherwise so
    the solo/local workflow keeps working with zero setup.
    """
    if app_settings.EDIT_ACCESS_KEY:
        if not x_admin_key or x_admin_key != app_settings.EDIT_ACCESS_KEY:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Missing or invalid X-Admin-Key header",
            )
