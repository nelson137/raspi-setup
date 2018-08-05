#!/bin/bash

mk_src() { echo "$2" | sudo tee "/etc/apt/sources.list.d/$1.list" >/dev/null; }
curl_add_key() { curl -sSL "$1" | sudo apt-key add -; }
apt_add_key() {
    local ks="$1"
    shift
    sudo apt-key adv --keyserver "$ks" --recv-keys "$@"
}

# Etcher
mk_src etcher 'deb https://dl.bintray.com/resin-io/debian/ stable etcher'
apt_add_key 'hkp://pgp.mit.edu:80' 379CE192D401AB61

# Google Chrome
mk_src google-chrome \
    'deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main'
curl_add_key 'https://dl.google.com/linux/linux_signing_key.pub'

# OBS
sudo add-apt-repository -y ppa:obsproject/obs-studio

# Spotify
mk_src spotify 'deb http://repository.spotify.com/ stable non-free'
apt_add_key 'hkp://keyserver.ubuntu.com:80' \
    931FF8E79F0876134EDDBDCCA87FF9DF48BF1C90

# Sublime
mk_src sublime-text 'deb https://download.sublimetext.com/ apt/stable/'
curl_add_key 'https://download.sublimetext.com/sublimehq-pub.gpg'

# Teamviewer
curl_add_key 'https://download.teamviewer.com/download/linux/signature/TeamViewer2017.asc'
wget 'https://download.teamviewer.com/download/linux/teamviewer_amd64.deb'
install_tv='sudo dpkg -i teamviewer_amd64.deb && rm teamviewer_amd64.deb'
"$install_tv" || { sudo apt install --fix-broken; "$install_tv"; }

# VirtualBox
curl_add_key 'https://www.virtualbox.org/download/oracle_vbox_2016.asc'
curl_add_key 'https://www.virtualbox.org/download/oracle_vbox.asc'

sudo apt update
sudo apt install -y etcher-electron google-chrome-stable obs-studio \
    spotify-client sublime-text teamviewer virtualbox
