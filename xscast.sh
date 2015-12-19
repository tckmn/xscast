#!/bin/bash

# "config" (TODO, make this actually configurable)
# dzen stuff
dh=20
dpad=20
dfont=monospace
dalign=l
dfg='#ffffff'
dbg='#000000'
# keybindings
kfinish='C-S-Esc'
kclear='C-Esc'

# check for missing dependencies
for dep in byzanz-record xwininfo xinput dzen2
do
    type $dep &>/dev/null || { echo >&2 Missing dependency: $dep && exit 1; }
done

# argument parsing
outfile=
while [ $# -gt 0 ]
do
    case "$1" in
        -h|--help)
            # bash is stupid and doesn't let me indent with spaces
            cat <<EOS
Usage: $0 [OPTION]... [output-file]

  -h, --help          output this help message
  -c, --config        (re)configure xinput
EOS
            exit
            ;;
        -c|--config)
            xinput --list
            printf "%$(tput cols)s" | tr ' ' '='
            echo Find your keyboard in the list and type the number after id=
            read
            echo "$REPLY" > "$HOME/.xscastrc"
            exit
            ;;
        -*)
            echo >&2 "Unknown option \`$1'"
            exit 1
            ;;
        *)
            if [ -n "$outfile" ]
            then
                echo >&2 "Misplaced bare argument \`$1'"
                exit 1
            else
                outfile="$1"
            fi
            ;;
    esac
    shift
done

# few last checks before we start
[ -f "$HOME/.xscastrc" ] || { echo >&2 "Missing config file; try \`$0 --config'" && exit 1; }
[ -f "$HOME/.xscastlock" ] && { echo >&2 "Lockfile still exists ($HOME/.xscastlock)" && exit 1; }
[ -n "$outfile" ] || { echo >&2 Missing output file && exit 1; }

# use xwininfo to grab info about a certain window
echo Click on the window that you want to xscast
wininfo="$(xwininfo)"
# xwininfo -int | grep id: | grep -o '[0-9]*' | head -n1, i3-msg -t get_tree

# coords/dimensions
wx=$(echo "$wininfo" | grep 'Absolute upper-left X:' | grep -o '[0-9]*')
wy=$(echo "$wininfo" | grep 'Absolute upper-left Y:' | grep -o '[0-9]*')
ww=$(echo "$wininfo" | grep 'Width:' | grep -o '[0-9]*')
wh=$(echo "$wininfo" | grep 'Height:' | grep -o '[0-9]*')

# some setup for xinput parsing
touch "$HOME/.xscastlock"
m_shift=
m_ctrl=
m_alt=
cache=
declare -A keydict=(
    [escape]='Esc' [exclam]='!' [at]='@' [numbersign]='#' [dollar]='$'
    [percent]='%' [asciicircum]='^' [ampersand]='&' [asterisk]='*'
    [parenleft]='(' [parenright]=')' [minus]='-' [underscore]='_' [equal]='='
    [plus]='+' [backspace]='Bksp' [tab]='Tab' [iso_left_tab]='S-Tab'
    [bracketleft]='[' [braceleft]='{' [bracketright]=']' [braceright]='}'
    [return]='Return' [semicolon]=';' [colon]=':' [apostrophe]="'"
    [quotedbl]='"' [grave]='`' [asciitilde]='~' [backslash]='\' [bar]='|'
    [comma]=',' [less]='<' [period]='.' [greater]='>' [slash]='/'
    [question]='?' [multiply]='*' [space]='Space' [num_lock]='NumLock'
    [scroll_lock]='ScrlLock' [home]='Home' [up]='Up' [prior]='PgUp'
    [subtract]='-' [left]='Left' [begin]='???' [right]='Right' [add]='+'
    [end]='End' [down]='Down' [next]='PgDown' [insert]='Ins' [delete]='Del'
    [decimal]='.' [enter]='Return' [divide]='/' [print]='PrtScn'
    [sys_req]='SysRq' [pause]='Pause' [break]='Break' [multi_key]='Multi'
)
function lookup {
    lookup_result="$1"
    lookup_result="${lookup_result#KP_}"
    lclr="$(echo "$lookup_result" | tr A-Z a-z)"
    if [ -n "${keydict[$lclr]}" ]
    then
        lookup_result="${keydict[$lclr]}"
    fi
    echo "$lookup_result"
}

# start parsing xinput data
xinput --test "$(<$HOME/.xscastrc)" | while read line
do
    key="$(echo "$line" | awk '{print $3}' | xargs -I{} grep 'keycode *{} =' <(xmodmap -pke))"
    if [[ "$line" == 'key press'* ]]
    then
        case "$key" in
            *Shift_[LR]*) m_shift=1 ;;
            *Control_[LR]*) m_ctrl=1 ;;
            *Alt_[LR]*) m_alt=1 ;;
            *)
                unshifted="$(lookup "$(echo "$key" | awk '{print $4}')")"
                shifted="$(lookup "$(echo "$key" | awk '{print $5}')")"
                if [ -n "$m_shift" ]
                then
                    if [ "$shifted" = NoSymbol -o "$unshifted" = "$shifted" ]
                    then
                        name="S-$unshifted"
                    else
                        name="$shifted"
                    fi
                else
                    name="$unshifted"
                fi
                [ -n "$m_alt" ] && name="A-$name"
                [ -n "$m_ctrl" ] && name="C-$name"
                if [ "$name" = "$kfinish" ]
                then
                    rm "$HOME/.xscastlock"
                    break
                elif [ "$name" = "$kclear" ]
                then
                    cache=
                    echo
                else
                    if [ 1 -lt ${#name} ]
                    then
                        cache="${cache% } $name "
                    else
                        cache="$cache$name"
                    fi
                    echo "$cache"
                fi
                ;;
        esac
    elif [[ "$line" == 'key release'* ]]
    then
        case "$key" in
            *Shift_[LR]*) m_shift= ;;
            *Control_[LR]*) m_ctrl= ;;
            *Alt_[LR]*) m_alt= ;;
        esac
    fi
done | dzen2 -x $wx -y $((wy+wh-dh-dpad)) -w $ww -h $dh -fn "$dfont" -ta "$dalign" -fg "$dfg" -bg "$dbg" &

# error checks
[ $? -eq 0 ] || { echo >&2 "xinput error; try \`$0 --config'" && exit 1; }

# start recording
byzanz-record -x $wx -y $wy -w $ww -h $wh --delay=0 \
    -e 'bash -c "while [ -f "$HOME/.xscastlock" ]; do sleep 0.01; done"' "$outfile"
