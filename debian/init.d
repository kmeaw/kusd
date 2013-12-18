#! /bin/sh
PATH=/usr/sbin:/usr/bin:/sbin:/bin
DAEMON=/usr/libexec/kusd/manager
PIDFILE=/var/run/kusd.manager.pid
[ -x "$DAEMON" ] || exit 0

case "$1" in
  start)
    start-stop-daemon --start --quiet --pidfile $PIDFILE -u root --exec $DAEMON --test > /dev/null \
      || return 1
    start-stop-daemon --start -d /usr/libexec/kusd --background --make-pidfile --quiet --pidfile $PIDFILE --exec $DAEMON \
      || return 2
    ;;
  stop)
    start-stop-daemon --stop -u root --quiet --retry=TERM/30/KILL/5 --pidfile $PIDFILE --signal 2 --exec $DAEMON
    RETVAL="$?"
    [ "$RETVAL" = 2 ] && return 2
    start-stop-daemon --stop --quiet --oknodo --retry=0/30/KILL/5 --exec $DAEMON
    [ "$?" = 2 ] && return 2
    rm -f $PIDFILE
    return "$RETVAL"
    ;;
  *)
    echo "Usage: $0 {start|stop}" >&2
    exit 3
    ;;
esac

:

