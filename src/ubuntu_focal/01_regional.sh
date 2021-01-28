#!/bin/sh

export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C
export LANGUAGE=C
export LANG=C

sha1sum -c --status <<EOF
6f465d7781d0f410a92976e970db8efc47ff7a43  /var/lib/locales/supported.d/en
230afb3aab291d2f630aeb60066ac63a905f4032  /var/lib/locales/supported.d/pt
08eba982affa83b7c859b9efc2ecc6f7c3694902  /etc/default/locale
EOF

if test $? -eq 0; then
    echo "Nothing to do"
    exit 0
fi

mkdir -p /var/lib/locales/supported.d

rm -rfv /usr/lib/locale/* /var/lib/locales/supported.d/*

tee /var/lib/locales/supported.d/en >/dev/null <<EOF
en_US.UTF-8 UTF-8
EOF

tee /var/lib/locales/supported.d/pt >/dev/null <<EOF
pt_PT.UTF-8 UTF-8
EOF

locale-gen

tee /etc/default/locale >/dev/null <<EOF
LANG=en_US.UTF-8
LANGUAGE=en
LC_CTYPE=pt_PT.UTF-8
LC_NUMERIC=pt_PT.UTF-8
LC_TIME=pt_PT.UTF-8
LC_COLLATE=pt_PT.UTF-8
LC_MONETARY=pt_PT.UTF-8
LC_MESSAGES=en_US.UTF-8
LC_PAPER=pt_PT.UTF-8
LC_NAME=pt_PT.UTF-8
LC_ADDRESS=pt_PT.UTF-8
LC_TELEPHONE=pt_PT.UTF-8
LC_MEASUREMENT=pt_PT.UTF-8
LC_IDENTIFICATION=pt_PT.UTF-8
EOF

ln -sfn /usr/share/zoneinfo/Europe/Lisbon /etc/localtime
