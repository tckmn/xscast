#!/bin/bash

# default config
dh=20
dpad=20
dfont=monospace
dalign=l
dfg='#ffffff'
dbg='#000000'
dbar=yes
delay=0
kfinish='C-Ins'
kclear='Ins'

# check for missing dependencies
for dep in ffmpeg convert xwininfo xinput dzen2
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

  -h, --help              output this help message
  -c, --config            (re)configure xinput
  -s, --height            set the height of the keystroke display box
  -p, --pad               set the space between the box and the window edge
  -f, --font              set the font of the keystrokes
  -a, --align             [l]eft, [c]enter, or [r]ight
  -t, --color, --fg       set the color of the keystrokes
  -b, --background, --bg  set the color of the keystroke box
  -n, --no-bar            do not display the bar containing keystrokes
  -d, --delay             set a delay before starting to record
EOS
            exit
            ;;
        -c|--config)
            if [ -f "$HOME/.xscastrc" ]
            then
                echo -n "WARNING: $HOME/.xscastrc already exists. Overwrite? [yn] "
                while :
                do
                    read
                    case "$REPLY" in
                        [Yy]*)
                            rm -rf "$HOME/.xscastrc"
                            break
                            ;;
                        [Nn]*)
                            echo 'No files changed; exiting'
                            exit 1
                            ;;
                        *)
                            echo Please respond with y or n
                            ;;
                    esac
                done
            fi
            xinput --list
            printf "%$(tput cols)s" | tr ' ' '='
            echo Find your keyboard in the list and type the number after id=
            read
            cat <<EOS > "$HOME/.xscastrc"
# the id that comes from \`xinput --list'
xinput_id='$REPLY'
# dzen config
dh=20
dpad=20
dfont=monospace
dalign=l
dfg='#ffffff'
dbg='#000000'
dbar=yes
delay=0
# keybindings (in the same format as xscast output)
kfinish='C-Ins'
kclear='Ins'
# other examples: C-S-F1, A-n, C-R, F11
EOS
            echo "Written to $HOME/.xscastrc. Please edit that file for further config options."
            exit
            ;;
        -s|--height) c_dh="$2"; shift ;;
        -p|--pad) c_dpad="$2"; shift ;;
        -f|--font) c_dfont="$2"; shift ;;
        -a|--align) c_dalign="$2"; shift ;;
        -t|--color|--fg) c_dfg="$2"; shift ;;
        -b|--background|--bg) c_dbg="$2"; shift ;;
        -n|--no-bar) c_dbar=no; : ;;
        -d|--delay) c_delay="$2"; shift ;;
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
[ -n "$outfile" ] || { echo >&2 Missing output file && exit 1; }
source "$HOME/.xscastrc"
[ -n "$xinput_id" ] || { echo >&2 "Malformed config file; try \`$0 --config' or editing $HOME/.xscastrc" && exit 1; }
dh="${c_dh:-$dh}"
dpad="${c_dpad:-$dpad}"
dfont="${c_dfont:-$dfont}"
dalign="${c_dalign:-$dalign}"
dfg="${c_dfg:-$dfg}"
dbg="${c_dbg:-$dbg}"
dbar="${c_dbar:-$dbar}"
delay="${c_delay:-$delay}"

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

# this is a really really bad idea, but it works
if [ "$dbar" != yes ]
then
    dzen2 () { cat >/dev/null; }
fi

sleep "$delay"

# start parsing xinput data
> .xscastpid
{
    for id in $xinput_id
    do
        xinput --test "$id" &
        echo $! >> .xscastpid
    done
} | while read line
do
    key="$(echo "$line" | awk '{print $3}' | xargs -I{} \
        grep 'keycode *{} =' <(xmodmap -pke))"
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
                    for pid in $(<.xscastpid)
                    do
                        kill $pid
                    done
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
done | dzen2 -x $wx -y $((wy+wh-dh-dpad)) -w $ww -h $dh -fn "$dfont" \
    -ta "$dalign" -fg "$dfg" -bg "$dbg" &

# error checks
[ $? -eq 0 ] || { echo >&2 "xinput error; try \`$0 --config'" && exit 1; }

# start recording
( ffmpeg -video_size ${ww}x$wh -framerate 25 -f x11grab -i :0.0+$wx,$wy \
    -f image2pipe -vcodec ppm - & echo $! >&3 ) 3>>.xscastpid | \
    convert -delay 4 -loop 0 - "$outfile"
rm .xscastpid
