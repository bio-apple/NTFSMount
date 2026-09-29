/*
 * Privileged helper daemon. Runs as root via LaunchDaemon.
 * Accepts a Unix socket, pins the caller by live code validity + stored CDHash,
 * then execs the root-owned ntfs-rw-helper under /Library/Application Support/NTFSMount/.
 */
#include <CommonCrypto/CommonDigest.h>
#include <CoreFoundation/CoreFoundation.h>
#include <Security/Security.h>
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <libproc.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <unistd.h>
#include <os/log.h>

#define SOCK_PATH "/var/run/com.bioapple.ntfsmount.sock"
#define SUPPORT_DIR "/Library/Application Support/NTFSMount"
#define APP_PATH_FILE SUPPORT_DIR "/app.path"
#define ALLOWED_CDHASH SUPPORT_DIR "/allowed.cdhash"
#define HELPER_STAMP SUPPORT_DIR "/helper.stamp"
#define HELPER_SEALED SUPPORT_DIR "/ntfs-rw-helper"
#define BUNDLE_ID "com.bioapple.ntfsmount"
#define MAX_ARGS 32
#define MAX_ARG 1024
#define MAX_BODY (256 * 1024)
#define WAIT_SEC 180
#define WAIT_SEC_LONG 600
#define HEARTBEAT_TENTHS 100

static const char *kAllowed[] = {
    "mount", "unmount", "eject", "format", "fix", "ntfsfix", "probe", "automount",
    "enable-automount", "disable-automount", "repair-env", "version", "selftest",
    NULL};

static os_log_t g_log;

static os_log_t helperd_log(void) {
  if (!g_log) g_log = os_log_create(BUNDLE_ID, "helperd");
  return g_log;
}

static void die(const char *m) {
  int saved = errno;
  FILE *f = fopen("/Library/Logs/ntfsmount-helperd.log", "a");
  if (f) {
    fprintf(f, "helperd: %s (errno=%d)\n", m, saved);
    fclose(f);
  }
  fprintf(stderr, "helperd: %s\n", m);
  os_log_error(helperd_log(), "die %{public}s errno=%d", m, saved);
  exit(1);
}

static int hex_encode(const unsigned char *in, size_t n, char *out, size_t outn) {
  static const char *h = "0123456789abcdef";
  if (outn < n * 2 + 1) return -1;
  for (size_t i = 0; i < n; i++) {
    out[i * 2] = h[(in[i] >> 4) & 0xf];
    out[i * 2 + 1] = h[in[i] & 0xf];
  }
  out[n * 2] = 0;
  return 0;
}

static int read_trim_file(const char *path, char *out, size_t n) {
  FILE *f = fopen(path, "r");
  if (!f) return -1;
  if (!fgets(out, (int)n, f)) {
    fclose(f);
    return -1;
  }
  fclose(f);
  size_t L = strlen(out);
  while (L && (out[L - 1] == '\n' || out[L - 1] == '\r' || out[L - 1] == ' ')) out[--L] = 0;
  return L ? 0 : -1;
}

static int write_trunc(const char *path, const char *text, mode_t mode) {
  int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, mode);
  if (fd < 0) return -1;
  size_t n = strlen(text);
  ssize_t w = write(fd, text, n);
  close(fd);
  chmod(path, mode);
  chown(path, 0, 0);
  return w == (ssize_t)n ? 0 : -1;
}

static int sha256_file(const char *path, char *out, size_t outn) {
  int fd = open(path, O_RDONLY);
  if (fd < 0) return -1;
  CC_SHA256_CTX ctx;
  CC_SHA256_Init(&ctx);
  unsigned char buf[8192];
  ssize_t n;
  while ((n = read(fd, buf, sizeof(buf))) > 0) {
    CC_SHA256_Update(&ctx, buf, (CC_LONG)n);
  }
  close(fd);
  if (n < 0) return -1;
  unsigned char dig[CC_SHA256_DIGEST_LENGTH];
  CC_SHA256_Final(dig, &ctx);
  return hex_encode(dig, CC_SHA256_DIGEST_LENGTH, out, outn);
}

