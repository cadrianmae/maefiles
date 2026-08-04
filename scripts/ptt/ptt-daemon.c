/*
 * Push-to-talk for the Keychron K8 Max.
 *
 * niri binds fire on key press only, so hold-to-talk cannot be expressed in
 * binds.kdl. This reads the keyboard's evdev nodes directly, where both the
 * press and the release are visible, and drives the mic mute through wpctl.
 *
 * The keyboard is matched by name rather than by event node: the node number
 * differs between the wired connection, the 2.4GHz Link dongle and Bluetooth.
 * A udev monitor triggers a rescan on hotplug so switching modes self-heals.
 *
 * Build: make
 */

#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <libudev.h>
#include <linux/input.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <unistd.h>

#define PTT_KEY KEY_F19
#define DEVICE_MATCH "Keychron"
#define SOURCE "@DEFAULT_AUDIO_SOURCE@"
#define MAX_DEVICES 16

/* poll() slots: one per keyboard node, plus the udev monitor on the end. */
static struct pollfd pfds[MAX_DEVICES + 1];
static int device_count;

/* Mute state from before the key went down, restored on release so a PTT
 * press while the mic is already live does not leave it muted afterwards.
 * -1 means the key is not currently held. */
static int restore_to = -1;

static volatile sig_atomic_t stopping;

static void on_signal(int sig) {
    (void)sig;
    stopping = 1;
}

static int bit_set(const unsigned long *bits, int bit) {
    return (bits[bit / (8 * sizeof(long))] >> (bit % (8 * sizeof(long)))) & 1;
}

/* Run wpctl and wait. Only ever called on a press or release, so the fork
 * cost is two per PTT cycle rather than anything per-event. */
static int wpctl(const char *const argv[]) {
    pid_t pid = fork();
    if (pid < 0) return -1;
    if (pid == 0) {
        execvp("wpctl", (char *const *)argv);
        _exit(127);
    }
    int status;
    if (waitpid(pid, &status, 0) < 0) return -1;
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

static void set_muted(int muted) {
    const char *const argv[] = {"wpctl", "set-mute", SOURCE, muted ? "1" : "0", NULL};
    if (wpctl(argv) != 0) fprintf(stderr, "ERROR wpctl set-mute failed\n");
}

/* 1 muted, 0 live, -1 on failure. */
static int is_muted(void) {
    FILE *fp = popen("wpctl get-volume " SOURCE " 2>/dev/null", "r");
    if (!fp) return -1;
    char buf[256];
    char *line = fgets(buf, sizeof buf, fp);
    int rc = pclose(fp);
    if (!line || rc != 0) return -1;
    return strstr(buf, "[MUTED]") != NULL;
}

static void ptt_pressed(void) {
    if (restore_to != -1) return; /* already held; ignore repeat across nodes */
    restore_to = is_muted();
    if (restore_to == -1) restore_to = 1; /* unknown: fail safe to muted */
    fprintf(stderr, "INFO PTT down (was %s)\n", restore_to ? "muted" : "live");
    set_muted(0);
}

static void ptt_released(void) {
    if (restore_to == -1) return;
    fprintf(stderr, "INFO PTT up (restoring %s)\n", restore_to ? "muted" : "live");
    set_muted(restore_to);
    restore_to = -1;
}

/* Never leave the mic open if we are going away. */
static void panic_mute(void) {
    if (restore_to != -1) {
        fprintf(stderr, "WARN exiting while held; muting\n");
        set_muted(1);
        restore_to = -1;
    }
}

static void close_devices(void) {
    for (int i = 0; i < device_count; i++) close(pfds[i].fd);
    device_count = 0;
}

/* Open every Keychron input node that can actually emit the PTT key. */
static void scan_devices(void) {
    close_devices();

    DIR *dir = opendir("/dev/input");
    if (!dir) {
        fprintf(stderr, "ERROR cannot open /dev/input: %s\n", strerror(errno));
        return;
    }

    struct dirent *entry;
    while ((entry = readdir(dir)) && device_count < MAX_DEVICES) {
        if (strncmp(entry->d_name, "event", 5) != 0) continue;

        char path[288];
        snprintf(path, sizeof path, "/dev/input/%s", entry->d_name);
        int fd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
        if (fd < 0) continue; /* not readable: udev rule likely missing */

        char name[256] = {0};
        unsigned long keys[KEY_MAX / (8 * sizeof(long)) + 1] = {0};
        if (ioctl(fd, EVIOCGNAME(sizeof name), name) < 0 ||
            ioctl(fd, EVIOCGBIT(EV_KEY, sizeof keys), keys) < 0 ||
            !strstr(name, DEVICE_MATCH) || !bit_set(keys, PTT_KEY)) {
            close(fd);
            continue;
        }

        fprintf(stderr, "INFO watching %s (%s)\n", name, path);
        pfds[device_count].fd = fd;
        pfds[device_count].events = POLLIN;
        device_count++;
    }
    closedir(dir);

    if (device_count == 0)
        fprintf(stderr, "WARN no Keychron device exposing F19 found\n");
}

static void handle_events(int fd) {
    struct input_event events[32];
    ssize_t n;
    while ((n = read(fd, events, sizeof events)) > 0) {
        for (size_t i = 0; i < n / sizeof events[0]; i++) {
            if (events[i].type != EV_KEY || events[i].code != PTT_KEY) continue;
            if (events[i].value == 1) ptt_pressed();
            else if (events[i].value == 0) ptt_released();
            /* value 2 is autorepeat while held; nothing to do */
        }
    }
}

int main(void) {
    setvbuf(stderr, NULL, _IOLBF, 0); /* line-buffered so journald sees it live */

    struct sigaction sa = {.sa_handler = on_signal};
    sigaction(SIGINT, &sa, NULL);
    sigaction(SIGTERM, &sa, NULL);

    struct udev *udev = udev_new();
    struct udev_monitor *mon = NULL;
    int mon_fd = -1;
    if (udev) {
        mon = udev_monitor_new_from_netlink(udev, "udev");
        if (mon) {
            udev_monitor_filter_add_match_subsystem_devtype(mon, "input", NULL);
            udev_monitor_enable_receiving(mon);
            mon_fd = udev_monitor_get_fd(mon);
        }
    }
    if (mon_fd < 0) fprintf(stderr, "WARN no udev monitor; hotplug will not rescan\n");

    scan_devices();

    while (!stopping) {
        int count = device_count;
        if (mon_fd >= 0) {
            pfds[count].fd = mon_fd;
            pfds[count].events = POLLIN;
            count++;
        }

        if (poll(pfds, count, -1) < 0) {
            if (errno == EINTR) continue;
            fprintf(stderr, "ERROR poll: %s\n", strerror(errno));
            break;
        }

        int rescan = 0;
        for (int i = 0; i < count; i++) {
            if (!pfds[i].revents) continue;
            if (mon_fd >= 0 && pfds[i].fd == mon_fd) {
                /* Drain the event; any input change triggers one rescan. */
                struct udev_device *dev = udev_monitor_receive_device(mon);
                if (dev) udev_device_unref(dev);
                rescan = 1;
            } else if (pfds[i].revents & POLLIN) {
                handle_events(pfds[i].fd);
            } else {
                rescan = 1; /* POLLERR/POLLHUP: device went away */
            }
        }
        if (rescan) scan_devices();
    }

    panic_mute();
    close_devices();
    if (mon) udev_monitor_unref(mon);
    if (udev) udev_unref(udev);
    return 0;
}
