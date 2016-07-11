## xscast

**xscast** is a tool for creating mini-screencasts of a terminal or other
window. It displays a bar on top of the terminal (with dzen2) that shows keys
as you press them, and it outputs an animated GIF.

Dependencies: `ffmpeg convert xwininfo xinput dzen2`. To install all
dependencies on Arch (some may already be installed):

    # pacman -S ffmpeg imagemagick xorg-utils xorg-server-utils dzen2

Usage: `./xscast.sh out.gif`

![](http://i.stack.imgur.com/L0WAq.gif)
