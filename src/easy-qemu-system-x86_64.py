#!/usr/bin/env python3

import hashlib
import logging
import os
import re
import shutil
import subprocess
import sys


def exec(args, *, check=True, **kwargs):
    result = subprocess.run(args, check=check, **kwargs)
    LOG.info("Executed: %s", " ".join(args))
    return result


def getLogger(name, level):
    class IndentFormatter(logging.Formatter):
        def format(self, record):
            return super().format(record).replace("\n", "\n" + " " * 33 + "| ")

    handler = logging.StreamHandler()
    handler.setFormatter(IndentFormatter("{asctime} {levelname:>8s} | {message}", style="{"))
    logger = logging.getLogger(name)
    logger.setLevel(level)
    logger.addHandler(handler)
    return logger


def idgen(seed):
    return hashlib.sha256(seed.encode()).hexdigest()[:8]


def macgen(seed):
    id = idgen(seed)
    return "02:00:" + ":".join([id[i : i + 2] for i in range(0, len(id), 2)])


def macro_br(cidr, env=None):
    if "networks" not in env:
        env["networks"] = {}

    br = "br-" + idgen(cidr)
    mac = macgen(cidr)
    env["networks"][br] = cidr, mac
    return (br,)


def macro_cd(iso, env=None):
    return (
        "-drive",
        "id={{id,drive}},if=none,format=raw,file={}".format(iso),
        "-device",
        "ide-cd,drive={id,drive,1},bus={id,ide.,1,1},{id,bootindex=,1}",
    )


def macro_cpu(cores=None, threads=None, sockets=None, env=None):
    cores = 2 if cores is None else int(cores)
    threads = 1 if threads is None else int(threads)
    sockets = 1 if sockets is None else int(sockets)
    return "-smp", "{},sockets={},cores={},threads={}".format(cores * threads * sockets, cores, threads, sockets)


def macro_defaults(env=None):
    return (
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
        "{}/process.pid".format(env["runtime"]),
        "-daemonize",
        "-k",
        "pt",
    )


def macro_hdd(file, size_gb=None, snap=None, env=None):
    if "hdds" not in env:
        env["hdds"] = {}

    size_gb = 20 if size_gb is None else int(size_gb)

    if snap == "snap":
        snap, ext = os.path.splitext(file)
        snap += "-{}{}".format(idgen(file + env["id"]), ext)
    else:
        snap = False

    env["hdds"][file] = (size_gb, snap)

    return (
        "-blockdev",
        "qcow2,node-name={{id,block}},file.driver=file,file.filename={}".format(snap if snap else file),
        "-device",
        "virtio-blk-pci,drive={id,block,1},{id,bootindex=,1}",
    )


def macro_id(name, inc=None, init=None, env=None):
    inc = 0 if inc is None else int(inc)
    init = 0 if init is None else int(init)
    current = env[name] if name in env else init
    env[name] = current + inc
    return ("{}{}".format(name, current),)


def macro_mac(env=None):
    if "macs" not in env:
        env["macs"] = {}

    mac = macgen(env["id"] + str(len(env["macs"])))
    env["macs"][mac] = ()
    return (mac,)


def macro_monitor(env=None):
    if "monitor" in env:
        return ()

    env["monitor"] = True
    monitor = "{}/monitor.sock".format(env["runtime"])
    LOG.info("You can connect to the qemu monitor using: minicom -D unix#%s", monitor)
    return ("-chardev", "socket,id={{id,char}},path={},server,nowait".format(monitor), "-mon", "chardev={id,char,1}")


def macro_net(cidr, env=None):
    if "taps" not in env:
        env["taps"] = {}

    (br,) = macro_br(cidr, env)
    seed = env["id"] + br + str(len(env["taps"]))
    tap = "tap-" + idgen(seed)
    mac = macgen(seed)
    ifup = "/dev/shm/{}.sh".format(tap)
    env["taps"][tap] = br, mac, ifup
    return ("-netdev", "tap,id={{id,net}},ifname={},script={}".format(tap, ifup), "-device", "virtio-net-pci,netdev={id,net,1},mac={mac}")


def macro_runtime(env=True):
    return (env["runtime"],)


def macro_serial(env=None):
    if "serials" not in env:
        env["serials"] = 0
    else:
        env["serials"] += 1

    serial = "{}/serial-{}.sock".format(env["runtime"], env["serials"])
    LOG.info("You can connect to the serial port %d using: minicom -D unix#%s", env["serials"], serial)

    return (
        "-chardev",
        "socket,id={{id,char}},path={},server,nowait".format(serial),
        "-device",
        "isa-serial,chardev={id,char,1}",
    )


def macro_video(driver=None, env=None):
    if "video" in env:
        return ()

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
            LOG.info(
                "You can connect to the display using: spicy --uri=spice+unix://%s --title=%s\nUse Shift+F12 to exit fullscreen",
                display,
                env["name"],
            )
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

        return args
    else:
        return ("-nographic",)


