FROM alpine:3.22

# The stock Alpine minirootfs points /sbin/init at OpenRC but does not ship
# the complete init system. Install the smallest bootable Alpine base and the
# services required by Apple container's persistent machine environment.
RUN apk add --no-cache alpine-base \
    && mkdir -p /run/openrc \
    && touch /run/openrc/softlevel \
    && rc-update add devfs sysinit \
    && rc-update add dmesg sysinit \
    && rc-update add mdev sysinit \
    && rc-update add hwdrivers sysinit \
    && rc-update add modules boot \
    && rc-update add sysctl boot \
    && rc-update add hostname boot \
    && rc-update add bootmisc boot

STOPSIGNAL SIGTERM
CMD ["/sbin/init"]
