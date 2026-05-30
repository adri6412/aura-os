# AuraOS Profile — Audio: PulseAudio
PROFILE_NAME="Audio: PulseAudio"
PROFILE_DESC="Stack audio classico PulseAudio (alternativa a PipeWire)"
PROFILE_CONFLICTS="audio-pipewire"

# Non rimuovere pipewire: serve per screen sharing e camera
# (xdg-desktop-portal-gnome e gnome-session dipendono da wireplumber)
# Si disabilitano solo i servizi audio di PipeWire e si abilita PulseAudio
REMOVE_PACKAGES=""
INSTALL_PACKAGES="pulseaudio pulseaudio-utils pulseaudio-module-bluetooth pavucontrol"
DISABLE_SERVICES="pipewire.service pipewire-pulse.service wireplumber.service"
ENABLE_SERVICES="pulseaudio.service"
