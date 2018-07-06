#!/bin/bash

# Weather
w_url='http://rss.accuweather.com/rss/liveweather_rss.asp?metric=2&locCode=NAM|US|MO|LAKE%20SAINT%20LOUIS'
w_sed='/Currently:/ s/.*: (.*): ([0-9]+)F.*/\2F, \1/p'
curl -s "$w_url" | sed -rn "$w_sed" > /etc/update-motd.d/pretty-header-weather.txt

# External ip
if which dig >/dev/null; then
    ext_ip="$(dig +short myip.opendns.com @resolver1.opendns.com)"
else
    ext_ip="$(curl -s 'http://icanhazip.com')"
fi
echo "$ext_ip" > /etc/update-motd.d/pretty-header-ext-ip.txt
