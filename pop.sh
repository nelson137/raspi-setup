#!/bin/bash

if [[ "$UID" == 0 ]]; then
    echo 'This script does not need to be run by root' >&2
    exit 1
fi

dir="$(dirname "$0")"



# Cache passwords
cache_passwds() {
    sudo echo >/dev/null
    read -rp 'Github password: ' GITHUB_PASSWD
}



# Update, upgrade, and install packages
pkgs() {
    # PPAs
    sudo add-apt-repository -y ppa:nextcloud-devs/client

    # Update and upgrade
    sudo apt update
    sudo apt-get dist-upgrade ||
        sudo apt-get dist-upgrade --fix-missing
    sudo apt upgrade -y

    # Pip installations
    sudo su nelson pip3 install flake8 flake8-docstrings isort lolcat \
        pycodestyle

    # Installations
    sudo apt install -y apache2 boxes build-essential cmake dnsutils figlet \
        git html-xml-utils jq libsecret-tools lolcat nextcloud-client nmap \
        nodejs openssh-server pylint python3-flask python3-pip python3-tk \
        shellinabox tmux upower vim vlc w3m zsh

    # youtube-dl
    # Don't install from repositories because they are behind
    local url='https://yt-dl.org/downloads/latest/youtube-dl'
    sudo curl -sSL "$url" -o /usr/local/bin/youtube-dl
    sudo chmod a+rx /usr/local/bin/youtube-dl

    # Install figlet font files
    local -a fonts=(banner3 colossal nancyj roman univers)
    for f in "${fonts[@]}"; do
        if [[ ! -f /usr/share/figlet/${f}.flf ]]; then
            sudo curl -sS "http://www.figlet.org/fonts/${f}.flf" \
                -o "/usr/share/figlet/${f}.flf"
        fi
    done

    # Install Etcher, Google Chrome, OBS, Spotify, Sublime Text, Teamviewer,
    # and Virtualbox
    "${dir}/external-installs.sh"
}



# Prevent screen tearing
no_tear() {
    mkdir -p /etc/X11/xorg.conf.d/
    sudo cp "${dir}/files/20-intel.conf" /etc/X11/xorg.conf.d/
}



# Use gsettings to set power settings
power_settings() {
    # - Set the timeout to suspend when inactive
    # - Set the timeout to make the screen blank when inactive
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-timeout 1800
    gsettings set org.gnome.desktop.session idle-delay 900
}



# Use hybrid suspend to wake up quicker
hybrid_suspend() {
    sudo cp "${dir}/files/00-use-suspend-hybrid" /etc/pm/config.d/
}



# Don't suspend while ssh connections are open
# https://bbs.archlinux.org/viewtopic.php?id=176876
ssh_keep_awake() {
    sudo cp "${dir}/files/ssh-keep-awake.service" /etc/systemd/system/
    sudo systemctl enable ssh-keep-awake.service
}



# Clean up SSH MOTD
ssh_motd() {
    # Disable motd-news in config file
    sudo sed -i '/^ENABLED/ s/1/0/' /etc/default/motd-news

    # Disable welcome message
    sudo sed -ri 's/^(printf)/#\1/' /etc/update-motd.d/00-header

    sudo cp "${dir}/files/01-pretty-header" /etc/update-motd.d/

    # Apply /etc/update-motd.d changes
    sudo run-parts /etc/update-motd.d/

    # Disable last login message
    sudo sed -ri 's/^\s*#?\s*(PrintLastLog).*$/\1 no/' /etc/ssh/sshd_config
    sudo systemctl restart sshd.service

    # pretty-header-data.sh setup in "Root crontabs" in crontabs()
}



# User and root crontabs
crontabs() {
    # Set crontab editor to vim basic
    cp "${dir}/files/.selected_editor" ~nelson/

    local comments="$(cat "${dir}/files/comments.crontab")"
    local mailto="MAILTO=''"

    # User crontabs
    # local u_tab=''
    # echo -e "${comments}\n\n${mailto}\n\n${u_tab}" | crontab -

    # Root crontabs
    sudo cp "${dir}/files/pretty-header-data.sh" /root/
    sudo chmod +x /root/pretty-header-data.sh
    local p="'/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'"
    local r_tab='*/10 * * * * /root/pretty-header-data.sh'
    echo -e "${comments}\n\nPATH=${p}\n${mailto}\n\n${r_tab}" | sudo crontab -
}



