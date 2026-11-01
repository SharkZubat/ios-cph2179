#!/usr/bin/env python3
"""Capture a CDC ACM port as raw bytes, configuring it without reopening it."""
import argparse
import errno
import fcntl
import os
from pathlib import Path
import select
import struct
import sys
import termios
import time
import tty


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("device", help="CDC ACM node, e.g. /dev/ttyACM0")
    parser.add_argument("output", type=Path)
    parser.add_argument("--seconds", type=float, default=25)
    parser.add_argument("--wait", type=float, default=0,
                        help="seconds to wait for the device node")
    args = parser.parse_args()

    deadline = time.monotonic() + args.wait
    total = 0
    with args.output.open("wb") as output:
        while True:
            try:
                fd = os.open(args.device,
                             os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
                break
            except OSError as exc:
                if (exc.errno not in (errno.ENOENT, errno.ENXIO) or
                        time.monotonic() >= deadline):
                    raise
                time.sleep(0.05)

        old_attrs = termios.tcgetattr(fd)
        try:
            # Opening a CDC ACM tty asserts modem control lines. Drop DTR
            # while setting raw mode, then assert it with the capture file
            # already open and ready to receive bytes.
            try:
                fcntl.ioctl(fd, termios.TIOCMBIC,
                            struct.pack("I", termios.TIOCM_DTR))
            except (OSError, termios.error):
                pass
            tty.setraw(fd, termios.TCSANOW)
            try:
                fcntl.ioctl(fd, termios.TIOCMBIS,
                            struct.pack("I", termios.TIOCM_DTR))
            except (OSError, termios.error):
                pass

            stop = time.monotonic() + args.seconds
            poller = select.poll()
            poller.register(fd, select.POLLIN | select.POLLHUP | select.POLLERR)
            while time.monotonic() < stop:
                timeout_ms = max(1, min(200,
                    int((stop - time.monotonic()) * 1000)))
                events = poller.poll(timeout_ms)
                if not events:
                    continue
                flags = events[0][1]
                if flags & select.POLLIN:
                    try:
                        data = os.read(fd, 4096)
                    except BlockingIOError:
                        data = None
                    if data:
                        output.write(data)
                        total += len(data)
                    elif not flags & (select.POLLHUP | select.POLLERR):
                        # Some CDC drivers report a transient empty read.
                        # Keep waiting while the device remains connected.
                        continue
                if flags & (select.POLLHUP | select.POLLERR | select.POLLNVAL):
                    break
        finally:
            try:
                termios.tcsetattr(fd, termios.TCSANOW, old_attrs)
            except (OSError, termios.error):
                pass
            os.close(fd)
    print(f"captured {total} bytes to {args.output}")


if __name__ == "__main__":
    main()
