from unittest import TestCase
from unittest.mock import Mock, patch

from fastapi import HTTPException
from fastapi.security import HTTPAuthorizationCredentials

from app.api.dependencies.auth import (
    AuthenticatedUser,
    require_active_user,
    require_roles,
)


class AuthDependencyTests(TestCase):
    def _credentials(self) -> HTTPAuthorizationCredentials:
        return HTTPAuthorizationCredentials(scheme="Bearer", credentials="token")

    @patch("app.api.dependencies.auth.get_firestore_client")
    @patch("app.api.dependencies.auth.firebase_auth.verify_id_token")
    def test_active_profile_is_returned(self, verify_token: Mock, get_db: Mock) -> None:
        verify_token.return_value = {"uid": "user-1", "email": "worker@example.com"}
        snapshot = Mock()
        snapshot.exists = True
        snapshot.to_dict.return_value = {"active": True, "role": "warehouse"}
        get_db.return_value.collection.return_value.document.return_value.get.return_value = (
            snapshot
        )

        user = require_active_user(self._credentials())

        self.assertEqual(user.uid, "user-1")
        self.assertEqual(user.role, "warehouse")

    @patch("app.api.dependencies.auth.get_firestore_client")
    @patch("app.api.dependencies.auth.firebase_auth.verify_id_token")
    def test_pending_profile_is_rejected(
        self, verify_token: Mock, get_db: Mock
    ) -> None:
        verify_token.return_value = {"uid": "user-2", "email": "new@example.com"}
        snapshot = Mock()
        snapshot.exists = True
        snapshot.to_dict.return_value = {"active": False, "role": "pending"}
        get_db.return_value.collection.return_value.document.return_value.get.return_value = (
            snapshot
        )

        with self.assertRaises(HTTPException) as raised:
            require_active_user(self._credentials())

        self.assertEqual(raised.exception.status_code, 403)

    def test_role_dependency_rejects_wrong_role(self) -> None:
        dependency = require_roles("admin")

        with self.assertRaises(HTTPException) as raised:
            dependency(
                AuthenticatedUser(
                    uid="user-3",
                    email="worker@example.com",
                    role="warehouse",
                )
            )

        self.assertEqual(raised.exception.status_code, 403)
