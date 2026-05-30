# AuraOS Profile — Audio: PipeWire (default)
PROFILE_NAME="Audio: PipeWire"
PROFILE_DESC="Stack audio default (PipeWire + WirePlumber)"
PROFILE_CONFLICTS="audio-pulseaudio"

# Ripristina PipeWire come stack audio (revert di audio-pulseaudio)
REMOVE_PACKAGES="pulseaudio pulseaudio-utils pulseaudio-module-bluetooth"
INSTALL_PACKAGES="pipewire pipewire-audio pipewire-alsa pipewire-pulse wireplumber"
DISABLE_SERVICES="pulseaudio.service"
ENABLE_SERVICES="pipewire.service pipewire-pulse.service wireplumber.service"