static int copy_file(const char *src, const char *dst) {
  int in = open(src, O_RDONLY | O_NOFOLLOW);
  if (in < 0) return -1;
  int out = open(dst, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, 0755);
  if (out < 0) {
    close(in);
    return -1;
  }
  char buf[8192];
  ssize_t n;
  int rc = 0;
  while ((n = read(in, buf, sizeof(buf))) > 0) {
    if (write(out, buf, (size_t)n) != n) {
      rc = -1;
      break;
    }
  }
  if (n < 0) rc = -1;
  close(in);
  close(out);
  if (rc == 0) {
    chown(dst, 0, 0);
    chmod(dst, 0755);
  }
  return rc;
}

static int cdhash_of_path(const char *path, char *out, size_t outn) {
  CFURLRef url = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)path, (CFIndex)strlen(path), false);
  if (!url) return -1;
  SecStaticCodeRef code = NULL;
  OSStatus st = SecStaticCodeCreateWithPath(url, kSecCSDefaultFlags, &code);
  CFRelease(url);
  if (st != errSecSuccess || !code) return -1;
  if (SecStaticCodeCheckValidity(code, kSecCSDefaultFlags, NULL) != errSecSuccess) {
    CFRelease(code);
    return -1;
  }
  CFDictionaryRef info = NULL;
  st = SecCodeCopySigningInformation(code, kSecCSSigningInformation, &info);
  CFRelease(code);
  if (st != errSecSuccess || !info) return -1;
  CFDataRef unique = CFDictionaryGetValue(info, kSecCodeInfoUnique);
  int rc = -1;
  if (unique) {
    rc = hex_encode(CFDataGetBytePtr(unique), (size_t)CFDataGetLength(unique), out, outn);
  }
  CFRelease(info);
  return rc;
}

static int identifier_of_path(const char *path, char *out, size_t outn) {
  CFURLRef url = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)path, (CFIndex)strlen(path), false);
  if (!url) return -1;
  SecStaticCodeRef code = NULL;
  OSStatus st = SecStaticCodeCreateWithPath(url, kSecCSDefaultFlags, &code);
  CFRelease(url);
  if (st != errSecSuccess || !code) return -1;
  CFDictionaryRef info = NULL;
  st = SecCodeCopySigningInformation(code, kSecCSSigningInformation, &info);
  CFRelease(code);
  if (st != errSecSuccess || !info) return -1;
  int rc = -1;
  CFStringRef ident = CFDictionaryGetValue(info, kSecCodeInfoIdentifier);
  if (ident && CFStringGetCString(ident, out, (CFIndex)outn, kCFStringEncodingUTF8)) rc = 0;
  CFRelease(info);
  return rc;
}

