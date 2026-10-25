# bash completion for goken
#


_goken_ips() {
    awk 'NF && $1 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ { print $1 }' "$1" 2>/dev/null | sort -u
}

# _goken_names <file> <ip> <same|other>
_goken_names() {
    awk -v ip="$2" -v mode="$3" '
        NF && $1 !~ /^#/ && ((mode == "same") == ($1 == ip)) {
            for (i = 2; i <= NF; i++) { if (substr($i, 1, 1) == "#") break; print $i }
        }
    ' "$1" 2>/dev/null | sort -u
}

_goken() {
    local cur=${COMP_WORDS[COMP_CWORD]}
    local file=${HOSTS_FILE:-/etc/hosts}
    local -a words=()
    local w

    if [[ $cur == -* ]]; then
        mapfile -t COMPREPLY < <(compgen -W '-n --dry-run -h --help' -- "$cur")
        return
    fi

    # Words typed so far, ignoring the program name and options.
    for w in "${COMP_WORDS[@]:1:COMP_CWORD-1}"; do
        [[ $w == -* ]] || words+=("$w")
    done

    if (( ${#words[@]} == 0 )); then
        mapfile -t COMPREPLY < <(compgen -W "add move clean list flush undo backups $(_goken_ips "$file")" -- "$cur")
        return
    fi

    local cmd=${words[0]}
    case $cmd in
        add|move|mv|clean|rm|remove|list|ls) ;;
        *) return ;;   # flush/undo/backups take no arguments; "<ip> <name>" takes new names
    esac

    if (( ${#words[@]} == 1 )); then
        mapfile -t COMPREPLY < <(compgen -W "$(_goken_ips "$file")" -- "$cur")
        return
    fi

    local ip=${words[1]} candidates
    case $cmd in
        clean|rm|remove) candidates=$(_goken_names "$file" "$ip" same) ;;
        move|mv)         candidates=$(_goken_names "$file" "$ip" other) ;;
        *)               return ;;
    esac

    # Don't offer names already typed on this command line.
    for w in "${words[@]:2}"; do
        candidates=$(grep -vxF -- "$w" <<< "$candidates" || :)
    done
    mapfile -t COMPREPLY < <(compgen -W "$candidates" -- "$cur")
}

complete -F _goken goken goken.sh
