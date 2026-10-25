#!/usr/bin/env bash
#
# Author:fakeplaintext
#
# goken - manage FQDN entries in the hosts file.


set -euo pipefail

HOSTS_FILE="${HOSTS_FILE:-/etc/hosts}"
BACKUP_DIR="${GOKEN_BACKUP_DIR:-$HOSTS_FILE.goken.d}"
KEEP="${GOKEN_KEEP:-20}"
PROG=${0##*/}

# Lines goken creates carry this comment, so `flush` can find them again.
TAG='# goken'
TAG_RE='#[ \t]*goken([ \t]|$)'

DRY_RUN=0
WORK=""
BACKUPS=()

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

usage() {
    local code=${1:-2} fd=2
    (( code == 0 )) && fd=1
    cat >&"$fd" <<EOF
    Usage:
    $PROG [-n] add   <IPv4> <FQDN> [FQDN...]   map name(s) to an IP
    $PROG [-n] move  <IPv4> <FQDN> [FQDN...]   map name(s), removing them from any other IP
    $PROG [-n] clean <IPv4> [FQDN...]          remove the whole entry, or only the given names
    $PROG [-n] flush                           remove every entry goken added
    $PROG [-n] undo                            restore the most recent backup
    $PROG list  [IPv4]                         list entries
    $PROG backups                              list backups, newest first
    
    "add" is the default: $PROG <IPv4> <FQDN> works too.
    
    Options:
    -n, --dry-run   show the change as a diff, write nothing
    -h, --help      show this help
    
    Environment:
    HOSTS_FILE        file to manage            (current: $HOSTS_FILE)
    GOKEN_BACKUP_DIR  where backups are kept    (current: $BACKUP_DIR)
    GOKEN_KEEP        number of backups to keep (current: $KEEP)
EOF
    exit "$code"
}

cleanup() {
if [[ -n $WORK ]]; then rm -f "$WORK" "$WORK.new"; fi
}
trap cleanup EXIT

is_ipv4() {
local octet
local -a parts
[[ $1 =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
IFS='.' read -ra parts <<< "$1"
for octet in "${parts[@]}"; do
    ((10#$octet <= 255)) || return 1
    done
}

# Expects an already lowercased name.
is_hostname() {
[[ $1 =~ ^[a-z0-9_]([a-z0-9._-]*[a-z0-9_])?$ ]]
}

check_file() {
[[ -f $HOSTS_FILE ]] || die "$HOSTS_FILE not found"
[[ -r $HOSTS_FILE ]] || die "cannot read $HOSTS_FILE"
}

check_writable() {
check_file
[[ -w $HOSTS_FILE ]] || die "cannot write to $HOSTS_FILE (run with sudo, or use --dry-run)"
}



load() {
if (( DRY_RUN )); then check_file; else check_writable; fi
    WORK=$(mktemp)
    cat "$HOSTS_FILE" > "$WORK"
}

# apply <awk args...>: run an awk program over $WORK and replace it with the output.
# awk ends every line it prints with a newline, which also repairs a file whose
# last line had none.
apply() {
awk "$@" "$WORK" > "$WORK.new"
mv "$WORK.new" "$WORK"
}

# Returns 1 if there is nothing to change.
commit() {
cmp -s "$HOSTS_FILE" "$WORK" && return 1
if (( DRY_RUN )); then
    diff -u --label "$HOSTS_FILE" --label "$HOSTS_FILE (after)" "$HOSTS_FILE" "$WORK" || :
    printf '(dry run: nothing written)\n'
    return 0
    fi
    backup
    # Write in place, keeping the file's inode, owner and permissions.
    cat "$WORK" > "$HOSTS_FILE"
}

# ------------------------------------------------------------------ backups

load_backups() {
local nullglob
nullglob=$(shopt -p nullglob || :)
shopt -s nullglob
BACKUPS=("$BACKUP_DIR/${HOSTS_FILE##*/}".*)
eval "$nullglob"
}

backup() {
mkdir -p "$BACKUP_DIR"
cp -p "$HOSTS_FILE" "$BACKUP_DIR/${HOSTS_FILE##*/}.$(date +%Y%m%d-%H%M%S-%N)"
load_backups
local i excess=$(( ${#BACKUPS[@]} - KEEP ))
for (( i = 0; i < excess; i++ )); do
    rm -f "${BACKUPS[i]}"
    done
}

# hosts.20261025-224012-123456789 -> 2026-10-25 22:40:12
backup_date() {
local stamp=${1##*.}
printf '%s-%s-%s %s:%s:%s' "${stamp:0:4}" "${stamp:4:2}" "${stamp:6:2}" \
"${stamp:9:2}" "${stamp:11:2}" "${stamp:13:2}"
}

# ------------------------------------------------------------------ queries

# Shared awk helper: split the current line into its names (nm) and its
# trailing comment (tail).
AWK_SPLIT='
function split_line(   i, j) {
nm = ""; tail = ""
for (i = 2; i <= NF; i++) {
    if (substr($i, 1, 1) == "#") {
        tail = $i
        for (j = i + 1; j <= NF; j++) tail = tail " " $j
            return
}
nm = nm (nm == "" ? "" : " ") $i
}
}
'

names_on() {
awk -v ip="$1" "$AWK_SPLIT"'
$1 == ip { split_line(); n = split(nm, f, " "); for (i = 1; i <= n; i++) print tolower(f[i]) }
' "$WORK"
}

owners_of() {
awk -v name="$1" "$AWK_SPLIT"'
NF && $1 !~ /^#/ {
split_line(); n = split(nm, f, " ")
for (i = 1; i <= n; i++) if (tolower(f[i]) == name) { print $1; break }
}
' "$WORK" | sort -u
}

# drop <only|except> <ip> <all:0|1> [names...]
#   only:   act on lines for <ip>;    except: act on lines for every other IP.
#   all=1:  remove those lines entirely; otherwise remove just the given names.
# A line left with no names is removed. Untouched lines keep their formatting.
drop() {
local scope=$1 ip=$2 all=$3 except=0
shift 3
[[ $scope == except ]] && except=1
apply -v ip="$ip" -v except="$except" -v all="$all" -v names="$*" "$AWK_SPLIT"'
BEGIN { n = split(names, a, " "); for (i = 1; i <= n; i++) gone[a[i]] = 1 }
NF == 0 || $1 ~ /^#/          { print; next }
(except ? $1 == ip : $1 != ip) { print; next }
all                           { next }
{
split_line(); out = ""
k = split(nm, f, " ")
for (i = 1; i <= k; i++) if (!(tolower(f[i]) in gone)) out = out (out == "" ? "" : " ") f[i]
    if (out == "") next
        if (out == nm) { print; next }
        print $1 "\t" out (tail == "" ? "" : "\t" tail)
}
'
}


# cmd_add <add|move> <ip> <names...>
cmd_add() {
local mode=$1
shift
(( $# >= 2 )) || die "usage: $PROG $mode <IPv4> <FQDN> [FQDN...]"
local ip=$1
shift
is_ipv4 "$ip" || die "'$ip' is not a valid IPv4 address"

local name owner here
local -a new=() owners=() others=()
local -A seen=()
for name in "$@"; do
    name=${name,,}
    is_hostname "$name" || die "'$name' is not a valid hostname"
    done
    
    load
    for name in "$@"; do
        name=${name,,}
        [[ -n ${seen[$name]:-} ]] && continue
        seen[$name]=1
        
        mapfile -t owners < <(owners_of "$name")
        here=0
        others=()
        for owner in "${owners[@]}"; do
            if [[ $owner == "$ip" ]]; then here=1; else others+=("$owner"); fi
                done
                
                if (( ${#others[@]} )); then
                    if [[ $mode == add ]]; then
                        printf 'skipped: %s already points to %s (use "%s move %s %s" to repoint it)\n' \
                        "$name" "${others[*]}" "$PROG" "$ip" "$name"
                        continue
                        fi
                        drop except "$ip" 0 "$name"
                        printf 'moved: %s from %s to %s\n' "$name" "${others[*]}" "$ip"
                        elif (( here )); then
                        printf 'skipped: %s already points to %s\n' "$name" "$ip"
                        fi
                        (( here )) || new+=("$name")
                        done
                        
                        if (( ${#new[@]} )); then
                            # Append to the first goken line for this IP, or create one.
                            # Lines goken didn't create are left alone, so `flush` stays safe.
                            apply -v ip="$ip" -v add="${new[*]}" -v tag="$TAG" -v re="$TAG_RE" "$AWK_SPLIT"'
                            !done && $1 == ip && $0 ~ re {
                            split_line()
                            print $1 "\t" nm " " add (tail == "" ? "" : "\t" tail)
                            done = 1; next
}
{ print }
END { if (!done) print ip "\t" add "\t" tag }
'
printf 'added: %s -> %s\n' "$ip" "${new[*]}"
fi
commit || :
}

cmd_clean() {
(( $# >= 1 )) || die "usage: $PROG clean <IPv4> [FQDN...]"
local ip=$1
shift
is_ipv4 "$ip" || die "'$ip' is not a valid IPv4 address"
load

if (( $# == 0 )); then
    drop only "$ip" 1
    if commit; then
        printf 'cleaned: removed every entry for %s\n' "$ip"
        else
            printf 'nothing to clean for %s\n' "$ip"
            fi
            return 0
            fi
            
            local name
            local -a gone=()
            local -A present=() seen=()
            while read -r name; do present[$name]=1; done < <(names_on "$ip")
                for name in "$@"; do
                    name=${name,,}
                    [[ -n ${seen[$name]:-} ]] && continue
                    seen[$name]=1
                    if [[ -n ${present[$name]:-} ]]; then
                        gone+=("$name")
                        else
                            printf 'not found: %s is not mapped to %s\n' "$name" "$ip"
                            fi
                            done
                            (( ${#gone[@]} )) || return 0
                            
                            drop only "$ip" 0 "${gone[@]}"
                            printf 'cleaned: removed %s from %s\n' "${gone[*]}" "$ip"
                            commit || :
}

cmd_flush() {
(( $# == 0 )) || die "usage: $PROG flush"
load
local count
count=$(awk -v re="$TAG_RE" 'NF && $1 !~ /^#/ && $0 ~ re' "$WORK" | wc -l)
if (( count == 0 )); then
    printf 'nothing to flush\n'
    return 0
    fi
    apply -v re="$TAG_RE" 'NF && $1 !~ /^#/ && $0 ~ re { next } { print }'
    printf 'flushed: removed %d line(s) added by goken\n' "$count"
    commit || :
}

cmd_undo() {
(( $# == 0 )) || die "usage: $PROG undo"
if (( DRY_RUN )); then check_file; else check_writable; fi
    load_backups
    (( ${#BACKUPS[@]} )) || die "no backup to restore in $BACKUP_DIR"
    
    local last=${BACKUPS[-1]}
    if (( DRY_RUN )); then
        diff -u --label "$HOSTS_FILE" --label "backup from $(backup_date "$last")" \
        "$HOSTS_FILE" "$last" || :
        printf '(dry run: nothing written)\n'
        return 0
        fi
        cat "$last" > "$HOSTS_FILE"
        rm -f "$last"
        printf 'restored %s from the backup of %s (%d older backup(s) left)\n' \
        "$HOSTS_FILE" "$(backup_date "$last")" $(( ${#BACKUPS[@]} - 1 ))
}

cmd_backups() {
(( $# == 0 )) || die "usage: $PROG backups"
load_backups
if (( ! ${#BACKUPS[@]} )); then
    printf 'no backups in %s\n' "$BACKUP_DIR"
    return 0
    fi
    local i
    for (( i = ${#BACKUPS[@]} - 1; i >= 0; i-- )); do
        printf '%s  %s\n' "$(backup_date "${BACKUPS[i]}")" "${BACKUPS[i]}"
        done
}

cmd_list() {
check_file
local ip=${1:-}
if [[ -n $ip ]]; then
    is_ipv4 "$ip" || die "'$ip' is not a valid IPv4 address"
    awk -v ip="$ip" '$1 == ip' "$HOSTS_FILE"
    else
        awk 'NF && $1 !~ /^#/' "$HOSTS_FILE"
        fi
}

# --------------------------------------------------------------------- main

[[ $KEEP =~ ^[1-9][0-9]*$ ]] || die "GOKEN_KEEP must be a positive number"

args=()
for arg in "$@"; do
    case $arg in
    -n|--dry-run) DRY_RUN=1 ;;
-h|--help)    usage 0 ;;
-*)           die "unknown option '$arg' (try: $PROG --help)" ;;
*)            args+=("$arg") ;;
esac
done
set -- "${args[@]}"

case ${1:-} in
    add)              shift; cmd_add add "$@" ;;
    move|mv)          shift; cmd_add move "$@" ;;
    clean|rm|remove)  shift; cmd_clean "$@" ;;
    list|ls)          shift; cmd_list "$@" ;;
    flush)            shift; cmd_flush "$@" ;;
    undo)             shift; cmd_undo "$@" ;;
    backups)          shift; cmd_backups "$@" ;;
    "")               usage 2 ;;
    *)                is_ipv4 "$1" || die "unknown command '$1' (try: $PROG --help)"
    cmd_add add "$@" ;;
    esac
    
