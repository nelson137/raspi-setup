#!/bin/bash

dir="$(dirname "$0")"


# Update, upgrade, and install packages
pkgs() {
    # PPAs
    sudo add-apt-repository -y ppa:nextcloud-devs/client

    # Update and upgrade
    sudo apt update
    sudo apt-get dist-upgrade ||
        sudo apt-get dist-upgrade --fix-missing
    sudo apt upgrade -y

    # Installations
    install() { sudo apt install -y "$@"; }
    install apache2 boxes build-essential cmake dnsutils figlet git \
        html-xml-utils libsecret-tools lolcat nextcloud-client nodejs \
        openssh-server python3-flask python3-pip python3-tk shellinabox \
        solaar tmux upower vim vlc w3m zsh

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


# Use hybrid suspend to wake up quicker
hybrid_suspend() {
    sudo cp "${dir}/files/00-use-suspend-hybrid" /etc/pm/config.d/
}


# Don't suspend while ssh connections are open
# https://askubuntu.com/questions/521620
ssh_keep_awake() {
    sudo cp "${dir}/files/05_ssh-keep-awake" /etc/pm/sleep.d
    sudo chmod +x /etc/pm/sleep.d/05_ssh-keep-awake
}


# Clean up SSH MOTD
ssh_motd() {
    # Disable motd-news in config file
    sudo sed -i '/^ENABLED/ s/1/0/' /etc/default/motd-news

    # Add extra newline before and after Welcome line
    header_regex='s:(Welcome to %s \(%s %s %s\)):\\n\1\\n:'
    sudo cat /etc/update-motd.d/00-header | grep '%s' | grep -q '\nWelcome' ||
        sudo sed -ri "$header_regex" /etc/update-motd.d/00-header

    # Create 01-pretty-header script
    sudo cp "${dir}/files/01-pretty-header" /etc/update-motd.d/
}


# User and root crontabs
crontabs() {
    # Set crontab editor to vim basic
    cp "${dir}/files/.selected_editor" ~nelson/

    local comments="$(cat "${dir}/files/comments.crontab")"
    local mailto="MAILTO=''"

    # User crontab
    local u_tab='0 5 * * * git -C ~nelson/Projects/Git/dot pull'
    echo -e "${comments}\n\n${mailto}\n\n${u_tab}" | crontab -

    # Root crontab
    sudo cp "${dir}/files/weather.sh" /root/
    sudo chmod +x /root/weather.sh
    local p="'/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'"
    local r_tab='*/10 * * * * /root/weather.sh'
    echo -e "${comments}\n\nPATH=${p}\n${mailto}\n\n${r_tab}" | sudo crontab -
}


# 
user() {
    # User directory
    mkdir -p ~nelson/{Downloads,Projects/Git}
    chown -R nelson:nelson ~nelson
    git clone 'https://github.com/nelson137/dot.git' ~nelson/Projects/Git/dot

    # Git
    cp "${dir}/files/.gitconfig" ~nelson/

    # oh-my-zsh
    local url='https://github.com/robbyrussell/oh-my-zsh.git'
    git --depth=1 "$url" ~nelson/.oh-my-zsh
    sudo chsh -s /usr/bin/zsh nelson

    # Tor
    local url='https://github.com/TheTorProject/gettorbrowser/releases'
    local v="$(curl "${url}/latest" 2>/dev/null | grep -Eo 'v[^"]+')"
    local fn="tor-browser-linux64-$(echo "$v" | tr -d v)_en-US.tar.xz"
    wget "${url}/download/${v}/${fn}"
    tar xJf "$fn" -C ~nelson && rm "$fn"
    mv ~nelson/tor-browser_en-US ~nelson/.tor
    ~nelson/.tor/Browser/start-tor-browser --register-app
}


# Generate a new SSH key, replacing the old Github key with the new one
git_ssh_key() {
    curl_git() {
        local url="https://api.github.com$1"
        shift
        curl -sSLiu "nelson137:$(cat password)" "$@" "$url"
    }

    # Generate SSH key
    yes y | ssh-keygen -t rsa -b 4096 -C 'nelson.earle137@gmail.com' \
        -f ~nelson/.ssh/id_rsa -N ''

    # For each ssh key
    # - get more data about the key
    # - if the key's title is Pi
    #   - delete it and upload the new one
    local -a key_ids=(
        $(curl_git '/users/nelson137/keys' | awk '/^\[/,/^\]/' | jq '.[].id')
    )
    local ssh_key="$(cat ~nelson/.ssh/id_rsa.pub)"
    for id in "${key_ids[@]}"; do
        local json="$(curl_git "/user/keys/$id" | awk '/^\{/,/^\}/')"
        if [[ $(echo "$json" | jq -r '.title') == Pi ]]; then
            curl_git "/user/keys/$id" -X DELETE
            curl_git '/user/keys' -d '{ "title": "Pi", "key": "'"$ssh_key"'" }'
            break
        fi
    done
}


pkgs
hybrid_suspend
ssh_keep_awake
ssh_motd
crontabs
user
git_ssh_key
