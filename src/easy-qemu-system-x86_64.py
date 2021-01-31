#!/usr/bin/env python3

import hashlib
import logging
import os
import random
import re
import shutil
import subprocess
import sys

MESSAGE_LOG_LEVEL = 25


def log_message(self, message, *args, **kwargs):
    if self.isEnabledFor(MESSAGE_LOG_LEVEL):
        self._log(MESSAGE_LOG_LEVEL, message, args, **kwargs)


logging.addLevelName(MESSAGE_LOG_LEVEL, "MESSAGE")
logging.Logger.message = log_message
logging.basicConfig(level=os.environ.get("LOGLEVEL", "MESSAGE"), format="%(asctime)s | %(levelname)s | %(message)s")

logger = logging.getLogger(__name__)


def exec(args, *, check=True, **kwargs):
    logger.info(" ".join(args))
    return subprocess.run(args, check=check, **kwargs)


def idgen(seed):
    return hashlib.sha256(seed.encode()).hexdigest()[:8]


def macro_runtime(env=True):
    return (True, env["runtime"], []) if "runtime" in env else (False, None, [])


def macro_id(name, inc=None, init=None, env=None):
    inc = 0 if inc is None else int(inc)
    init = 0 if init is None else int(init)
    current = env[name] if name in env else init
    env[name] = current + inc
    return True, "{}{}".format(name, current), []


def macro_br(cidr, env=None):
    if "networks" not in env:
        env["networks"] = {}

    br = "br-" + idgen(cidr)
    env["networks"][br] = cidr
    return True, br, []


def macro_snap(hdd, env=None):
    if "id" not in env:
        return False, None, []

    if "snapshots" not in env:
        env["snapshots"] = {}

    snapshot, ext = os.path.splitext(hdd)
    snapshot += "-{}{}".format(idgen(hdd + env["id"]), ext)
    env["snapshots"][hdd] = snapshot
    return True, snapshot, []


def macro_cpu(cores=None, threads=None, sockets=None, env=None):
    cores = 2 if cores is None else int(cores)
    threads = 1 if threads is None else int(threads)
    sockets = 1 if sockets is None else int(sockets)
    return True, "", ["-smp", "{},sockets={},cores={},threads={}".format(cores * threads * sockets, cores, threads, sockets)]


def macro_mac(env=None):
    if "id" not in env:
        return False, None, []

    if "macgen" not in env:
        env["macgen"] = random.Random(env["id"])

    macgen = env["macgen"]
    return True, "02:00:00:{:02X}:{:02X}:{:02X}".format(macgen.randint(0, 255), macgen.randint(0, 255), macgen.randint(0, 255)), []


def macro_hdd(file, env=None):
    return (
        True,
        "",
        [
            "-blockdev",
            "qcow2,node-name={{id,block}},file.driver=file,file.filename={}".format(file),
            "-device",
            "virtio-blk-pci,drive={id,block,1},{id,bootindex=,1}",
        ],
    )


def macro_net(cidr, env=None):
    return (
        True,
        "",
        [
            "-netdev",
            "bridge,id={{id,net}},br={{br,{}}}".format(cidr),
            "-device",
            "virtio-net-pci,netdev={id,net,1},mac={mac}",
        ],
    )


def macro_cd(iso, env=None):
    return (
        True,
        "",
        [
            "-drive",
            "id={{id,drive}},if=none,format=raw,file={}".format(iso),
            "-device",
            "ide-cd,drive={id,drive,1},bus={id,ide.,1,1},{id,bootindex=,1}",
        ],
    )


def macro_serial(env=None):
    if "runtime" not in env:
        return False, None, []

    if "serials" not in env:
        env["serials"] = 0
    else:
        env["serials"] += 1

    serial = "{}/serial-{}.sock".format(env["runtime"], env["serials"])
    logger.message("minicom -D unix#%s", serial)

    return (
        True,
        "",
        [
            "-chardev",
            "socket,id={{id,char}},path={},server,nowait".format(serial),
            "-device",
            "isa-serial,chardev={id,char,1}",
        ],
    )


def macro_monitor(env=None):
    if "runtime" not in env:
        return False, None, []

    if "monitor" in env:
        return True, "", []

    env["monitor"] = True
    monitor = "{}/monitor.sock".format(env["runtime"])
    logger.message("minicom -D unix#%s", monitor)

    return (
        True,
        "",
        [
            "-chardev",
            "socket,id={{id,char}},path={},server,nowait".format(monitor),
            "-mon",
            "chardev={id,char,1}",
        ],
    )


