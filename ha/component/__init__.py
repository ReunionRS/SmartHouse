"""Smart House hub identity and pairing discovery API."""

import os
import base64
import hashlib
import hmac
import json
import secrets
import time

from aiohttp import web

from homeassistant.components.http import KEY_HASS, HomeAssistantView
from homeassistant.core import HomeAssistant
from homeassistant.helpers import config_validation as cv
from homeassistant.helpers.typing import ConfigType

DOMAIN = "smart_house"
CONFIG_SCHEMA = cv.empty_config_schema(DOMAIN)


async def async_setup(hass: HomeAssistant, config: ConfigType) -> bool:
    """Expose non-sensitive product information for the Smart House app."""
    hass.http.register_view(SmartHouseInfoView)
    return True


class SmartHouseInfoView(HomeAssistantView):
    """Describe this local Smart House hub before authentication."""

    url = "/api/smart_house/info"
    name = "api:smart_house:info"
    requires_auth = False

    async def get(self, request: web.Request) -> web.Response:
        """Return hub identity and whether an owner already exists."""
        hass: HomeAssistant = request.app[KEY_HASS]
        owner = await hass.auth.async_get_owner()
        hub_id = os.environ.get("SMART_HOUSE_HUB_ID", "")
        payload = json.dumps(
            {
                "hubId": hub_id,
                "issuedAt": int(time.time()),
                "nonce": secrets.token_urlsafe(16),
            },
            separators=(",", ":"),
        ).encode()
        encoded_payload = base64.urlsafe_b64encode(payload).rstrip(b"=")
        signature = hmac.new(
            os.environ.get("HA_PAIRING_SECRET", "").encode(),
            encoded_payload,
            hashlib.sha256,
        ).digest()
        pairing_proof = (
            f"{encoded_payload.decode()}."
            f"{base64.urlsafe_b64encode(signature).rstrip(b'=').decode()}"
        )
        return self.json(
            {
                "product": "Smart House Hub",
                "hubId": hub_id,
                "claimed": owner is not None,
                "pairingProtocol": 1,
                "pairingProof": pairing_proof,
            }
        )
