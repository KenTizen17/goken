# goken

A small Bash helper for managing `/etc/hosts` entries during pentests, CTFs and exams like HTB CPTS,CAPE etc.., where you keep adding vhosts and subdomains to the same target IP.

Instead of opening the hosts file in an editor every time you find a new vhost:

```bash
sudo goken 10.129.42.7 inlanefreight.htb dev.inlanefreight.htb admin.inlanefreight.htb
```

which gives you a single tidy line:

```
10.129.42.7	inlanefreight.htb dev.inlanefreight.htb admin.inlanefreight.htb
```

## Features

- Appends names to an existing line for the same IP instead of creating duplicate lines
- Skips names that are already mapped to that IP
- Removes a whole entry, or only specific names from it
- Keeps inline comments (`# ...`) intact
- Validates IPv4 addresses before touching anything
- Writes a backup (`/etc/hosts.bak`) before every change
- Rewrites the file in place, so its owner, permissions and inode are preserved
- Works on any hosts-style file via `HOSTS_FILE`, handy for testing

## Requirements

- Bash 4 or newer
- `awk`, `cp`, `cat`, `mktemp` (present on any standard Linux, including Kali, Parrot and Pwnbox)
- Root privileges to edit `/etc/hosts`

## Installation

Clone the repo and install the script somewhere on your `PATH`:

```bash
git clone https://github.com/fakeplaintext/goken.git
cd goken
sudo install -m 755 goken.sh /usr/local/bin/goken
```

Check it works:

```bash
goken --help
```

### Without installing

You can also run it straight from the repo:

```bash
chmod +x goken.sh
sudo ./goken.sh add 10.129.42.7 target.htb
```

### Uninstall

```bash
sudo rm /usr/local/bin/goken
```

## Usage

```
goken add   <IPv4> <FQDN> [FQDN...]   append name(s); creates the line if needed
goken clean <IPv4> [FQDN...]          remove the whole entry, or only the given names
goken list  [IPv4]                    list entries
```

`add` is the default command, so `goken <IPv4> <FQDN>` is the same as `goken add <IPv4> <FQDN>`.
`clean` also answers to `rm` and `remove`; `list` also answers to `ls`.

### Add entries

```bash
# create a new line
sudo goken add 10.129.42.7 inlanefreight.htb

# append more names to the same line
sudo goken 10.129.42.7 blog.inlanefreight.htb vpn.inlanefreight.htb

# names already present are skipped
sudo goken 10.129.42.7 inlanefreight.htb
# skipped: inlanefreight.htb already points to 10.129.42.7
```

### List entries

```bash
goken list               # every non-comment line
goken list 10.129.42.7   # only lines for that IP
```

`list` only needs read access, so it doesn't require `sudo`.

### Remove entries

```bash
# remove only some names, keep the rest of the line
sudo goken clean 10.129.42.7 vpn.inlanefreight.htb

# remove every line for that IP
sudo goken clean 10.129.42.7
```

If removing names leaves a line empty, the line is dropped.

## Working on another file

Set `HOSTS_FILE` to point the script at any hosts-style file. This is the easiest way to try it out without touching your real hosts file:

```bash
cp /etc/hosts ./hosts.test
HOSTS_FILE=./hosts.test goken add 10.0.0.1 foo.lan
HOSTS_FILE=./hosts.test goken list
```

Note that `sudo` drops most environment variables, so pass it after `sudo` if you need both:

```bash
sudo HOSTS_FILE=/path/to/hosts goken add 10.0.0.1 foo.lan
```

## Backups

Before every change, the current file is copied to `<file>.bak` (for example `/etc/hosts.bak`). Only the most recent state is kept. To undo the last change:

```bash
sudo cp /etc/hosts.bak /etc/hosts
```

