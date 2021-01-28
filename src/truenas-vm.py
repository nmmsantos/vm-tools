#!/usr/bin/env python3.8

from configparser import ConfigParser, ExtendedInterpolation
from json import dumps, load
from logging import INFO, WARNING, basicConfig, getLogger
from os import environ, execl, makedirs
from os.path import dirname, realpath
from pathlib import Path
from random import randint
from shutil import which
from subprocess import DEVNULL, CalledProcessError, run
from sys import exit as sys_exit
from sys import stderr
from tempfile import NamedTemporaryFile
from textwrap import dedent
from urllib.error import HTTPError
from urllib.request import Request, urlopen


def config(default):
    parser = ConfigParser(interpolation=ExtendedInterpolation())

    with NamedTemporaryFile(mode="w+", prefix="truenas-vm-", suffix=".ini") as config_file:
        config_file.write(dedent(default).strip())
        config_file.flush()
        run(["nano", config_file.name], check=True)
        parser.read(config_file.name)

    return parser


CONFIG = config(
    """
    [VM]
    ;name = ubuntu
    ip = 10.0.0.
    hostname = ${{name}}
    # Memory in MiB
    memory = 2048
    # HDD size in GiB
    hdd_size = 10
    cores = 2
    vcpus = 1
    threads = 1
    nic = lagg0
    mac = {mac}
    netmask = 24
    gateway = 10.0.0.1
    domain = juenuno.com
    dns = 10.0.0.2
    minion_id = ${{hostname}}
    salt_master_ip = 10.0.0.62
    autostart = yes
    # Options for bootloader: UEFI | UEFI_CSM
    bootloader = UEFI
    # Timeout in seconds
    shutdown_timeout = 90
    hdd_template = ${{App:cwd}}/hdd-template.qcow2
    dataset = ${{TrueNAS:base_dataset}}/${{name}}-hdd
    ssh_key = {ssh_key}

    [TrueNAS]
    host = 127.0.0.1
    key = 1-DEHN3UxEomg9jN1hOlrnjEBWeX3iHSZLNFUTmpdOEopAENUU6ch9HCEXoYsJbEAr
    base_dataset = nvme-r0-pool/vms

    [App]
    debug = no
    cwd = {cwd}
    root = ${{cwd}}/root
    qemu_img_path = ${{cwd}}/qemu-img
    bootstrap_script = ${{cwd}}/vm-bootstrap.sh
    """.format(
        cwd=dirname(realpath(__file__)),
        mac="02:00:00:{:02X}:{:02X}:{:02X}".format(randint(0, 255), randint(0, 255), randint(0, 255)),
        ssh_key="".join(
            [
                "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDT2l7FkBAZeZHDhB7AwT+Vx6pKjIVBe2fgaMb6x3yoi2iwRsxygnDnkX5CrVsSE8jhUqoZ8k75U4TJyKNim",
                "Co+9LdIiDjxwOrRPAXjxEbyvfrISlpdoyOZsRbU/wguXvp7Wa2PEgoQFZa8reetOX8hhgVviO5LTZkZkJxUcrdNkxLJ/GeyYTDadt5OnbfuqYcNLmgt1C96fX",
                "W0oZaV/bB5WAA5mLEEzS9FH5jxKI4xLQNBSM3vzVJ2sPLbZ/vHhvthl3/NiSVBXjnX+OA1wEw5+dNs+1eNJCTRt8ba6ye2mCGmpIxsq3nNJkOIf/SYqeELN8l",
                "AKejlU36SVZ31/ZvqCWlChhoaTJ0Ck022Pgkbr8miP2kH1LgmNNide5rgF5i+TlFBJg6i7gpudeXqxu0eVtHDueT3615o8c1thStK4vZF+zRlbUoHj/ciLGnU",
                "+ZpoAbuwK7HE235bITKcuBJ235Jb5aNd5oUnqQqU4+z249ts9KQYmDbxfVf4cgLB0ZUriJjYZBkTNgaBLkVbwWUuYX8pErgcep3zkUzw+alVVLYvbYPMlFvS5",
                "BiE2HRHy7JPBQtOqA2RuFsH6/sqEPNqSMwGLvjwIvwvP5PmHPJOOi8Nz3YxpsfWB+pupVL1xE/3ZtTa17CCrOguEsfK0VDDuXy3xIi9cnt4hJ+yP8+TLw==",
            ]
        ),
    )
)

VM_NAME = CONFIG.get("VM", "name")
IP = CONFIG.get("VM", "ip")
HOSTNAME = CONFIG.get("VM", "hostname")
MEMORY = CONFIG.getint("VM", "memory")
HDD_SIZE = CONFIG.getint("VM", "hdd_size") * 1073741824  # multiple of 16k = 16384
CORES = CONFIG.getint("VM", "cores")
VCPUS = CONFIG.getint("VM", "vcpus")
THREADS = CONFIG.getint("VM", "threads")
NIC = CONFIG.get("VM", "nic")
MAC = CONFIG.get("VM", "mac")
NETMASK = CONFIG.getint("VM", "netmask")
GATEWAY = CONFIG.get("VM", "gateway")
DOMAIN = CONFIG.get("VM", "domain")
DNS = CONFIG.get("VM", "dns")
MINION_ID = CONFIG.get("VM", "minion_id")
SALT_MASTER_IP = CONFIG.get("VM", "salt_master_ip")
AUTOSTART = CONFIG.getboolean("VM", "autostart")
BOOTLOADER = CONFIG.get("VM", "bootloader")
SHUTDOWN_TIMEOUT = CONFIG.getint("VM", "shutdown_timeout")
HDD_TEMPLATE = CONFIG.get("VM", "hdd_template")
DATASET = CONFIG.get("VM", "dataset")
SSH_KEY = CONFIG.get("VM", "ssh_key")
HOST = CONFIG.get("TrueNAS", "host")
KEY = CONFIG.get("TrueNAS", "key")
DEBUG = CONFIG.getboolean("App", "debug")
CWD = CONFIG.get("App", "cwd")
ROOT = CONFIG.get("App", "root")
QEMU_IMG_PATH = CONFIG.get("App", "qemu_img_path")
BOOTSTRAP_SCRIPT = CONFIG.get("App", "bootstrap_script")

