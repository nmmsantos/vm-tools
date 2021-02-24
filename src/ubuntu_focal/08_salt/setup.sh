#!/bin/sh

sha1sum -c --status <<EOF
97df80c8339a2c1b59e9ce6441842d28a0d78abd  /lib/systemd/system/salt-master.service
dfd3b7d96910a58c80746d7640908f18791d93b2  /lib/systemd/system/salt-minion.service
EOF

if test $? -eq 0; then
    echo "Nothing to do"
    exit 0
fi

apt-get -y install python3-venv

# libsodium needed for libnacl
apt-get -s install libsodium-dev | awk '{if ($1 == "Inst" && $2 ~ /libsodium[0-9]+/) {print $2}}' | xargs -r apt-get -y install

SALTSTACK_DIR="/srv/saltstack"
BIN_DIR="/usr/local/sbin"
ROOT_DIR="/opt/salt"
VENV_DIR="$ROOT_DIR/.venv"
CONFIG_DIR="$ROOT_DIR/etc/salt"
COMMANDS="salt salt-key salt-master salt-run salt-call salt-minion"

for CMD in $COMMANDS; do
    echo "#!/bin/sh\n\n. \"$VENV_DIR/bin/activate\"\nexec $CMD -c \"$CONFIG_DIR\" \"\$@\"" >"$BIN_DIR/$CMD"
    chmod +x "$BIN_DIR/$CMD"
done

python3 -m venv --system-site-packages "$VENV_DIR"

. "$VENV_DIR/bin/activate"

pip install -U pip
pip install -U pipenv

(
    cd "$ROOT_DIR"
    PIPENV_VERBOSITY=-1 pipenv install salt==3002.2 libnacl docker
)

deactivate

VERSION=$("$BIN_DIR/salt-master" --version | awk '{print $2}')

tee /lib/systemd/system/salt-master.service >/dev/null <<EOF
[Unit]
Description=The Salt Master Server
After=network.target

[Service]
LimitNOFILE=100000
Type=notify
NotifyAccess=all
ExecStart=$BIN_DIR/salt-master

[Install]
WantedBy=multi-user.target
EOF

mkdir -p "$CONFIG_DIR/master.d"
wget -qO "$CONFIG_DIR/master" "https://raw.githubusercontent.com/saltstack/salt/v$VERSION/conf/master"

tee "$CONFIG_DIR/master.d/custom.conf" >/dev/null <<EOF
root_dir: $ROOT_DIR
module_dirs:
  - $SALTSTACK_DIR/salt/ext
file_roots:
  base:
    - $SALTSTACK_DIR/salt/ext
    - $SALTSTACK_DIR/salt/envs/base/states
pillar_roots:
  base:
    - $SALTSTACK_DIR/salt/envs/base/pillar
nacl.config:
  sk_file: $CONFIG_DIR/pki/master/nacl
  pk_file: $CONFIG_DIR/pki/master/nacl.pub
EOF

VERSION=$("$BIN_DIR/salt-minion" --version | awk '{print $2}')

tee /lib/systemd/system/salt-minion.service >/dev/null <<EOF
[Unit]
Description=The Salt Minion
After=network.target salt-master.service

[Service]
KillMode=process
Type=notify
NotifyAccess=all
LimitNOFILE=8192
ExecStart=$BIN_DIR/salt-minion

[Install]
WantedBy=multi-user.target
EOF

mkdir -p "$CONFIG_DIR/minion.d"
wget -qO "$CONFIG_DIR/minion" "https://raw.githubusercontent.com/saltstack/salt/v$VERSION/conf/minion"

tee "$CONFIG_DIR/minion.d/custom.conf" >/dev/null <<EOF
master: 127.0.0.1
root_dir: $ROOT_DIR
id: local
EOF

systemctl enable salt-minion