def prepare(env):
    os.makedirs(env["runtime"], exist_ok=True)

    if "networks" in env:
        with open("/proc/self/net/route", "r") as route_fd:
            gw = next(line[0] for line in map(str.split, iter(route_fd.readline, "")) if line[1] == "00000000")

        for br, net in env["networks"].items():
            cidr, mac = net

            try:
                exec(["brctl", "addbr", br], capture_output=True)
            except subprocess.CalledProcessError as exc:
                err = exc.stderr.decode().strip()

                if err.startswith("device {} already exists".format(br)):
                    continue

                raise

            exec(["ip", "addr", "add", cidr, "dev", br])
            exec(["ip", "link", "set", br, "up", "address", mac])
            exec(["iptables", "-t", "nat", "-A", "POSTROUTING", "-s", cidr, "-o", gw, "-j", "MASQUERADE"])
            exec(["iptables", "-A", "FORWARD", "-i", br, "-j", "ACCEPT"])
            exec(["iptables", "-A", "FORWARD", "-i", gw, "-o", br, "-m", "conntrack", "--ctstate", "ESTABLISHED,RELATED", "-j", "ACCEPT"])

    if "taps" in env:
        with open("/etc/qemu-ifup", "r") as ifup_fd:
            ifup_orig = ifup_fd.read()

        switch_matcher = re.compile(r"^switch=.*?\n\n", re.M | re.S)

        for _, tap in env["taps"].items():
            br, mac, ifup = tap
            script = switch_matcher.sub(
                "switch={}\n\n".format(br), ifup_orig.replace('ip link set "$1" up', 'ip link set "$1" up address {}'.format(mac))
            )

            with open(ifup, "w") as ifup_fd:
                ifup_fd.write(script)

            os.chmod(ifup, 0o700)

    if "hdds" in env:
        for file, hdd in env["hdds"].items():
            size_gb, snap = hdd

            if not os.path.exists(file):
                exec(["qemu-img", "create", "-f", "qcow2", file, str(size_gb) + "G"])

            if snap and not os.path.exists(snap):
                exec(["qemu-img", "create", "-f", "qcow2", "-b", file, "-F", "qcow2", snap])


def process_arg0(env, arg):
    prefix = "easy-"
    executable = os.path.basename(arg)

    if executable.startswith(prefix):
        executable, _ = os.path.splitext(executable[len(prefix) :])
        return [shutil.which(executable), executable]
    else:
        return [arg]


def process_args(args: list, env):
    idx = 0

    while True:
        try:
            arg = args[idx]
        except IndexError:
            return

        def handle_output(fn, arg, *macroargs):
            nonlocal idx
            newargs = fn(env, arg, *macroargs)
            if len(newargs) == 0:
                LOG.debug("Argument: %s -> removed", arg)
                del args[idx]
            elif len(newargs) == 1 and newargs[0] == arg:
                idx += 1
            else:
                LOG.debug("Argument: %s -> %s", arg, newargs)
                args[idx : idx + 1] = newargs

        if idx == 0:
            handle_output(process_arg0, arg)
        elif arg == "-name":
            handle_output(process_name, arg, args[idx + 1])
        else:
            handle_output(process_macro, arg)


def process_macro(env, arg):
    match = env["matcher"].search(arg)

    if match is None:
        return [arg]

    macro = match.group(0)
    fields = env["unwrapper"](macro)
    macrofn = env["macros"][fields[0]]
    macroargs = [None if f == "" else f for f in fields[1:]]
    newargs = list(macrofn(*macroargs, env=env))

    if len(newargs):
        LOG.debug("Macro: %s -> %s -> newargs: %s", macro, newargs[0], newargs[1:])
        newargs[0] = arg[: match.start()] + newargs[0] + arg[match.end() :]
    else:
        LOG.debug("Macro: %s -> removed", macro)

    return newargs


def process_name(env, arg, nextarg):
    env["name"] = nextarg
    env["id"] = idgen(nextarg)
    env["runtime"] = "/var/run/qemu-{}".format(env["id"])
    return [arg]


def qemu_command(args):
    env = {
        "matcher": re.compile(r"{[^{}]+?}"),
        "unwrapper": lambda match: match.lstrip("{").rstrip("}").split(","),
        "macros": {
            "cpu": macro_cpu,
            "runtime": macro_runtime,
            "id": macro_id,
            "br": macro_br,
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

    args = args[:]
    process_args(args, env)
    prepare(env)
    LOG.info("QEMU command: %s", "".join((" \\\n  " if a.startswith("-") else " ") + a for a in args).strip())
    os.execl(*args)


if __name__ == "__main__":
    LOG = getLogger(__name__, os.environ.get("LOGLEVEL", "INFO"))

    try:
        qemu_command(sys.argv)
    except Exception as e:
        LOG.error("%s", e)
        LOG.debug("Raised exception:", exc_info=e)
