#!/bin/bash

if [[ "$UID" == 0 ]]; then
    echo 'This script does not need to be run by root' >&2
    exit 1
fi



dl_file() {
    local url='https://raw.githubusercontent.com/nelson137/setup/master'
    eval curl -sS "$url/files/$1" ${2:+>"${2%/}/$1"}
}



dl_file_sudo() {
    local url='https://raw.githubusercontent.com/nelson137/setup/master'
    eval curl -sS "$url/files/$1" | sudo tee "$2/$1" >/dev/null
}



# Cache passwords
cache_passwds() {
    sudo echo >/dev/null
    read -rp 'Github password: ' GITHUB_PASSWD
}



# Update, upgrade, and install packages
pkgs() {
    # Pip installations
    sudo su nelson pip3 install flake8 flake8-docstrings isort pycodestyle

    # Update and upgrade
    sudo apt-get update
    sudo apt-get dist-upgrade ||
        sudo apt-get dist-upgrade --fix-missing
    sudo apt-get upgrade -y

    # Make sure add-apt-repository is installed
    which add-apt-repository >/dev/null ||
        sudo apt-get install -y software-properties-common

    # PPAs
    sudo add-apt-repository -y ppa:nextcloud-devs/client

    # Nodejs 8 setup
    curl -sL https://deb.nodesource.com/setup_8.x | sudo bash -

    # Installations
    sudo apt-get install -y boxes build-essential cmake dnsutils figlet git \
        html-xml-utils jq libsecret-tools lolcat nmap nodejs openssh-server \
        phantomjs pylint python3-pip python3-tk tmux vim zsh

    # Manually install youtube-dl because the repositories might be behind
    local url='https://yt-dl.org/downloads/latest/youtube-dl'
    sudo curl -sSL "$url" -o /usr/local/bin/youtube-dl
    sudo chmod a+rx /usr/local/bin/youtube-dl

    # Install figlet font files
    local -a fonts=(banner3 colossal nancyj roman univers)
    for f in "${fonts[@]}"; do
        if [[ ! -e /usr/share/figlet/${f}.flf ]]; then
            sudo curl -sS "http://www.figlet.org/fonts/${f}.flf" \
                -o "/usr/share/figlet/${f}.flf"
        fi
    done
}



# Clean up SSH MOTD
ssh_motd() {
    # Disable motd-news in config file
    sudo sed -i '/^ENABLED/ s/1/0/' /etc/default/motd-news

    # Disable welcome message
    sudo sed -ri 's/^(printf)/# \1/' /etc/update-motd.d/00-header

    dl_file_sudo 01-pretty-header /etc/update-motd.d/

    # Apply /etc/update-motd.d changes
    sudo run-parts /etc/update-motd.d/

    # Disable last login message
    sudo sed -ri 's/^\s*#?\s*(PrintLastLog).*$/\1 no/' /etc/ssh/sshd_config
    sudo systemctl restart sshd.service

    # pretty-header-data.sh setup in "Root crontabs" in crontabs()
}



# User directory and environment
user() {
    # File structure
    mkdir -p ~nelson/{Downloads,Projects}
    git clone 'https://github.com/nelson137/dot.git' ~nelson/.dot

    # Config files
    local conf_files=(.vimrc .tmux.conf .zshrc .bashrc .bash_additions)
    for cf in "${conf_files[@]}"; do
        ln -fs ~nelson/.dot/files/"$cf" ~nelson/
    done

    # git
    # - Copy .gitconfig to ~nelson/
    # - Copy /usr/share/git-core/templates/ to ~nelson/.git_templates/
    # - Copy commit-msg to ~nelson/.git_templates/
    dl_file .gitconfig ~nelson/
    sudo cp -r /usr/share/git-core/templates/ ~nelson/.git_templates/
    sudo chown -R nelson:nelson ~nelson/.git_templates/
    dl_file commit-msg ~nelson/.git_templates/hooks/
    chmod a+x ~nelson/.git_templates/hooks/commit-msg

    # Oh My Zsh
    local url='https://github.com/robbyrussell/oh-my-zsh.git'
    git clone --depth=1 "$url" ~nelson/.oh-my-zsh
    sudo chsh -s /usr/bin/zsh nelson
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

    # Find the old WSL SSH key, delete it, upload the new one
    local -a key_ids=(
        $(curl_git '/users/nelson137/keys' | awk '/^\[/,/^\]/' | jq '.[].id')
    )
    local ssh_key="$(cat ~nelson/.ssh/id_rsa.pub)"
    for id in "${key_ids[@]}"; do
        local json="$(curl_git "/user/keys/$id" | awk '/^\{/,/^\}/')"
        if [[ $(echo "$json" | jq -r '.title') == WSL ]]; then
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
ssh_motd
user
git_ssh_key
root