def macro_video(driver=None, env=None):
    if "runtime" not in env and driver == "qxl":
        return False, None, []

    if "video" in env:
        return True, "", []

    env["video"] = True

    if driver in ["vga", "virtio", "qxl"]:
        args = [
            "-device",
            "ich9-usb-ehci1,id=usb",
            "-device",
            "ich9-usb-uhci1,masterbus=usb.0,firstport=0,multifunction=on",
            "-device",
            "ich9-usb-uhci2,masterbus=usb.0,firstport=2",
            "-device",
            "ich9-usb-uhci3,masterbus=usb.0,firstport=4",
            "-device",
            "usb-tablet",
        ]
        if driver == "vga":
            args.extend(["-device", "VGA,vgamem_mb=64"])
        elif driver == "virtio":
            args.extend(["-device", "virtio-gpu-pci"])
        else:
            display = "{}/display.sock".format(env["runtime"])
            logger.message("spicy --uri=spice+unix://%s --title=%s", display, env["name"])
            logger.message("Shift+F12 - exit fullscreen")
            args.extend(
                [
                    "-device",
                    "qxl-vga,vgamem_mb=64,max_outputs=1",
                    "-spice",
                    "addr={},unix,disable-ticketing,image-compression=off,seamless-migration=on".format(display),
                    "-chardev",
                    "spicevmc,id={id,char},debug=0,name=vdagent",
                    "-device",
                    "virtio-serial-pci",
                    "-device",
                    "virtserialport,chardev={id,char,1},name=com.redhat.spice.0",
                    "-chardev",
                    "spicevmc,id={id,char},debug=0,name=usbredir",
                    "-device",
                    "usb-redir,chardev={id,char,1}",
                    "-chardev",
                    "spicevmc,id={id,char},debug=0,name=usbredir",
                    "-device",
                    "usb-redir,chardev={id,char,1}",
                    "-chardev",
                    "spicevmc,id={id,char},debug=0,name=usbredir",
                    "-device",
                    "usb-redir,chardev={id,char,1}",
                ]
            )

        return True, "", args
    else:
        return True, "-nographic", []


def macro_defaults(env=None):
    return (
        True,
        "",
        [
            "-cpu",
            "host",
            "-boot",
            "order=cd,menu=on",
            "-nodefaults",
            "-no-user-config",
            "-no-hpet",
            "-machine",
            "q35,accel=kvm,vmport=off,dump-guest-core=off",
            "-object",
            "rng-random,id={id,obj},filename=/dev/urandom",
            "-device",
            "virtio-rng-pci,rng={id,obj,1}",
            "-device",
            "virtio-balloon-pci",
            "-pidfile",
            "{runtime}/process.pid",
            "-daemonize",
            "-k",
            "pt",
        ],
    )


def process(index, arg, env):
    if index == 0:
        prefix = "easy-"
        executable = os.path.basename(arg)
        if executable.startswith(prefix):
            executable, _ = os.path.splitext(executable[len(prefix) :])
            return True, [shutil.which(executable), executable]

    if arg == "-name" and "id" not in env:
        env["capture_id"] = True
        return False, [arg]

    if "capture_id" in env and env["capture_id"]:
        env["name"] = arg
        env["id"] = idgen(arg)
        env["runtime"] = "/var/run/qemu-{}".format(env["id"])
        del env["capture_id"]
        return True, [arg]

    matches = env["matcher"].findall(arg)

    if len(matches):
        parts = env["matcher"].split(arg)
        changed = False
        newargs = [""]

        for match in matches:
            fields = env["unwrapper"](match)
            macro = env["macros"][fields[0]]
            macroargs = [None if f == "" else f for f in fields[1:]]
            c, r, a = macro(*macroargs, env=env)
            changed = changed or c
            newargs[0] += parts.pop(0) + (match if r is None else r)
            newargs.extend(a)

            if c:
                logger.debug("macro %s -> %s, %s", match, r, a)

        newargs[0] += parts.pop(0)

        if newargs[0] == "":
            newargs.pop(0)

        return changed, newargs

    return False, [arg]


def prepare(env):
    os.makedirs(env["runtime"], exist_ok=True)

    if "networks" in env:
        with open("/proc/self/net/route", "r") as route_fd:
            gw = next(line[0] for line in map(str.split, iter(route_fd.readline, "")) if line[1] == "00000000")

        for br, cidr in env["networks"].items():
            try:
                exec(["brctl", "addbr", br], capture_output=True)
            except subprocess.CalledProcessError as exc:
                err = exc.stderr.decode().strip()
                if err.startswith("device {} already exists".format(br)):
                    continue

                logger.error(err)
                raise

            exec(["ip", "addr", "add", cidr, "dev", br])
            exec(["ip", "link", "set", br, "up"])
            exec(["iptables", "-t", "nat", "-A", "POSTROUTING", "-s", cidr, "-o", gw, "-j", "MASQUERADE"])
            exec(["iptables", "-A", "FORWARD", "-i", br, "-j", "ACCEPT"])
            exec(["iptables", "-A", "FORWARD", "-i", gw, "-o", br, "-m", "conntrack", "--ctstate", "ESTABLISHED,RELATED", "-j", "ACCEPT"])

    if "snapshots" in env:
        for hdd, snapshot in env["snapshots"].items():
            if not os.path.exists(snapshot):
                exec(["qemu-img", "create", "-f", "qcow2", "-b", hdd, "-F", "qcow2", snapshot])


def qemu_command(args):
    env = {
        "matcher": re.compile(r"{[^{}]+?}"),
        "unwrapper": lambda match: match.lstrip("{").rstrip("}").split(","),
        "macros": {
            "cpu": macro_cpu,
            "runtime": macro_runtime,
            "id": macro_id,
            "br": macro_br,
            "snap": macro_snap,
            "hdd": macro_hdd,
            "mac": macro_mac,
            "net": macro_net,
            "cd": macro_cd,
            "serial": macro_serial,
            "monitor": macro_monitor,
            "video": macro_video,
            "defaults": macro_defaults,
        },
    }

    changed = True

    while changed:
        changed = False
        newagrs = []
        logger.debug("starting pass")

        for index, arg in enumerate(args):
            c, a = process(index, arg, env)
            changed = changed or c
            newagrs.extend(a)

            if c:
                logger.debug("arg %s -> %s", arg, a)

        args = newagrs

    prepare(env)
    logger.info("".join((" \\\n  " if a.startswith("-") else " ") + a for a in args).strip())
    os.execl(*args)


if __name__ == "__main__":
    qemu_command(sys.argv[:])
