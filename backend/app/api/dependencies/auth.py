from __future__ import annotations

from dataclasses import dataclass
from typing import Annotated, Callable

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from firebase_admin import auth as firebase_auth

from app.core.config import get_settings
from app.services.firebase_service import get_firestore_client

bearer_scheme = HTTPBearer(auto_error=False)


@dataclass(frozen=True)
class AuthenticatedUser:
    uid: str
    email: str
    role: str


def _authentication_error(detail: str) -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail=detail,
        headers={"WWW-Authenticate": "Bearer"},
    )


def require_active_user(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer_scheme)],
) -> AuthenticatedUser:
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise _authentication_error("Authentication is required.")

    settings = get_settings()
    try:
        decoded = firebase_auth.verify_id_token(
            credentials.credentials,
            check_revoked=settings.firebase_check_revoked_tokens,
        )
    except (
        firebase_auth.InvalidIdTokenError,
        firebase_auth.ExpiredIdTokenError,
        firebase_auth.RevokedIdTokenError,
        firebase_auth.UserDisabledError,
    ) as exc:
        raise _authentication_error(
            "The Firebase session is invalid or expired."
        ) from exc
    except Exception as exc:  # noqa: BLE001
        raise _authentication_error(
            "The Firebase session could not be verified."
        ) from exc

    uid = str(decoded.get("uid") or decoded.get("sub") or "").strip()
    if not uid:
        raise _authentication_error("The Firebase token has no user identifier.")

    profile_snapshot = get_firestore_client().collection("users").document(uid).get()
    profile = profile_snapshot.to_dict() if profile_snapshot.exists else None
    if not profile or profile.get("active") is not True:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="The user is pending approval or inactive.",
        )

    role = str(profile.get("role") or "pending").strip().lower()
    email = str(decoded.get("email") or profile.get("email") or "").strip().lower()
    return AuthenticatedUser(uid=uid, email=email, role=role)


def require_roles(*allowed_roles: str) -> Callable[..., AuthenticatedUser]:
    normalized_roles = {role.strip().lower() for role in allowed_roles}

    def dependency(
        user: Annotated[AuthenticatedUser, Depends(require_active_user)],
    ) -> AuthenticatedUser:
        if user.role not in normalized_roles:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="The user does not have permission for this operation.",
            )
        return user

    return dependency
