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

    @patch("app.api.dependencies.auth.get_firestore_client")
    @patch("app.api.dependencies.auth.firebase_auth.verify_id_token")
    def test_firebase_is_initialized_before_token_verification(
        self, verify_token: Mock, get_db: Mock
    ) -> None:
        initialized = False
        database = Mock()
        snapshot = Mock(exists=True)
        snapshot.to_dict.return_value = {"active": True, "role": "admin"}
        database.collection.return_value.document.return_value.get.return_value = (
            snapshot
        )

        def initialize_firebase() -> Mock:
            nonlocal initialized
            initialized = True
            return database

        def verify_initialized_token(*_args: object, **_kwargs: object) -> dict:
            self.assertTrue(initialized)
            return {"uid": "admin-1", "email": "admin@example.com"}

        get_db.side_effect = initialize_firebase
        verify_token.side_effect = verify_initialized_token

        user = require_active_user(self._credentials())

        self.assertEqual(user.role, "admin")