static int cdhash_of_pid(pid_t pid, char *out, size_t outn, int *validity_ok) {
  *validity_ok = 0;
  CFNumberRef pidRef = CFNumberCreate(NULL, kCFNumberIntType, &pid);
  if (!pidRef) return -1;
  const void *keys[] = {kSecGuestAttributePid};
  const void *vals[] = {pidRef};
  CFDictionaryRef attrs = CFDictionaryCreate(NULL, keys, vals, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
  CFRelease(pidRef);
  if (!attrs) return -1;
  SecCodeRef code = NULL;
  OSStatus st = SecCodeCopyGuestWithAttributes(NULL, attrs, kSecCSDefaultFlags, &code);
  CFRelease(attrs);
  if (st != errSecSuccess || !code) return -1;
  if (SecCodeCheckValidity(code, kSecCSDefaultFlags, NULL) == errSecSuccess) *validity_ok = 1;
  CFDictionaryRef info = NULL;
  st = SecCodeCopySigningInformation(code, kSecCSSigningInformation, &info);
  CFRelease(code);
  if (st != errSecSuccess || !info) return -1;
  CFDataRef unique = CFDictionaryGetValue(info, kSecCodeInfoUnique);
  int rc = -1;
  if (unique) {
    rc = hex_encode(CFDataGetBytePtr(unique), (size_t)CFDataGetLength(unique), out, outn);
  }
  CFRelease(info);
  return rc;
}

static int app_from_self(char *out, size_t n) {
  char self[PROC_PIDPATHINFO_MAXSIZE];
  if (proc_pidpath(getpid(), self, sizeof(self)) <= 0) return -1;
  char *p = strstr(self, "/Contents/MacOS/");
  if (!p) return -1;
  *p = 0;
  if (strlen(self) >= n) return -1;
  memcpy(out, self, strlen(self) + 1);
  return 0;
}

static int read_app_path(char *out, size_t n) {
  /* SMAppService BundleProgram: pin the live .app, not a stale app.path. */
  if (app_from_self(out, n) == 0) return 0;
  return read_trim_file(APP_PATH_FILE, out, n);
}

static int same_app(const char *peer_exe, const char *app) {
  char prefix[4096];
  snprintf(prefix, sizeof(prefix), "%s/Contents/MacOS/NTFSMount", app);
  return strcmp(peer_exe, prefix) == 0;
}

static int helper_root_owned(const char *path) {
  struct stat st;
  if (lstat(path, &st) != 0) return 0;
  if (!S_ISREG(st.st_mode)) return 0;
  if (st.st_uid != 0 || st.st_gid != 0) return 0;
  if (st.st_mode & (S_IWOTH | S_IWGRP)) return 0;
  if (!(st.st_mode & S_IXUSR)) return 0;
  return 1;
}

static int stamp_matches(const char *helper) {
  char line[256];
  if (read_trim_file(HELPER_STAMP, line, sizeof(line)) != 0) return 0;
  char *sha = strrchr(line, ' ');
  sha = sha ? sha + 1 : line;
  char got[65];
  if (sha256_file(helper, got, sizeof(got)) != 0) return 0;
  return strcasecmp(sha, got) == 0;
}

static int sealed_ready(void) {
  char buf[256];
  if (!helper_root_owned(HELPER_SEALED)) return 0;
  if (!stamp_matches(HELPER_SEALED)) return 0;
  if (read_trim_file(ALLOWED_CDHASH, buf, sizeof(buf)) != 0) return 0;
  if (read_trim_file(APP_PATH_FILE, buf, sizeof(buf)) != 0) return 0;
  return 1;
}

static int ensure_sealed(const char *app) {
  mkdir(SUPPORT_DIR, 0755);
  chown(SUPPORT_DIR, 0, 0);
  chmod(SUPPORT_DIR, 0755);

  char nlapp[4100];
  snprintf(nlapp, sizeof(nlapp), "%s\n", app);
  if (write_trunc(APP_PATH_FILE, nlapp, 0644) != 0) return -1;

  char hash[128];
  if (cdhash_of_path(app, hash, sizeof(hash)) != 0) return -1;
  char line[160];
  snprintf(line, sizeof(line), "%s\n", hash);
  if (write_trunc(ALLOWED_CDHASH, line, 0644) != 0) return -1;

  char src[4096];
  snprintf(src, sizeof(src), "%s/Contents/Resources/ntfs-rw-helper", app);
  if (access(src, R_OK) != 0) return -1;
  if (copy_file(src, HELPER_SEALED) != 0) return -1;

  char sha[65];
  if (sha256_file(HELPER_SEALED, sha, sizeof(sha)) != 0) return -1;
  char stamp[96];
  snprintf(stamp, sizeof(stamp), "0 %s\n", sha);
  if (write_trunc(HELPER_STAMP, stamp, 0644) != 0) return -1;
  return helper_root_owned(HELPER_SEALED) ? 0 : -1;
}

static int peer_ok(int fd, const char *app) {
  pid_t pid = 0;
  socklen_t len = sizeof(pid);
  if (getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &pid, &len) < 0 || pid <= 0) return 0;
  char exe[PROC_PIDPATHINFO_MAXSIZE];
  if (proc_pidpath(pid, exe, sizeof(exe)) <= 0) return 0;
  if (!same_app(exe, app)) return 0;
  char ident[256];
  if (identifier_of_path(exe, ident, sizeof(ident)) != 0) return 0;
  if (strcmp(ident, BUNDLE_ID) != 0) return 0;

  int validity_ok = 0;
  char peer_hash[128];
  if (cdhash_of_pid(pid, peer_hash, sizeof(peer_hash), &validity_ok) != 0) {
    /* Guest lookup failed; static path still requires SecStaticCodeCheckValidity. */
    if (cdhash_of_path(exe, peer_hash, sizeof(peer_hash)) != 0) return 0;
    validity_ok = 1;
  }

  char allowed[128];
  if (read_trim_file(ALLOWED_CDHASH, allowed, sizeof(allowed)) != 0) return 0;
  /* Stored install pin, not the live .app CDHash (that would follow a replaced bundle). */
  if (strcasecmp(peer_hash, allowed) != 0) return 0;
  if (!validity_ok) return 0;
  return 1;
}

