#!/bin/bash

if [[ "$EUID" != 0 ]]; then
    echo "Script must be run as root. Try 'sudo $0'" >&2
    exit 1
fi


dl_file() {
    local url='https://raw.githubusercontent.com/nelson137/setup/master'
    eval curl -sS "$url/files/$1" ${2:+>"${2%/}/$1"}
}


# Cache passwords
cache_passwds() {
    read -srp 'Github password: ' GITHUB_PASSWD
    echo
}


# Setup users and groups
users_groups() {
    # Create new user
    useradd nelson -mc 'Nelson Earle' -UG \
        adm,audio,cdrom,dialout,gpio,i2c,netdev,pi,plugdev,spi,sudo,users,video

    # Change root and new users's passwords
    local root_p nelson_p
    read -srp 'New password for root: ' root_p
    echo
    read -srp 'New password for nelson: ' nelson_p
    echo
    echo "root:$root_p\nnelson:$nelson_p" | chpasswd
}


# Update, upgrade, install, and reinstall packages
pkgs() {
    # Update and upgrade
    apt-get update

    # Make sure add-apt-repository is installed
    which add-apt-repository &>/dev/null ||
        apt-get install -y software-properties-common

    # PPAs
    add-apt-repository -y ppa:nextcloud-devs/client

    # Nodejs 8 setup
    curl -sL https://deb.nodesource.com/setup_8.x | bash -

    apt-get purge -y openssh-server

    # Installations
    apt-get install -y apache2 boxes build-essential cmake dnsutils figlet \
        git golang-go html-xml-utils jq libsecret-tools lolcat \
        nextcloud-client nmap nodejs openssh-server phantomjs python3-flask \
        python3-pip shellinabox tmux upower vim w3m zip zsh

    # youtube-dl
    # Don't install from repositories because they are behind
    local url='https://yt-dl.org/downloads/latest/youtube-dl'
    curl -sSL "$url" -o /usr/local/bin/youtube-dl
    chmod a+rx /usr/local/bin/youtube-dl

    # Go installations
    su -c 'go get github.com/ericchiang/pup' nelson

    # Pip installations
    su -c 'python3 -m pip install --upgrade pip' nelson
    su -c '~nelson/.local/bin/pip3 install --user --no-warn-script-location \
        flake8 flake8-docstrings isort pycodestyle' nelson
}


# System config
system() {
    # Timezone
    timedatectl set-timezone America/Chicago

    # Don't autologin
    sed -ri 's/^(autologin-user=)/#\1/' /etc/lightdm/lightdm.conf

    # Disable splash screen on boot
    # - Remove arguments from the boot cmdline
    sed -ri 's/( quiet| splash| plymouth.ignore-serial-consoles)//g' \
        /boot/cmdline.txt

    # Turn off bluetooth on boot
    # - Add rfkill block bluetooth to rc.local
    [[ ! -f /etc/rc.local ]] &&
       echo -e "#!/bin/bash\n\nexit 0" > /etc/rc.local
    local line_n="$(cat /etc/rc.local | grep -n exit | cut -d: -f1)"
    sed -i "${line_n}i rfkill block bluetooth\n" /etc/rc.local

    # Shellinabox
    # - Add --disable-ssl and --localhost-only to SHELLINABOX_ARGS
    # - Make shellinabox css file names more standardized
    # - Enable white-on-black (fg-on-bg) and color-terminal
    # - Restart shellinabox service
    sed -i "s/--no-beep/--no-beep --disable-ssl --localhost-only/" \
        /etc/default/shellinabox
    cd /etc/shellinabox/options-enabled
    rm *.css
    cd ../options-available
    mv '00+Black on White.css' '00_black-on-white.css'
    mv '00_White On Black.css' '00+white-on-black.css'
    mv '01+Color Terminal.css' '01+color-terminal.css'
    mv '01_Monochrome.css' '01_monochrome.css'
    cd ../options-enabled
    ln -s '../options-available/00+white-on-black.css' .
    ln -s '../options-available/01+color-terminal.css' .
    systemctl restart shellinabox.service

    # Apache2
    # - Add another Listen command (below the first one) in ports.conf
    # - Copy shellinabox.conf to /etc/apache2/sites-available/
    # - Enable the proxy and proxy_http modules
    # - Enable shellinabox.conf
    # - Restart the apache2 service
    local n="$(cat /etc/apache2/ports.conf | grep -n Listen | cut -d: -f1)"
    ((n++))
    sed -i "${n}i Listen 6184"
    dl_file shellinabox.conf /etc/apache2/sites-available/
    a2enmod proxy proxy_http
    a2ensite shellinabox.conf
    systemctl restart apache2.service
}


