#!/usr/bin/env python3
"""6A-244: one small shared network helper - "no IPv6 route" must never stop an update.

Standalone (standard library only). Loaded by path by the other lib modules; each of them falls back to plain urllib
when this file is missing, so it can never make things worse.

Problem: a mirror whose DNS answer has only IPv6 (AAAA) addresses on a machine without an IPv6 route fails with
"Network is unreachable" (errno ENETUNREACH). curl copes, Python urllib does not.

Rule: when a connection fails with ENETUNREACH / EHOSTUNREACH / EADDRNOTAVAIL (an IPv6 address was tried), the same
request is repeated once over IPv4 (the name is resolved with AF_INET). When the name has no IPv4 address the original
error is raised at once, so the caller moves on to the next host of the mirror family. A host that failed this way is
remembered for the rest of the process (IPv4 first, or "no address" without waiting again).

Nothing is checked less: the helper only changes WHICH address is used, never what is verified afterwards.
"""

import errno
import http.client
import socket
import threading
import urllib.error
import urllib.request

UNREACHABLE = (errno.ENETUNREACH, errno.EHOSTUNREACH, errno.EADDRNOTAVAIL)

_lock = threading.Lock()
_v4_hosts = set()      # hosts that need IPv4 only
_dead_hosts = set()    # hosts without any usable address (no A record, no IPv6 route)


def is_unreachable(exc):
    """True for a 'network/host unreachable' style failure (also inside URLError / socket.error chains)."""
    seen = 0
    while exc is not None and seen < 6:
        seen += 1
        if isinstance(exc, OSError) and getattr(exc, "errno", None) in UNREACHABLE:
            return True
        nxt = getattr(exc, "reason", None)
        if nxt is None or nxt is exc:
            nxt = exc.__cause__ or exc.__context__
        exc = nxt if isinstance(nxt, BaseException) else None
    return False


def _connect_v4(host, port, timeout, source_address=None):
    """A connected socket over IPv4 only. OSError(ENETUNREACH) when the name has no IPv4 address."""
    try:
        infos = socket.getaddrinfo(host, port, socket.AF_INET, socket.SOCK_STREAM)
    except socket.gaierror as e:
        raise OSError(errno.ENETUNREACH, "no IPv4 address for %s" % host) from e
    if not infos:
        raise OSError(errno.ENETUNREACH, "no IPv4 address for %s" % host)
    last = None
    for fam, typ, proto, _canon, addr in infos:
        sock = None
        try:
            sock = socket.socket(fam, typ, proto)
            if timeout is not None and timeout is not socket._GLOBAL_DEFAULT_TIMEOUT:
                sock.settimeout(timeout)
            if source_address:
                sock.bind(source_address)
            sock.connect(addr)
            return sock
        except OSError as e:
            last = e
            if sock is not None:
                sock.close()
    raise last if last else OSError(errno.ENETUNREACH, "no IPv4 address for %s" % host)


class _V4HTTPConnection(http.client.HTTPConnection):
    def connect(self):
        self.sock = _connect_v4(self.host, self.port, self.timeout, self.source_address)
        try:
            self.sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        except OSError:
            pass
        if self._tunnel_host:
            self._tunnel()


class _V4HTTPSConnection(http.client.HTTPSConnection):
    def connect(self):
        sock = _connect_v4(self.host, self.port, self.timeout, self.source_address)
        try:
            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        except OSError:
            pass
        server_hostname = self.host
        if self._tunnel_host:
            self.sock = sock
            self._tunnel()
            server_hostname = self._tunnel_host
        self.sock = self._context.wrap_socket(sock, server_hostname=server_hostname)


class _V4HTTPHandler(urllib.request.HTTPHandler):
    def http_open(self, req):
        return self.do_open(_V4HTTPConnection, req)


class _V4HTTPSHandler(urllib.request.HTTPSHandler):
    def https_open(self, req):
        return self.do_open(_V4HTTPSConnection, req, context=self._context)


def v4_handlers():
    """urllib handlers that connect over IPv4 only (for callers that build their own opener)."""
    return (_V4HTTPHandler(), _V4HTTPSHandler())


def _host_of(req):
    if isinstance(req, str):
        req = urllib.request.Request(req)
    try:
        return (req.host or "").lower()
    except Exception:
        return ""


def forget():
    """Tests: forget the per-process host memory."""
    with _lock:
        _v4_hosts.clear()
        _dead_hosts.clear()


def open_url(req, timeout=None, handlers=()):
    """Like urllib.request.urlopen(req, timeout=...) but with the IPv4 retry described above. `handlers` are extra
    urllib handlers (for example a redirect policy) used for both tries. Returns the response; raises the ORIGINAL
    error when IPv4 does not help."""
    host = _host_of(req)
    with _lock:
        dead = host in _dead_hosts
        v4 = host in _v4_hosts
    if dead:
        raise urllib.error.URLError(OSError(errno.ENETUNREACH, "Network is unreachable (no IPv4 address for %s)" % host))
    kw = {} if timeout is None else {"timeout": timeout}
    if not v4:
        try:
            return urllib.request.build_opener(*handlers).open(req, **kw)
        except Exception as e:
            if not is_unreachable(e):
                raise
            first = e
    else:
        first = None
    try:
        resp = urllib.request.build_opener(*handlers, *v4_handlers()).open(req, **kw)
        with _lock:
            _v4_hosts.add(host)
        return resp
    except Exception as e2:
        if is_unreachable(e2):
            with _lock:
                _dead_hosts.add(host)
            raise first if first is not None else e2
        # IPv4 reached the host but the request failed for another reason (HTTP error, timeout, TLS): that is the real
        # answer for this host
        with _lock:
            _v4_hosts.add(host)
        raise

