# sbm.sh: settings for bm under Cygwin. The installer puts this file in
# /etc/profile.d, and each login shell reads it. The shell reads
# ~/.bash_profile and ~/.profile later, so settings there win.

# Open URLs with the default browser of Windows.
export SBM_OPEN="${SBM_OPEN:-cygstart}"
# Use the Windows clipboard. sed removes the CR at the end of each line.
export SBM_COPY="${SBM_COPY:-cp /dev/stdin /dev/clipboard}"
export SBM_PASTE="${SBM_PASTE:-sed s/\r\$// /dev/clipboard}"
# fzf.exe reads non-ASCII input only in full screen.
export SBM_FZF_OPTS="${SBM_FZF_OPTS:---no-height}"
