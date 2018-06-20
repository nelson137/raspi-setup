#!/bin/bash

dir="$(dirname "$0")/files"


# Make new user
mk_user() {
    sudo useradd nelson -mc 'Nelson Earle' -UG pi,adm,sudo,users
}


# Set new passwords for root, pi, and nelson
set_passwds() {
    local root pi nelson

    read -rp 'New password for root: ' root
    read -rp 'New password for pi: ' pi
    read -rp 'New password for nelson: ' nelson

    echo -e "root:${root}\npi:${pi}\nnelson:${nelson}" | sudo chpasswd
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

    # Installations
    install() { sudo apt install -y "$@"; }
    install apache2 boxes build-essential cmake dnsutils figlet git \
        html-xml-utils lolcat nextcloud-client nodejs openssh-server
        python3-flask python3-pip python3-tk shellinabox solaar upower vim w3m
        zsh

    # youtube-dl
    # Don't install from repositories because they are behind
    local url='https://yt-dl.org/downloads/latest/youtube-dl'
    sudo curl -sSL "$url" -o /usr/local/bin/youtube-dl
    sudo chmod a+rx /usr/local/bin/youtube-dl
}


# System config
system() {
    # Timezone
    sudo timedatectl set-timezone America/Chicago

    # Keyboard layout
    # - Sets keyboard layout to 
    sudo cp "${dir}/keyboard" /etc/default/keyboard

    # Don't autologin
    # - Comments out autologin-user= in /etc/lightdm/lightdm.conf
    sudo sed -ri 's/^(autologin-user=)/#\1/' /etc/lightdm/lightdm.conf

    # Turn off bluetooth on boot
    # - Adds rfkill block command to rc.local to disable bluetooth on boot
    [[ ! -f /etc/rc.local ]] &&
       echo -e "#!/bin/bash\n\nexit 0" | sudo tee /etc/rc.local >/dev/null
    local line_n="$(sudo cat /etc/rc.local | grep -n exit | cut -d: -f1)"
    sudo sed -i "${line_n}i rfkill block bluetooth\n" /etc/rc.local

    # Shellinabox
    # - Adds --disable-ssl and --localhost-only to SHELLINABOX_ARGS
    # - Makes shellinabox css file names more standardized
    # - Enables white-on-black (fg-on-bg) and color-terminal
    # - Restarts shellinabox service
    local old_cwd="$(pwd)"
    local siab_args='--no-beep --disable-ssl --localhost-only'
    sudo sed -i "s/--no-beep/${siab_args}/" /etc/default/shellinabox
    cd /etc/shellinabox/options-enabled
    sudo rm *.css
    cd ../options-available
    sudo mv '00+Black on White.css' '00_black-on-white.css'
    sudo mv '00_White On Black.css' '00+white-on-black.css'
    sudo mv '01+Color Terminal.css' '01+color-terminal.css'
    sudo mv '01_Monochrome.css' '01_monochrome.css'
    cd ../options-enabled
    sudo ln -s '../options-available/00+white-on-black.css' .
    sudo ln -s '../options-available/01+color-terminal.css' .
    sudo systemctl restart shellinabox.service
    cd "$old_cwd"

    # Apache2
    # - Adds another Listen command, below the first one, in ports.conf 
    # - Copies shellinabox.conf into /etc/apache2/sites-available
    # - Enables the proxy and proxy_http modules
    # - Enables shellinabox.conf
    # - Restarts the apache2 service
    local n="$(cat /etc/apache2/ports.conf | grep -n Listen | cut -d: -f1)"
    ((n++))
    sudo sed -i "${n}i Listen 6184"
    sudo cp "${dir}/shellinabox.conf" /etc/apache2/sites-available
    sudo a2enmod proxy proxy_http
    sudo a2ensite shellinabox.conf
    sudo systemctl restart apache2.service
}


# User and root crontabs
crontabs() {
    # Set crontab editor to vim basic
    cp "${dir}/.selected_editor" ~nelson

    local comments="$(cat "${dir}/comments.crontab")"
    local mailto='MAILTO=""'

    # User crontab
    local u_tab='0 5 * * * git -C /home/nelson/Projects/Git/dot pull'
    echo -e "${comments}\n\n${mailto}\n\n${u_tab}" | crontab -

    # Root crontab
    # local p='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
    # local r_tab=''
    # echo -e "${comments}\n\nPATH='${p}'\n${mailto}\n\n${r_tab}" | sudo crontab -
}


ssh_key() {
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
        if [[ $(echo "$json" | jq '.title' | tr -d '"') == Pi ]]; then
            curl_git "/user/keys/$id" -X DELETE
            curl_git '/user/keys' -d '{ "title": "Pi", "key": "'"$ssh_key"'" }'
            break
        fi
    done
}


# User directory and environment
user() {
    # User directory
    mkdir -p ~nelson/{Downloads,Projects/Git}
    chown -R nelson:nelson ~nelson
    git clone 'https://github.com/nelson137/dot.git' ~nelson/Projects/Git/dot

    # Git
    cp "${dir}/.gitconfig" ~nelson

    # oh-my-zsh
    local url='https://github.com/robbyrussell/oh-my-zsh.git'
    git --depth=1 "$url" ~nelson/.oh-my-zsh
    sudo chsh -s /usr/bin/zsh nelson
}


mk_user
set_passwds
pkgs
system
crontabs
ssh_key
user