static int allowed_cmd(const char *c) {
  for (int i = 0; kAllowed[i]; i++)
    if (strcmp(c, kAllowed[i]) == 0) return 1;
  return 0;
}

static int read_line(int fd, char *buf, size_t n) {
  size_t i = 0;
  while (i + 1 < n) {
    char c;
    ssize_t r = recv(fd, &c, 1, 0);
    if (r <= 0) return -1;
    if (c == '\n') {
      buf[i] = 0;
      return 0;
    }
    buf[i++] = c;
  }
  return -1;
}

static int read_exact(int fd, char *buf, size_t n) {
  size_t i = 0;
  while (i < n) {
    ssize_t r = recv(fd, buf + i, n - i, 0);
    if (r <= 0) return -1;
    i += (size_t)r;
  }
  return 0;
}

static int parse_ulen(const char *s, unsigned *out) {
  char *end = NULL;
  unsigned long v;
  if (!s || !*s) return -1;
  errno = 0;
  v = strtoul(s, &end, 10);
  if (errno != 0 || end == s || *end != '\0' || v >= (unsigned long)MAX_ARG) return -1;
  *out = (unsigned)v;
  return 0;
}

static int read_v2_arg(int fd, char *buf, size_t cap) {
  char nline[32];
  unsigned n = 0;
  if (read_line(fd, nline, sizeof(nline)) != 0) return -1;
  if (parse_ulen(nline, &n) != 0) return -1;
  if (n >= cap) return -1;
  if (n > 0 && read_exact(fd, buf, n) != 0) return -1;
  if (memchr(buf, 0, n) != NULL) return -1;
  buf[n] = 0;
  return 0;
}

static void write_all(int fd, const char *p, size_t n) {
  while (n) {
    ssize_t w = send(fd, p, n, 0);
    if (w <= 0) return;
    p += (size_t)w;
    n -= (size_t)w;
  }
}

static int wait_sec_for_cmd(const char *cmd) {
  if (strcmp(cmd, "format") == 0 || strcmp(cmd, "fix") == 0 || strcmp(cmd, "ntfsfix") == 0)
    return WAIT_SEC_LONG;
  return WAIT_SEC;
}

static void reap_children(int sig) {
  (void)sig;
  int st;
  while (waitpid(-1, &st, WNOHANG) > 0) {
  }
}

/* Client always SHUT_WR after argv; recv 0 / POLLHUP-with-POLLOUT is normal.
 * Skip exec only if the peer fully closed (timeout) — same send-fail rule as wait_helper. */
static int peer_disconnected(int fd) {
  struct pollfd pfd;
  pfd.fd = fd;
  pfd.events = POLLOUT;
  pfd.revents = 0;
  if (poll(&pfd, 1, 0) > 0) {
    if (pfd.revents & (POLLERR | POLLNVAL)) return 1;
    if ((pfd.revents & POLLHUP) && !(pfd.revents & POLLOUT)) return 1;
  }
  {
    char hb = '\0';
    if (send(fd, &hb, 1, 0) <= 0) return 1;
  }
  return 0;
}

/* Poll helper stdout while waiting. Every 10s send NUL heartbeat so the app
 * SO_RCVTIMEO does not fire. If the app hangs up, kill the helper (do not keep formatting). */