LOGGER = getLogger(__name__)
basicConfig(level=INFO if DEBUG else WARNING, format="%(asctime)s | %(levelname)s | %(message)s")


def request(method, path, body=None):
    url = "http://{}/api/v2.0{}".format(HOST, path)
    data = None
    headers = {"Authorization": "Bearer {}".format(KEY), "Accept": "application/json"}

    if method == "POST":
        data = dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json; charset=utf-8"
        headers["Content-Length"] = len(data)

    LOGGER.info("%s %s", method, url)
    LOGGER.info("%s", headers)
    LOGGER.info("%s", data)

    req = Request(url, data=data, headers=headers, method=method)

    try:
        rsp = urlopen(req)
    except HTTPError as err:
        LOGGER.warning("%s %s", err.code, err.reason)
        raise

    with rsp as f:
        obj = load(f)
        LOGGER.info("%s %s", rsp.status, rsp.reason)
        LOGGER.info("%s", obj)
        return rsp.status, obj


def exit_error(message):
    print(message, file=stderr)
    sys_exit(1)


def qemu_img(args, **kwargs):
    default_env = {**environ}
    default_env["LD_LIBRARY_PATH"] = QEMU_IMG_PATH + (":" + default_env["LD_LIBRARY_PATH"] if "LD_LIBRARY_PATH" in default_env else "")
    env = kwargs.pop("env", default_env)
    return run(["{}/qemu-img".format(QEMU_IMG_PATH)] + args, env=env, **kwargs)


try:
    qemu_img(["--version"], stdout=DEVNULL, stderr=DEVNULL, check=True)
except (OSError, CalledProcessError):
    exit_error(
        dedent(
            """
            Command qemu-img is not functional.
            Create a jail with the latest TrueNAS version, and execute the following commands:
                pkg install qemu
                mkdir qemu-img
                cp `which qemu-img` ./qemu-img/
                ldd -av ./qemu-img/qemu-img | awk 'NF == 4 {{print $3}}' | sort -u | xargs -I% cp "%" ./qemu-img/
                tar cvzf qemu-img.tgz qemu-img

            Now, copy the qemu-img.tgz and extract it to {cwd}. You are free to destroy the jail.
            """.format(
                cwd=CWD
            )
        ).strip()
    )

# request("GET", "/vm")
# request("GET", "/vm/device")

_, VM = request(
    "POST",
    "/vm",
    {
        "name": VM_NAME,
        "description": "",
        "vcpus": VCPUS,
        "cores": CORES,
        "threads": THREADS,
        "memory": MEMORY,
        "autostart": AUTOSTART,
        "time": "LOCAL",
        "grubconfig": None,
        "bootloader": BOOTLOADER,
        "shutdown_timeout": SHUTDOWN_TIMEOUT,
        "devices": [
            {"dtype": "NIC", "attributes": {"type": "VIRTIO", "mac": MAC, "nic_attach": NIC}},
            {"dtype": "DISK", "attributes": {"create_zvol": True, "type": "VIRTIO", "zvol_name": DATASET, "zvol_volsize": HDD_SIZE}},
        ],
    },
)


ZVOL = next(d for d in VM["devices"] if d["dtype"] == "DISK")["attributes"]["path"]

run(["zfs", "set", "volmode=geom", DATASET], check=True)

qemu_img(["convert", "-O", "raw", HDD_TEMPLATE, ZVOL], check=True)

if DEBUG:
    run(["gpart", "show", ZVOL])

PARTITION = "{}p1".format(ZVOL)

makedirs(ROOT, exist_ok=True)

run(["mount_msdosfs", PARTITION, ROOT], check=True)

Path("{}/vm-bootstrap.sh".format(ROOT)).write_text(
    Path(BOOTSTRAP_SCRIPT)
    .read_text()
    .format(
        ip=IP,
        netmask=NETMASK,
        gateway=GATEWAY,
        domain=DOMAIN,
        dns=DNS,
        hostname=HOSTNAME,
        ssh_key=SSH_KEY,
        salt_master_ip=SALT_MASTER_IP,
        minion_id=MINION_ID,
    )
)

run(["umount", ROOT], check=True)

run(["zfs", "inherit", "volmode", DATASET], check=True)

_, STATUS = request("POST", "/vm/id/{}/start".format(VM["id"]), {"overcommit": True})

_, CONSOLE = request("POST", "/vm/get_console", VM["id"])

if DEBUG:
    print("To connect to the VM console: cu -l {} -s 9600, to exit press: ~~ ^d".format(CONSOLE))
else:
    print("Connecting to the VM console console, to exit press: ~~ ^d")
    execl(which("cu"), "cu", "-l", CONSOLE, "-s", "9600")


# pkg install fusefs-lkl
# kldload fuse.ko
# kldstat
# kldunload fuse.ko
# lklfuse -o type=ext4 /dev/zvol/slow/vms/ubuntu-hdd /mnt

# Documentation
# /usr/local/lib/python3.8/site-packages/middlewared/plugins/vm.py
#
# sudo sshfs root@10.0.0.77:/root/truenas-vm truenas-vm -o allow_other,reconnect,follow_symlinks