# User directory and environment
user() {
    # File structure
    mkdir -p ~nelson/{Downloads,Projects/Git}
    git clone 'https://github.com/nelson137/dot.git' ~nelson/Projects/Git/dot

    # Config files
    ln -fs ~nelson/Projects/Git/dot/files/.vimrc ~nelson/
    ln -fs ~nelson/Projects/Git/dot/files/.tmux.conf ~nelson/
    ln -fs ~nelson/Projects/Git/dot/files/.zshrc ~nelson/
    ln -fs ~nelson/Projects/Git/dot/files/.bashrc ~nelson/
    ln -fs ~nelson/Projects/Git/dot/files/.bash_additions ~nelson/

    # git
    # - Copy .gitconfig to ~nelson/
    # - Copy /usr/share/git-core/templates/ to ~nelson/.git_templates/
    # - Copy commit-msg to ~nelson/.git_templates/
    cp "${dir}/files/.gitconfig" ~nelson/
    sudo cp -r /usr/share/git-core/templates/ ~nelson/.git_templates/
    sudo chown -R nelson:nelson ~nelson/.git_templates/
    cp "${dir}/files/commit-msg" ~nelson/.git_templates/hooks/
    chmod a+x ~nelson/.git_templates/hooks/commit-msg

    # Oh My Zsh
    local url='https://github.com/robbyrussell/oh-my-zsh.git'
    git clone --depth=1 "$url" ~nelson/.oh-my-zsh
    sudo chsh -s /usr/bin/zsh nelson

    # Tor
    # - Download Tor from Github
    # - Extract it
    # - Register Tor as an application
    local url='https://github.com/TheTorProject/gettorbrowser/releases'
    local v="$(curl "${url}/latest" 2>/dev/null | grep -Eo 'v[^"]+')"
    local fn="tor-browser-linux64-$(echo "$v" | tr -d v)_en-US.tar.xz"
    wget "${url}/download/${v}/${fn}"
    tar xJf "$fn" -C ~nelson && rm "$fn"
    mv ~nelson/tor-browser_en-US ~nelson/.tor
    ~nelson/.tor/Browser/start-tor-browser --register-app
}



# Generate a new SSH key, replace the old Github key with the new one
git_ssh_key() {
    curl_git() {
        # Query Github API
        local url="https://api.github.com$1"
        shift
        curl -sSLiu "nelson137:$GITHUB_PASSWD" "$@" "$url"
    }

    # Generate SSH key
    yes y | ssh-keygen -t rsa -b 4096 -C 'nelson.earle137@gmail.com' \
        -f ~nelson/.ssh/id_rsa -N ''

    # For each ssh key
    # - Get more data about the key
    # - If the key's title is Pi
    #   - Delete it and upload the new one
    local -a key_ids=(
        $(curl_git '/users/nelson137/keys' | awk '/^\[/,/^\]/' | jq '.[].id')
    )
    local ssh_key="$(cat ~nelson/.ssh/id_rsa.pub)"
    for id in "${key_ids[@]}"; do
        local json="$(curl_git "/user/keys/$id" | awk '/^\{/,/^\}/')"
        if [[ $(echo "$json" | jq -r '.title') == Pop ]]; then
            curl_git "/user/keys/$id" -X DELETE
            break
        fi
    done
    curl_git '/user/keys' -d '{ "title": "Pop", "key": "'"$ssh_key"'" }'
}


# Root directory
root() {
    sudo ln -fs ~nelson/.vimrc /root/
    sudo ln -fs ~nelson/.bashrc /root/
    sudo ln -fs ~nelson/.bash_additions /root/
    sudo ln -fs ~nelson/.bash_aliases /root/
    sudo ln -fs ~nelson/.bash_functions /root/
    sudo ln -fs ~nelson/bin /root/
}



cache_passwds
pkgs
no_tear
power_settings
hybrid_suspend
ssh_keep_awake
ssh_motd
crontabs
user
git_ssh_key
root