static int wait_helper(int client, int pr, pid_t pid, int sec, int *st, char *body, size_t cap, size_t *nout) {
  size_t n = 0;
  int ticks = 0;
  int max_ticks = sec * 10;
  int since_hb = 0;
  int pipe_open = 1;
  int st_got = 0;
  int local_st = 0;

  while (ticks < max_ticks) {
    if (!st_got) {
      pid_t r = waitpid(pid, &local_st, WNOHANG);
      if (r == pid) {
        st_got = 1;
      } else if (r < 0 && errno != EINTR) {
        *nout = n;
        return -1;
      }
    }
    if (pipe_open) {
      fd_set rfds;
      struct timeval tv;
      int s;
      FD_ZERO(&rfds);
      FD_SET(pr, &rfds);
      tv.tv_sec = 0;
      tv.tv_usec = 100000;
      s = select(pr + 1, &rfds, NULL, NULL, &tv);
      if (s < 0 && errno == EINTR) continue;
      if (s > 0 && FD_ISSET(pr, &rfds)) {
        if (n < cap - 1) {
          ssize_t rd = read(pr, body + n, cap - 1 - n);
          if (rd > 0)
            n += (size_t)rd;
          else
            pipe_open = 0;
        } else {
          char dump[256];
          ssize_t rd = read(pr, dump, sizeof(dump));
          if (rd <= 0) pipe_open = 0;
        }
      }
    } else if (!st_got) {
      usleep(100000);
    }
    if (st_got && !pipe_open) {
      *st = local_st;
      *nout = n;
      return 0;
    }
    ticks++;
    since_hb++;
    if (since_hb >= HEARTBEAT_TENTHS) {
      char hb = '\0';
      since_hb = 0;
      if (send(client, &hb, 1, 0) <= 0) {
        kill(pid, SIGTERM);
        usleep(400000);
        kill(pid, SIGKILL);
        waitpid(pid, &local_st, 0);
        *st = local_st;
        *nout = n;
        return -3;
      }
    }
  }
  kill(pid, SIGTERM);
  usleep(400000);
  kill(pid, SIGKILL);
  waitpid(pid, &local_st, 0);
  *st = local_st;
  *nout = n;
  return -2;
}

/* Between fork and exec, only async-signal-safe calls. os_log aborts the child
   on macOS 26+ ("crashed on child side of fork pre-exec"), which the client
   sees as a socket that accepts and then returns nothing. */
static void child_log(const char *msg) {
  size_t n = 0;
  if (!msg) return;
  while (msg[n]) n++;
  if (n) write(STDERR_FILENO, msg, n);
  write(STDERR_FILENO, "\n", 1);
}

static void handle(int fd) {
  struct timeval tv = {.tv_sec = 30, .tv_usec = 0};
  setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
  char line[64];
  int argc = 0;
  int ver = 0;
  int hdrn = 0;
  char extra;
  if (read_line(fd, line, sizeof(line)) != 0) return;
  if (strncmp(line, "v2 ", 3) == 0 && sscanf(line + 3, "%d%c", &hdrn, &extra) == 1) {
    ver = 2;
    argc = hdrn;
  } else if (strncmp(line, "v1 ", 3) == 0 && sscanf(line + 3, "%d%c", &hdrn, &extra) == 1) {
    ver = 1;
    argc = hdrn;
  }
  if (ver == 0 || argc < 1 || argc > MAX_ARGS) {
    const char *m = "ERR\nProtocol error.\n";
    write_all(fd, m, strlen(m));
    return;
  }
  char args[MAX_ARGS][MAX_ARG];
  char *argv[MAX_ARGS + 2];
  const char *helper = HELPER_SEALED;
  if (!helper_root_owned(helper) || !stamp_matches(helper)) {
    const char *m = "ERR\nMount helper copy failed verification. Reinstall the helper.\n";
    write_all(fd, m, strlen(m));
    return;
  }
  argv[0] = (char *)helper;
  for (int i = 0; i < argc; i++) {
    if (ver == 2) {
      if (read_v2_arg(fd, args[i], MAX_ARG) != 0) {
        const char *m = "ERR\nProtocol error.\n";
        write_all(fd, m, strlen(m));
        return;
      }
    } else if (read_line(fd, args[i], MAX_ARG) != 0) {
      return;
    }
    if (i == 0 && !allowed_cmd(args[i])) {
      const char *m = "ERR\nCommand not allowed.\n";
      write_all(fd, m, strlen(m));
      return;
    }
    argv[i + 1] = args[i];
  }
  argv[argc + 1] = NULL;
  if (access(helper, X_OK) != 0) {
    const char *m = "ERR\nPinned mount helper not found. Reinstall the helper.\n";
    write_all(fd, m, strlen(m));
    return;
  }
  if (peer_disconnected(fd)) return;

  int pipefd[2];
  if (pipe(pipefd) != 0) return;
  pid_t pid = fork();
  if (pid < 0) {
    close(pipefd[0]);
    close(pipefd[1]);
    return;
  }
  if (pid == 0) {
    close(pipefd[0]);
    dup2(pipefd[1], STDOUT_FILENO);
    dup2(pipefd[1], STDERR_FILENO);
    close(pipefd[1]);
    execv(helper, argv);
    child_log("exec mount helper failed");
    _exit(127);
  }
  close(pipefd[1]);
  char body[MAX_BODY];
  size_t n = 0;
  int st = 0;
  int wr = wait_helper(fd, pipefd[0], pid, wait_sec_for_cmd(args[0]), &st, body, sizeof(body), &n);
  body[n] = 0;
  close(pipefd[0]);
  if (wr == -3) {
    child_log("client hung up");
    return;
  }
  if (wr == -2) {
    child_log("mount helper timed out");
    const char *m = "ERR\nMount helper timed out.\n";
    write_all(fd, m, strlen(m));
    write_all(fd, body, n);
    return;
  }
  int ok = wr == 0 && WIFEXITED(st) && WEXITSTATUS(st) == 0;
  const char *head = ok ? "OK\n" : "ERR\n";
  write_all(fd, head, strlen(head));
  write_all(fd, body, n);
}

