"""Smart House account pairing authentication provider."""

from collections.abc import Mapping
import logging
from typing import Any, override

import voluptuous as vol

from homeassistant.auth.const import GROUP_ID_ADMIN
from homeassistant.core import callback
from homeassistant.exceptions import HomeAssistantError
from homeassistant.components.onboarding import (
    STORAGE_KEY as ONBOARDING_STORAGE_KEY,
    STORAGE_VERSION as ONBOARDING_STORAGE_VERSION,
    OnboardingStorage,
)
from homeassistant.components.onboarding.const import DOMAIN as ONBOARDING_DOMAIN
from homeassistant.components.onboarding.const import STEPS as ONBOARDING_STEPS
from homeassistant.helpers.aiohttp_client import async_get_clientsession

from ..models import AuthFlowContext, AuthFlowResult, Credentials, UserMeta
from . import AUTH_PROVIDER_SCHEMA, AUTH_PROVIDERS, AuthProvider, LoginFlow

_LOGGER = logging.getLogger(__name__)

CONFIG_SCHEMA = AUTH_PROVIDER_SCHEMA.extend(
    {
        vol.Required("backend_url"): vol.Url(),
        vol.Required("hub_id"): str,
        vol.Required("pairing_secret"): str,
    },
    extra=vol.PREVENT_EXTRA,
)


class InvalidPairingToken(HomeAssistantError):
    """Raised when a Smart House pairing token cannot be consumed."""


@AUTH_PROVIDERS.register("smart_house")
class SmartHouseAuthProvider(AuthProvider):
    """Authenticate HA users through one-time Smart House pairing sessions."""

    DEFAULT_TITLE = "Smart House"

    @property
    def support_mfa(self) -> bool:
        """Smart House handles account security before issuing a pairing token."""
        return False

    @override
    async def async_login_flow(
        self, context: AuthFlowContext | None
    ) -> "SmartHouseLoginFlow":
        """Return the pairing login flow."""
        return SmartHouseLoginFlow(self)

    async def async_consume_pairing_token(self, token: str) -> dict[str, str]:
        """Consume a one-time token and return the linked Smart House identity."""
        backend_url = self.config["backend_url"].rstrip("/")
        session = async_get_clientsession(self.hass)
        try:
            async with session.post(
                f"{backend_url}/api/home-assistant/pairing-sessions/consume",
                headers={
                    "x-smart-house-pairing-secret": self.config["pairing_secret"]
                },
                json={"token": token, "hubId": self.config["hub_id"]},
                timeout=10,
            ) as response:
                payload: Any = await response.json(content_type=None)
                if response.status != 200 or not isinstance(payload, dict):
                    raise InvalidPairingToken
        except InvalidPairingToken:
            raise
        except Exception as error:
            _LOGGER.warning("Smart House pairing backend is unavailable: %s", error)
            raise InvalidPairingToken from error

        user = payload.get("user")
        if not isinstance(user, dict) or not user.get("id"):
            raise InvalidPairingToken
        return {
            "smart_house_user_id": str(user["id"]),
            "email": str(user.get("email") or ""),
            "name": str(user.get("name") or user.get("email") or "Smart House"),
        }

    @override
    async def async_get_or_create_credentials(
        self, flow_result: Mapping[str, str]
    ) -> Credentials:
        """Find the linked HA user or create the first local owner."""
        smart_house_user_id = flow_result["smart_house_user_id"]
        for credential in await self.async_credentials():
            if credential.data.get("smart_house_user_id") == smart_house_user_id:
                return credential

        credentials = self.async_create_credentials(
            {
                "smart_house_user_id": smart_house_user_id,
                "email": flow_result.get("email", ""),
            }
        )
        user = await self.hass.auth.async_create_user(
            flow_result.get("name") or flow_result.get("email") or "Smart House",
            group_ids=[GROUP_ID_ADMIN],
        )
        await self.hass.auth.async_link_user(user, credentials)
        if user.is_owner:
            await self._async_complete_onboarding()
        return credentials

    async def _async_complete_onboarding(self) -> None:
        """Finish the stock onboarding after the first paired owner is created."""
        onboarding = self.hass.data.get(ONBOARDING_DOMAIN)
        if onboarding is None or onboarding.onboarded:
            return

        onboarding.steps["done"] = list(ONBOARDING_STEPS)
        onboarding.onboarded = True
        store = OnboardingStorage(
            self.hass,
            ONBOARDING_STORAGE_VERSION,
            ONBOARDING_STORAGE_KEY,
            private=True,
        )
        await store.async_save(onboarding.steps)
        listeners = list(onboarding.listeners)
        onboarding.listeners.clear()
        for listener in listeners:
            listener()

    @override
    async def async_user_meta_for_credentials(
        self, credentials: Credentials
    ) -> UserMeta:
        """Return metadata for compatibility with the HA auth manager."""
        return UserMeta(
            name=credentials.data.get("email") or "Smart House",
            is_active=True,
            group=GROUP_ID_ADMIN,
        )


class SmartHouseLoginFlow(LoginFlow[SmartHouseAuthProvider]):
    """Handle a one-time pairing token submitted by the Smart House app."""

    @override
    async def async_step_init(
        self, user_input: dict[str, str] | None = None
    ) -> AuthFlowResult:
        """Validate and consume the pairing token."""
        errors: dict[str, str] = {}
        if user_input is not None:
            try:
                identity = await self._auth_provider.async_consume_pairing_token(
                    user_input["pairing_token"]
                )
            except InvalidPairingToken:
                errors["base"] = "invalid_auth"
            else:
                return await self.async_finish(identity)

        return self.async_show_form(
            step_id="init",
            data_schema=vol.Schema({vol.Required("pairing_token"): str}),
            errors=errors,
        )
