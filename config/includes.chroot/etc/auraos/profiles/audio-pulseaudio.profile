# AuraOS Profile — Audio: PulseAudio
PROFILE_NAME="Audio: PulseAudio"
PROFILE_DESC="Stack audio classico PulseAudio (alternativa a PipeWire)"
PROFILE_CONFLICTS="audio-pipewire"
REMOVE_PACKAGES="pipewire pipewire-audio pipewire-alsa pipewire-pulse wireplumber"
INSTALL_PACKAGES="pulseaudio pulseaudio-utils pulseaudio-module-bluetooth pavucontrol"
DISABLE_SERVICES="pipewire.service pipewire-pulse.service wireplumber.service"
ENABLE_SERVICES="pulseaudio.service"
