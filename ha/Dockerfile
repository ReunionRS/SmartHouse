ARG HA_BASE_IMAGE=ghcr.io/home-assistant/home-assistant:stable
FROM ${HA_BASE_IMAGE}

LABEL org.opencontainers.image.title="Smart House HA"
LABEL org.opencontainers.image.description="Home Assistant runtime for Smart House hubs"

COPY auth/smart_house.py /usr/src/homeassistant/homeassistant/auth/providers/smart_house.py
COPY component/ /usr/src/homeassistant/homeassistant/components/smart_house/