int main(void) {
  fprintf(stderr, "helperd: start pid=%d uid=%d\n", (int)getpid(), (int)getuid());
  os_log(helperd_log(), "start pid=%d uid=%d", (int)getpid(), (int)getuid());
  if (getuid() != 0) die("need root");
  signal(SIGPIPE, SIG_IGN);
  signal(SIGCHLD, reap_children);
  char app[4096];
  if (read_app_path(app, sizeof(app)) != 0) die("no app.path");
  os_log(helperd_log(), "app.path %{private}s", app);
  /* First SMAppService start writes the install pins. Never recopy from a
   * user-writable .app just because the live bundle CDHash changed. */
  if (!sealed_ready()) {
    if (ensure_sealed(app) != 0 || !sealed_ready()) die("seal helper");
  }

  unlink(SOCK_PATH);
  int s = socket(AF_UNIX, SOCK_STREAM, 0);
  if (s < 0) die("socket");
  struct sockaddr_un addr;
  memset(&addr, 0, sizeof(addr));
  addr.sun_family = AF_UNIX;
  strncpy(addr.sun_path, SOCK_PATH, sizeof(addr.sun_path) - 1);
  if (bind(s, (struct sockaddr *)&addr, sizeof(addr)) < 0) die("bind");
  /* 0666: unprivileged app connects; helperd authenticates by stored CDHash. */
  chmod(SOCK_PATH, 0666);
  if (listen(s, 8) < 0) die("listen");

  for (;;) {
    int c = accept(s, NULL, NULL);
    if (c < 0) {
      if (errno == EINTR) continue;
      break;
    }
    /* Authenticate in the parent. Security.framework and os_log are not safe
       in the forked child before exec. */
    if (!peer_ok(c, app)) {
      os_log_error(helperd_log(), "peer rejected app=%{private}s", app);
      const char *m = "ERR\nCaller failed the signature check.\n";
      write_all(c, m, strlen(m));
      close(c);
      continue;
    }
    pid_t w = fork();
    if (w == 0) {
      close(s);
      signal(SIGCHLD, SIG_DFL);
      handle(c);
      close(c);
      _exit(0);
    }
    if (w < 0) {
      const char *m = "ERR\nMount helper could not start.\n";
      write_all(c, m, strlen(m));
    }
    close(c);
    /* Parent returns to accept. SIGCHLD reaps workers; do not waitpid here. */
  }
  return 0;
}