# User and root crontabs
crontabs() {
    # Set crontab editor to vim basic
    dl_file .selected_editor ~nelson/

    local comments="$(dl_file comments.crontab)"
    local mailto="MAILTO=''"

    # User crontab
    local dot="dot='-C ~/.dot'"
    local u_tab='0 5 * * * [[ $(git $dot status -s) ]] || git $dot pull'
    echo -e "${comments}\n\n${mailto}\n\n${dot}\n${u_tab}" |
        su -c 'crontab -' nelson

    # Root crontab
    dl_file pretty-header-data.sh /root/
    chmod +x /root/pretty-header-data.sh
    local p="'/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'"
    local r_tab='*/10 * * * * /root/pretty-header-data.sh'
    echo -e "${comments}\n\nPATH=${p}\n${mailto}\n\n${r_tab}" | crontab -
}


# User directory and environment
user() {
    # User directory
    mkdir -p ~nelson/{Downloads,Projects/.ssh}
    git clone 'https://github.com/nelson137/.dot.git' ~nelson/.dot

    # git
    # - Copy .gitconfig to ~nelson/
    # - Copy /usr/share/git-core/templates/ to ~nelson/.git_templates/
    # - Copy commit-msg to ~nelson/.git_templates/
    dl_file .gitconfig ~nelson/
    cp -r /usr/share/git-core/templates/ ~nelson/.git_templates/
    dl_file commit-msg ~nelson/.git_templates/hooks/
    chmod a+x ~nelson/.git_templates/hooks/commit-msg

    # Oh My Zsh
    local url='https://github.com/robbyrussell/oh-my-zsh.git'
    git clone --depth=1 "$url" ~nelson/.oh-my-zsh
    chsh nelson -s /usr/bin/zsh

    # LXPanel
    # - Remove widgets from the lxpanel
    # - Remove cached menu items so updates will appear
    # - Restart lxpanel
    dl_file panel ~nelson/.config/lxpanel/LXDE-pi/panels/
    killall lxpanel
    find ~nelson/.cache/menus -type f -name '*' -print0 | xargs -0 rm
    nohup lxpanel -p LXDE-pi &>/dev/null & disown

    # LXTerminal
    # - Use the xterm color palette
    # - Cursor blinks
    # - Hide scroll bar
    local conf_file=~nelson/.config/lxterminal/lxterminal.conf
    sed -i '/^color_preset=/ s/VGA/xterm/; /^cursorblinks=/ s/false/true/' \
        "$conf_file"
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
    local email='nelson.earle137@gmail.com'
    local cmd="ssh-keygen -t rsa -b 4096 -C '$email' -f ~nelson/.ssh/id_rsa \
        -N ''"
    echo y | su -c "$cmd" nelson

    # Find the old Pi SSH key, delete it, upload the new one
    local -a key_ids=(
        $(curl_git '/users/nelson137/keys' | awk '/^\[/,/^\]/' | jq '.[].id')
    )
    local ssh_key="$(cat ~nelson/.ssh/id_rsa.pub)"
    for id in "${key_ids[@]}"; do
        local json="$(curl_git "/user/keys/$id" | awk '/^\{/,/^\}/')"
        if [[ "$(jq -r '.title' <<< "$json")" == Pi ]]; then
            curl_git "/user/keys/$id" -X DELETE
            curl_git '/user/keys' -d '{ "title": "Pi", "key": "'"$ssh_key"'" }'
            break
        fi
    done
}


cleanup() {
    # Make sure all files and directories in ~nelson are owned by nelson
    chown -R nelson:nelson ~nelson/
}


cache_passwds
users_groups
pkgs
system
crontabs
user
git_ssh_key
cleanup
