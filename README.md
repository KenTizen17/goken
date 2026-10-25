# goken

A small Bash helper for managing `/etc/hosts` entries during pentests, CTFs and exams like HTB CPTS,CAPE etc..., where you keep adding vhosts and subdomains to the same target IP.

I made this while going through the CPTS Path, manually editing the hosts file every time is annoying. 

Instead of opening the hosts file in an editor every time you find a new vhost:

```bash
sudo goken 10.129.42.7 inlanefreight.htb
sudo goken 10.129.42.7 dev.inlanefreight.htb admin.inlanefreight.htb
sudo goken add 10.129.33.33 {app,dev,run,prod}.inlanefreight.htb
```

which gives you a single tidy line:

```
10.129.42.7	inlanefreight.htb dev.inlanefreight.htb admin.inlanefreight.htb	# goken
```

## Features

- Appends names to the existing line for an IP instead of creating duplicate lines
- Skips names already mapped to that IP, and refuses to silently map a name to a second IP
- `move` repoints names when a box gets a new IP after a reset
- Removes a whole entry, or only specific names from it
- Tags its own lines with `# goken`, so `flush` cleans up everything it added, and nothing else
- Timestamped backups before every change, with `undo` to step back through them
- `--dry-run` shows any change as a diff before writing it
- Tab completion for bash and zsh: commands, IPs in the hosts file, names to clean
- Validates IPv4 addresses and hostnames before touching anything
- Rewrites the file in place, so its owner, permissions and inode are preserved
- Works on any hosts-style file via `HOSTS_FILE`, handy for testing

## Requirements

- Bash 4.4 or newer
- Standard tools: `awk`, `diff`, `cmp`, `mktemp`, `date` (present on Kali, Parrot, Pwnbox and any other mainstream Linux)
- `make`, only if you use it to install
- Root privileges to edit `/etc/hosts`

## Installation

```bash
git clone https://github.com/fakeplaintext/goken.git
cd goken
sudo make install
```

This installs:

| File | Location |
| ---- | -------- |
| `goken.sh` | `/usr/local/bin/goken` |
| `completions/goken.bash` | `/usr/share/bash-completion/completions/goken` |
| `completions/_goken` | `/usr/local/share/zsh/site-functions/_goken` |

Open a new terminal and check it works:

```bash
goken --help
```

Change the install location with `PREFIX`, for example `sudo make install PREFIX=/opt/goken`.

### Tab completion

Bash picks up the completion automatically in new shells, as long as the `bash-completion` package is installed (it is on Kali and Parrot).


Completion works after `sudo` too: `sudo goken clean 10.129.42.7 <Tab>` lists the names on that IP.

### Without installing

You can also run it straight from the repo:

```bash
chmod +x goken.sh
sudo ./goken.sh add 10.129.42.7 target.htb
```

To get completion this way, load it in your current shell: `source completions/goken.bash` on bash.

### Uninstall

```bash
sudo make uninstall
```

## Usage

```
goken [-n] add   <IPv4> <FQDN> [FQDN...]   map name(s) to an IP
goken [-n] move  <IPv4> <FQDN> [FQDN...]   map name(s), removing them from any other IP
goken [-n] clean <IPv4> [FQDN...]          remove the whole entry, or only the given names
goken [-n] flush                           remove every entry goken added
goken [-n] undo                            restore the most recent backup
goken list  [IPv4]                         list entries
goken backups                              list backups, newest first
```

`add` is the default command, so `goken <IPv4> <FQDN>` is the same as `goken add <IPv4> <FQDN>`.
Aliases: `mv` for `move`; `rm` and `remove` for `clean`; `ls` for `list`.

Hostnames are lowercased, since DNS names are case-insensitive.

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

### Repoint names after a box reset

When a target comes back with a new IP, `add` won't create a second mapping for a name, because the resolver would keep using the first (old) one:

```bash
sudo goken 10.129.55.3 inlanefreight.htb
# skipped: inlanefreight.htb already points to 10.129.42.7 (use "goken move 10.129.55.3 inlanefreight.htb" to repoint it)
```

`move` removes the names from the old IP and adds them to the new one:

```bash
sudo goken move 10.129.55.3 inlanefreight.htb blog.inlanefreight.htb
```

### List entries

```bash
goken list               # every non-comment line
goken list 10.129.42.7   # only lines for that IP
```

`list` and `backups` only need read access, so they don't require `sudo`.

### Remove entries

```bash
# remove only some names, keep the rest of the line
sudo goken clean 10.129.42.7 vpn.inlanefreight.htb

# remove every line for that IP
sudo goken clean 10.129.42.7
```

If removing names leaves a line empty, the line is dropped.

### Clean up after an exam: `flush`

Every line goken creates ends with a `# goken` comment:

```
127.0.0.1	localhost
10.129.42.7	inlanefreight.htb dev.inlanefreight.htb	# goken
```

`flush` removes all of those lines in one go, and leaves your own entries alone:

```bash
sudo goken flush
```

goken never appends names to a line it didn't create. If an IP is already in the file on a line you wrote yourself, goken adds a separate tagged line for it, so `flush` stays safe.

### Preview a change: `--dry-run`

Add `-n` or `--dry-run` to any command that changes the file to see a diff of what would happen. Nothing is written and no backup is made, so it doesn't need `sudo`:

```bash
goken -n move 10.129.55.3 inlanefreight.htb
```

```diff
--- /etc/hosts
+++ /etc/hosts (after)
@@ -1,2 +1,3 @@
 127.0.0.1	localhost
-10.129.42.7	inlanefreight.htb dev.inlanefreight.htb	# goken
+10.129.42.7	dev.inlanefreight.htb	# goken
+10.129.55.3	inlanefreight.htb	# goken
```

## Backups and undo

Before every change, goken saves a timestamped copy of the file in `/etc/hosts.goken.d/`. It keeps the 20 most recent and deletes older ones.

```bash
goken backups        # list them, newest first
goken -n undo        # preview what undo would restore
sudo goken undo      # restore the latest backup
```

`undo` restores the most recent backup and then deletes it, so running it again steps back one more change.

## Configuration

All settings are environment variables:

| Variable | Default | Meaning |
| -------- | ------- | ------- |
| `HOSTS_FILE` | `/etc/hosts` | file to manage |
| `GOKEN_BACKUP_DIR` | `<HOSTS_FILE>.goken.d` | where backups are kept |
| `GOKEN_KEEP` | `20` | number of backups to keep |

To try goken without touching your real hosts file:

```bash
cp /etc/hosts ./hosts.test
HOSTS_FILE=./hosts.test goken add 10.0.0.1 foo.lan
HOSTS_FILE=./hosts.test goken list
```

`sudo` drops most environment variables, so put them after `sudo` if you need both:

```bash
sudo HOSTS_FILE=/path/to/hosts goken add 10.0.0.1 foo.lan
```


